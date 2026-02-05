<#
.SYNOPSIS
    AI Provider abstraction layer for Code Conclave.

.DESCRIPTION
    Provides a unified interface for multiple AI providers.
    Handles provider loading, dispatch, retry logic, connectivity testing,
    prompt caching (SharedContext), and model tiering.
#>

# Provider directory location
$Script:ProvidersDir = Join-Path $PSScriptRoot "providers"

function Get-SanitizedError {
    <#
    .SYNOPSIS
        Sanitize error messages to prevent API key and sensitive data leakage.
    .PARAMETER Message
        The error message to sanitize.
    .RETURNS
        Sanitized error message with sensitive data redacted.
    #>
    param([string]$Message)

    if (-not $Message) { return $Message }

    # Redact various API key patterns
    $sanitized = $Message -replace 'sk-ant-[a-zA-Z0-9_-]+', '[REDACTED_KEY]' `
                          -replace 'sk-[a-zA-Z0-9_-]{20,}', '[REDACTED_KEY]' `
                          -replace 'Bearer\s+\S+', 'Bearer [REDACTED]' `
                          -replace 'api-key:\s*\S+', 'api-key: [REDACTED]' `
                          -replace 'x-api-key:\s*\S+', 'x-api-key: [REDACTED]' `
                          -replace 'Authorization:\s*\S+', 'Authorization: [REDACTED]'

    # Redact user paths that might reveal system info
    if ($env:USERPROFILE) {
        $sanitized = $sanitized -replace [regex]::Escape($env:USERPROFILE), '[USER_HOME]'
    }
    if ($env:HOME) {
        $sanitized = $sanitized -replace [regex]::Escape($env:HOME), '[USER_HOME]'
    }

    return $sanitized
}

function Get-AIProvider {
    <#
    .SYNOPSIS
        Factory function to get the configured AI provider.
    .PARAMETER Config
        The effective configuration hashtable (from Get-EffectiveConfig).
    .PARAMETER ProviderOverride
        Optional provider name to override config.
    .PARAMETER ModelOverride
        Optional model name to override config.
    .PARAMETER EndpointOverride
        Optional endpoint to override config.
    .RETURNS
        Hashtable with: Name, Config (provider-specific), CommonConfig (shared ai settings)
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string]$ProviderOverride,
        [string]$ModelOverride,
        [string]$EndpointOverride
    )

    # Determine provider name
    $providerName = if ($ProviderOverride) { $ProviderOverride }
                    elseif ($Config.ai -and $Config.ai.provider) { $Config.ai.provider }
                    else { "anthropic" }

    $providerFile = Join-Path $Script:ProvidersDir "$providerName.ps1"

    if (-not (Test-Path $providerFile)) {
        $available = (Get-ChildItem $Script:ProvidersDir -Filter "*.ps1" -ErrorAction SilentlyContinue).BaseName -join ", "
        throw "AI provider not found: $providerName. Available: $available"
    }

    # Get provider-specific config
    $providerConfig = @{}
    if ($Config.ai -and $Config.ai[$providerName]) {
        $providerConfig = $Config.ai[$providerName]
    }

    # Apply CLI overrides
    if ($ModelOverride) {
        # For anthropic, override 'model'; for azure-openai, override 'deployment'
        if ($providerName -eq "azure-openai") {
            $providerConfig.deployment = $ModelOverride
        }
        else {
            $providerConfig.model = $ModelOverride
        }
    }
    if ($EndpointOverride) {
        $providerConfig.endpoint = $EndpointOverride
    }

    # Build common config
    $commonConfig = @{}
    if ($Config.ai) {
        $commonConfig = $Config.ai.Clone()
        # Remove provider-specific sub-configs from common
        foreach ($key in @("anthropic", "azure-openai", "openai", "ollama")) {
            $commonConfig.Remove($key)
        }
    }

    return @{
        Name         = $providerName
        Config       = $providerConfig
        CommonConfig = $commonConfig
        ProviderFile = $providerFile
    }
}

function Invoke-AICompletion {
    <#
    .SYNOPSIS
        Send a completion request to the configured AI provider.
    .PARAMETER Provider
        Provider info from Get-AIProvider.
    .PARAMETER SharedContext
        Cacheable shared content (CONTRACTS + project context). Placed before
        SystemPrompt to form a stable prefix for prompt caching.
        For Anthropic: sent as separate system block with cache_control.
        For others: concatenated with SystemPrompt (automatic prefix caching).
    .PARAMETER SystemPrompt
        Agent-specific system prompt (instructions).
    .PARAMETER UserPrompt
        The user prompt (review task).
    .PARAMETER Tier
        Agent tier: "primary" (full model) or "lite" (cheaper model).
    .PARAMETER MaxTokens
        Maximum tokens in response (optional, uses config default).
    .RETURNS
        Hashtable with: Success, Content, TokensUsed, Error
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider,

        [string]$SharedContext,

        [Parameter(Mandatory)]
        [string]$SystemPrompt,

        [Parameter(Mandatory)]
        [string]$UserPrompt,

        [string]$Tier = "primary",

        [int]$MaxTokens = 0
    )

    # Get retry settings from common config
    $maxAttempts = if ($Provider.CommonConfig.retry_attempts) { $Provider.CommonConfig.retry_attempts } else { 3 }
    $delaySeconds = if ($Provider.CommonConfig.retry_delay_seconds) { $Provider.CommonConfig.retry_delay_seconds } else { 5 }

    $lastResult = $null

    # Source provider file to ensure function is available in this scope
    if ($Provider.ProviderFile -and (Test-Path $Provider.ProviderFile)) {
        . $Provider.ProviderFile
    }

    # Resolve tier to provider-specific model/deployment
    $tierModel = $null
    $tierDeployment = $null
    if ($Tier -eq "lite") {
        switch ($Provider.Name) {
            "anthropic" {
                $tierModel = if ($Provider.Config.lite_model) { $Provider.Config.lite_model } else { $null }
            }
            "azure-openai" {
                $tierDeployment = if ($Provider.Config.lite_deployment) { $Provider.Config.lite_deployment } else { $null }
            }
            "openai" {
                $tierModel = if ($Provider.Config.lite_model) { $Provider.Config.lite_model } else { $null }
            }
            # ollama: ignore tier (local, free)
        }
    }

    $rateLimitMax = [math]::Max($maxAttempts, 5)
    for ($attempt = 1; $attempt -le $rateLimitMax; $attempt++) {
        # Dispatch to provider-specific implementation
        $result = switch ($Provider.Name) {
            "anthropic" {
                # Anthropic supports explicit cache_control via SharedContext param
                Invoke-AnthropicCompletion -Provider $Provider `
                    -SharedContext $SharedContext `
                    -SystemPrompt $SystemPrompt `
                    -UserPrompt $UserPrompt `
                    -Model $tierModel `
                    -MaxTokens $MaxTokens
            }
            "azure-openai" {
                # Azure: concatenate shared context into system prompt; caching is automatic
                $fullSystem = if ($SharedContext) { "$SharedContext`n`n$SystemPrompt" } else { $SystemPrompt }
                Invoke-AzureOpenAICompletion -Provider $Provider `
                    -SystemPrompt $fullSystem `
                    -UserPrompt $UserPrompt `
                    -Deployment $tierDeployment `
                    -MaxTokens $MaxTokens
            }
            "openai" {
                # OpenAI: concatenate shared context into system prompt; caching is automatic
                $fullSystem = if ($SharedContext) { "$SharedContext`n`n$SystemPrompt" } else { $SystemPrompt }
                Invoke-OpenAICompletion -Provider $Provider `
                    -SystemPrompt $fullSystem `
                    -UserPrompt $UserPrompt `
                    -Model $tierModel `
                    -MaxTokens $MaxTokens
            }
            "ollama" {
                # Ollama: local/free, no caching or tiering
                $fullSystem = if ($SharedContext) { "$SharedContext`n`n$SystemPrompt" } else { $SystemPrompt }
                Invoke-OllamaCompletion -Provider $Provider `
                    -SystemPrompt $fullSystem `
                    -UserPrompt $UserPrompt `
                    -MaxTokens $MaxTokens
            }
            default { throw "Unknown provider: $($Provider.Name)" }
        }

        $lastResult = $result

        # Success - return immediately
        if ($result.Success) {
            return $result
        }

        # Check if error is retryable
        $errorMsg = $result.Error
        $isRateLimit = $errorMsg -match '429'
        $isRetryable = ($isRateLimit -or $errorMsg -match '(500|502|503|504|timeout|timed out|request was aborted)') -and
                       $errorMsg -notmatch '(400|401|403|404|not found|unauthorized|forbidden|bad request)'

        # Rate limits get more attempts (up to $rateLimitMax); other errors use $maxAttempts
        $effectiveMax = if ($isRateLimit) { $rateLimitMax } else { $maxAttempts }

        if (-not $isRetryable -or $attempt -ge $effectiveMax) {
            # Sanitize error before returning
            $result.Error = Get-SanitizedError $errorMsg
            return $result
        }

        # Rate limits: wait 30s base (survives 60s rate window). Others: standard backoff.
        $baseDelay = if ($isRateLimit) { 30 } else { $delaySeconds }
        $waitTime = $baseDelay * [math]::Min($attempt, 3)
        $safeMsg = Get-SanitizedError $errorMsg
        $retryMsg = if ($isRateLimit) { "Rate limited" } else { "AI request failed" }
        Write-Warning "  $retryMsg (attempt $attempt/$effectiveMax): $safeMsg. Retrying in ${waitTime}s..."
        Start-Sleep -Seconds $waitTime
    }

    return $lastResult
}

function Test-AIProvider {
    <#
    .SYNOPSIS
        Test connectivity to the configured AI provider.
    .PARAMETER Provider
        Provider info from Get-AIProvider.
    .RETURNS
        Boolean indicating if the provider is reachable and working.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider
    )

    try {
        $result = Invoke-AICompletion -Provider $Provider `
            -SystemPrompt "You are a helpful assistant." `
            -UserPrompt "Respond with exactly: OK" `
            -MaxTokens 10

        return $result.Success -and $result.Content -match "OK"
    }
    catch {
        $safeMsg = Get-SanitizedError $_.Exception.Message
        Write-Warning "Provider test failed: $safeMsg"
        return $false
    }
}

# Export if running as module
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Get-AIProvider, Invoke-AICompletion, Test-AIProvider, Get-SanitizedError
}
