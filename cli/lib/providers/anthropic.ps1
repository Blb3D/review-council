<#
.SYNOPSIS
    Anthropic Claude API provider for Code Conclave.

.DESCRIPTION
    Implements direct API calls to the Anthropic Messages API.
    Supports prompt caching via cache_control for multi-agent cost reduction.
#>

function Invoke-AnthropicCompletion {
    param(
        [hashtable]$Provider,
        [string]$SharedContext,
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [string]$Model,
        [int]$MaxTokens
    )

    $config = $Provider.Config
    $common = $Provider.CommonConfig

    # Get API key from environment
    $apiKeyEnv = if ($config.api_key_env) { $config.api_key_env } else { "ANTHROPIC_API_KEY" }
    $apiKey = [Environment]::GetEnvironmentVariable($apiKeyEnv)

    if (-not $apiKey) {
        return @{
            Success = $false
            Content = $null
            TokensUsed = $null
            Error = "API key not found in environment variable: $apiKeyEnv"
        }
    }

    # Model override (for tier support), then config, then default
    $modelName = if ($Model) { $Model }
                 elseif ($config.model) { $config.model }
                 else { "claude-sonnet-4-5-20250929" }
    $maxTok = if ($MaxTokens -gt 0) { $MaxTokens }
              elseif ($config.max_tokens) { $config.max_tokens }
              else { 16000 }
    $temperature = if ($null -ne $common.temperature) { $common.temperature } else { 0.3 }
    $timeout = if ($common.timeout_seconds) { $common.timeout_seconds } else { 300 }

    $headers = @{
        "Content-Type"      = "application/json"
        "x-api-key"         = $apiKey
        "anthropic-version" = "2023-06-01"
    }

    # Build system prompt — use array format with cache_control when SharedContext provided
    if ($SharedContext) {
        $systemContent = @(
            @{
                type = "text"
                text = $SharedContext
                cache_control = @{ type = "ephemeral" }
            },
            @{
                type = "text"
                text = $SystemPrompt
            }
        )
    } else {
        $systemContent = $SystemPrompt
    }

    $body = @{
        model       = $modelName
        max_tokens  = $maxTok
        temperature = $temperature
        system      = $systemContent
        messages    = @(
            @{
                role    = "user"
                content = $UserPrompt
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.anthropic.com/v1/messages" `
            -Method POST `
            -Headers $headers `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec $timeout

        $content = $response.content | Where-Object { $_.type -eq "text" } |
                   Select-Object -ExpandProperty text -First 1

        return @{
            Success    = $true
            Content    = $content
            TokensUsed = @{
                Input      = $response.usage.input_tokens
                Output     = $response.usage.output_tokens
                CacheRead  = if ($response.usage.cache_read_input_tokens) { $response.usage.cache_read_input_tokens } else { 0 }
                CacheWrite = if ($response.usage.cache_creation_input_tokens) { $response.usage.cache_creation_input_tokens } else { 0 }
            }
            Error      = $null
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errMsg += " | Details: $($_.ErrorDetails.Message)"
        }
        return @{
            Success    = $false
            Content    = $null
            TokensUsed = $null
            Error      = $errMsg
        }
    }
}
