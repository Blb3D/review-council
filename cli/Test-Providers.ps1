<#
.SYNOPSIS
    Test all configured AI providers for Code Conclave.

.DESCRIPTION
    Validates connectivity to each AI provider by sending a simple
    test request. Useful for verifying API keys and configuration.

.PARAMETER ProjectPath
    Path to a project with .code-conclave/config.yaml (optional).

.PARAMETER Provider
    Test only a specific provider instead of all.

.EXAMPLE
    .\Test-Providers.ps1

.EXAMPLE
    .\Test-Providers.ps1 -Provider anthropic
#>

param(
    [string]$ProjectPath = ".",
    [string]$Provider
)

$ErrorActionPreference = "Stop"

# Load libraries
$libDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $libDir "yaml-parser.ps1")
. (Join-Path $libDir "config-loader.ps1")
. (Join-Path $libDir "ai-engine.ps1")

Write-Host ""
Write-Host "  Code Conclave - Provider Test" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor Cyan
Write-Host ""

# Load config
$config = Get-DefaultConfig

$providers = if ($Provider) {
    @($Provider)
} else {
    @("anthropic", "azure-openai", "openai", "ollama")
}

foreach ($providerName in $providers) {
    Write-Host "  [$providerName]" -ForegroundColor Yellow -NoNewline

    try {
        $providerInfo = Get-AIProvider -Config $config -ProviderOverride $providerName

        $result = Invoke-AICompletion -Provider $providerInfo `
            -SystemPrompt "You are a helpful assistant." `
            -UserPrompt "Say 'Hello from $providerName' and nothing else." `
            -MaxTokens 50

        if ($result.Success) {
            Write-Host " OK" -ForegroundColor Green
            Write-Host "    Response: $($result.Content.Trim())" -ForegroundColor Gray
            if ($result.TokensUsed) {
                Write-Host "    Tokens: $($result.TokensUsed.Input) in / $($result.TokensUsed.Output) out" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Error: $($result.Error)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " ERROR" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Yellow
    }

    Write-Host ""
}

Write-Host "  Done." -ForegroundColor Cyan
Write-Host ""
