<#
.SYNOPSIS
    AI Provider abstraction layer for Code Conclave.

.DESCRIPTION
    Provides a unified interface for multiple AI providers.
    Handles provider loading, dispatch, retry logic, and connectivity testing.
#>

# Provider directory location
$Script:ProvidersDir = Join-Path $PSScriptRoot "providers"

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
    .PARAMETER SystemPrompt
        The system prompt (agent instructions + contracts).
    .PARAMETER UserPrompt
        The user prompt (project context + task).
    .PARAMETER MaxTokens
        Maximum tokens in response (optional, uses config default).
    .RETURNS
        Hashtable with: Success, Content, TokensUsed, Error
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider,

        [Parameter(Mandatory)]
        [string]$SystemPrompt,

        [Parameter(Mandatory)]
        [string]$UserPrompt,

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

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        # Dispatch to provider-specific implementation
        $result = switch ($Provider.Name) {
            "anthropic"    { Invoke-AnthropicCompletion -Provider $Provider -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
            "azure-openai" { Invoke-AzureOpenAICompletion -Provider $Provider -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
            "openai"       { Invoke-OpenAICompletion -Provider $Provider -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
            "ollama"       { Invoke-OllamaCompletion -Provider $Provider -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
            default        { throw "Unknown provider: $($Provider.Name)" }
        }

        $lastResult = $result

        # Success - return immediately
        if ($result.Success) {
            return $result
        }

        # Check if error is retryable
        $errorMsg = $result.Error
        $isRetryable = $errorMsg -match '(429|500|502|503|504|timeout|timed out|request was aborted)' -and
                       $errorMsg -notmatch '(400|401|403|404|not found|unauthorized|forbidden|bad request)'

        if (-not $isRetryable -or $attempt -eq $maxAttempts) {
            # Sanitize error before returning - strip API keys, endpoints, and paths
            $sanitized = $errorMsg -replace 'sk-ant-[a-zA-Z0-9_-]+', '[REDACTED]' `
                                   -replace 'sk-[a-zA-Z0-9_-]{20,}', '[REDACTED]' `
                                   -replace 'Bearer\s+\S+', 'Bearer [REDACTED]'
            $result.Error = $sanitized
            return $result
        }

        # Wait before retry with exponential backoff
        $waitTime = $delaySeconds * $attempt
        $safeMsg = $errorMsg -replace 'sk-ant-[a-zA-Z0-9_-]+', '[REDACTED]' -replace 'sk-[a-zA-Z0-9_-]{20,}', '[REDACTED]'
        Write-Warning "  AI request failed (attempt $attempt/$maxAttempts): $safeMsg. Retrying in ${waitTime}s..."
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
        Write-Warning "Provider test failed: $_"
        return $false
    }
}

# Export if running as module
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Get-AIProvider, Invoke-AICompletion, Test-AIProvider
}
