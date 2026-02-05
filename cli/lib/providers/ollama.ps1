<#
.SYNOPSIS
    Ollama local model provider for Code Conclave.

.DESCRIPTION
    Enables running Code Conclave with local LLMs via Ollama.
    No API key required. Must have Ollama running locally.
#>

function Invoke-OllamaCompletion {
    param(
        [hashtable]$Provider,
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens
    )

    $config = $Provider.Config
    $common = $Provider.CommonConfig

    $endpoint = if ($config.endpoint) { $config.endpoint } else { "http://localhost:11434" }
    $model = if ($config.model) { $config.model } else { "llama3.1:70b" }
    $timeout = if ($common.timeout_seconds) { $common.timeout_seconds } else { 600 }
    $maxTok = if ($MaxTokens -gt 0) { $MaxTokens }
              elseif ($config.max_tokens) { $config.max_tokens }
              else { 8000 }

    $uri = "$($endpoint.TrimEnd('/'))/api/chat"

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
        stream  = $false
        options = @{
            num_predict = $maxTok
        }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod `
            -Uri $uri `
            -Method POST `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -ContentType "application/json" `
            -TimeoutSec $timeout

        return @{
            Success    = $true
            Content    = $response.message.content
            TokensUsed = @{
                Input  = $response.prompt_eval_count
                Output = $response.eval_count
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
