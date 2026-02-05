<#
.SYNOPSIS
    Azure OpenAI Service provider for Code Conclave.

.DESCRIPTION
    Implements direct API calls to Azure OpenAI Chat Completions endpoint.
#>

function Invoke-AzureOpenAICompletion {
    param(
        [hashtable]$Provider,
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens
    )

    $config = $Provider.Config
    $common = $Provider.CommonConfig

    # Validate required config
    if (-not $config.endpoint) {
        return @{
            Success = $false
            Content = $null
            TokensUsed = $null
            Error = "Azure OpenAI endpoint not configured. Set ai.azure-openai.endpoint in config.yaml"
        }
    }

    if (-not $config.deployment) {
        return @{
            Success = $false
            Content = $null
            TokensUsed = $null
            Error = "Azure OpenAI deployment not configured. Set ai.azure-openai.deployment in config.yaml"
        }
    }

    # Get API key from environment
    $apiKeyEnv = if ($config.api_key_env) { $config.api_key_env } else { "AZURE_OPENAI_KEY" }
    $apiKey = [Environment]::GetEnvironmentVariable($apiKeyEnv)

    if (-not $apiKey) {
        return @{
            Success = $false
            Content = $null
            TokensUsed = $null
            Error = "API key not found in environment variable: $apiKeyEnv"
        }
    }

    $apiVersion = if ($config.api_version) { $config.api_version } else { "2024-02-15-preview" }
    $maxTok = if ($MaxTokens -gt 0) { $MaxTokens }
              elseif ($config.max_tokens) { $config.max_tokens }
              else { 16000 }
    $temperature = if ($null -ne $common.temperature) { $common.temperature } else { 0.3 }
    $timeout = if ($common.timeout_seconds) { $common.timeout_seconds } else { 300 }

    $endpoint = $config.endpoint.TrimEnd('/')
    $uri = "$endpoint/openai/deployments/$($config.deployment)/chat/completions?api-version=$apiVersion"

    $headers = @{
        "Content-Type" = "application/json"
        "api-key"      = $apiKey
    }

    $body = @{
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
            -Uri $uri `
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
