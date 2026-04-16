<#
.SYNOPSIS
    Launch Code Conclave Dashboard with live monitoring

.EXAMPLE
    .\start-dashboard.ps1 -Project "C:\path\to\your\project"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Project
)

$dashboardDir = Join-Path $PSScriptRoot "dashboard"

# Check if node_modules exists
if (-not (Test-Path (Join-Path $dashboardDir "node_modules"))) {
    Write-Host "Installing dashboard dependencies..." -ForegroundColor Yellow
    Push-Location $dashboardDir
    npm install
    Pop-Location
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    CODE CONCLAVE - Live Dashboard" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Project: $Project" -ForegroundColor White
Write-Host "  Dashboard will open at: http://localhost:3847" -ForegroundColor Green
Write-Host ""
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Start server
Push-Location $dashboardDir
Start-Process "http://localhost:3847" # Open browser
node server.js --project $Project
Pop-Location
