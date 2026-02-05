<#
.SYNOPSIS
    OpenAI API provider for Code Conclave.

.DESCRIPTION
    Implements direct API calls to the OpenAI Chat Completions endpoint.
#>

function Invoke-OpenAICompletion {
    param(
        [hashtable]$Provider,
        [string]$SystemPrompt,
        [string]$UserPrompt,
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

    $model = if ($config.model) { $config.model } else { "gpt-4o" }
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
        model    = $model
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

        return @{
            Success    = $true
            Content    = $content
            TokensUsed = @{
                Input  = $response.usage.prompt_tokens
                Output = $response.usage.completion_tokens
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
