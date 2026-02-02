<#
.SYNOPSIS
    Initialize git repo and push to GitHub as private
#>

param(
    [string]$RepoName = "code-conclave",
    [string]$Description = "AI-powered code review orchestrator - deploy 6 specialized agents to review your codebase"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Setting up GitHub repository..." -ForegroundColor Cyan
Write-Host ""

# Check for gh CLI
$ghExists = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghExists) {
    Write-Host "  ERROR: GitHub CLI (gh) not found." -ForegroundColor Red
    Write-Host "  Install from: https://cli.github.com/" -ForegroundColor Gray
    exit 1
}

# Check gh auth
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Not authenticated with GitHub CLI." -ForegroundColor Red
    Write-Host "  Run: gh auth login" -ForegroundColor Gray
    exit 1
}

Push-Location $PSScriptRoot

try {
    # Initialize git if needed
    if (-not (Test-Path ".git")) {
        Write-Host "  Initializing git repository..." -ForegroundColor Yellow
        git init
        git add .
        git commit -m "Initial commit - Code Conclave v2.0"
    }
    else {
        # Repo exists, make sure everything is committed
        $status = git status --porcelain
        if ($status) {
            Write-Host "  Committing changes..." -ForegroundColor Yellow
            git add .
            git commit -m "Initial commit - Code Conclave v2.0"
        }
    }

    # Create private repo on GitHub
    Write-Host "  Creating private repository on GitHub..." -ForegroundColor Yellow
    gh repo create $RepoName --private --description $Description --source . --push

    Write-Host ""
    Write-Host "  SUCCESS! Private repo created." -ForegroundColor Green
    Write-Host ""

    $username = gh api user -q ".login"
    Write-Host "  URL: https://github.com/$username/$RepoName" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
}
finally {
    Pop-Location
}
