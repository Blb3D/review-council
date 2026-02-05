<#
.SYNOPSIS
    Anthropic Claude API provider for Code Conclave.

.DESCRIPTION
    Implements direct API calls to the Anthropic Messages API.
    Uses Invoke-RestMethod instead of the Claude CLI.
#>

function Invoke-AnthropicCompletion {
    param(
        [hashtable]$Provider,
        [string]$SystemPrompt,
        [string]$UserPrompt,
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

    $model = if ($config.model) { $config.model } else { "claude-sonnet-4-20250514" }
    $maxTok = if ($MaxTokens -gt 0) { $MaxTokens }
              elseif ($config.max_tokens) { $config.max_tokens }
              else { 16000 }
    $temperature = if ($null -ne $common.temperature) { $common.temperature } else { 0.3 }
    $timeout = if ($common.timeout_seconds) { $common.timeout_seconds } else { 300 }

    $headers = @{
        "Content-Type"     = "application/json"
        "x-api-key"        = $apiKey
        "anthropic-version" = "2023-06-01"
    }

    # Anthropic Messages API uses system as a top-level field
    $body = @{
        model      = $model
        max_tokens = $maxTok
        temperature = $temperature
        system     = $SystemPrompt
        messages   = @(
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
                Input  = $response.usage.input_tokens
                Output = $response.usage.output_tokens
            }
            Error      = $null
        }
    }
    catch {
        return @{
            Success    = $false
            Content    = $null
            TokensUsed = $null
            Error      = $_.Exception.Message
        }
    }
}
