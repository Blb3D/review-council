<#
.SYNOPSIS
    OpenAI API provider for Code Conclave.

.DESCRIPTION
    Implements direct API calls to the OpenAI Chat Completions endpoint.
    Supports automatic prompt caching and model tiering via lite_model.
#>

function Invoke-OpenAICompletion {
    param(
        [hashtable]$Provider,
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [string]$Model,
        [int]$MaxTokens
    )

    $config = $Provider.Config
    $common = $Provider.CommonConfig

    # Get API key from environment
    $apiKeyEnv = if ($config.api_key_env) { $config.api_key_env } else { "OPENAI_API_KEY" }
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
                 else { "gpt-4o" }
    $maxTok = if ($MaxTokens -gt 0) { $MaxTokens }
              elseif ($config.max_tokens) { $config.max_tokens }
              else { 16000 }
    $temperature = if ($null -ne $common.temperature) { $common.temperature } else { 0.3 }
    $timeout = if ($common.timeout_seconds) { $common.timeout_seconds } else { 300 }

    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $apiKey"
    }

    $body = @{
        model    = $modelName
        messages = @(
            @{
                role    = "system"
                content = $SystemPrompt
            },
            @{
                role    = "user"
                content = $UserPrompt
            }
        )
        max_tokens  = $maxTok
        temperature = $temperature
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/chat/completions" `
            -Method POST `
            -Headers $headers `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec $timeout

        $content = $response.choices[0].message.content

        # Extract cache metrics (OpenAI reports cached tokens automatically)
        $cachedTokens = 0
        if ($response.usage.prompt_tokens_details -and $response.usage.prompt_tokens_details.cached_tokens) {
            $cachedTokens = $response.usage.prompt_tokens_details.cached_tokens
        }

        return @{
            Success    = $true
            Content    = $content
            TokensUsed = @{
                Input      = $response.usage.prompt_tokens
                Output     = $response.usage.completion_tokens
                CacheRead  = $cachedTokens
                CacheWrite = 0
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
