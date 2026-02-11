<#
.SYNOPSIS
    Standards management commands for Code Conclave.

.DESCRIPTION
    List available compliance standards and show detailed information.

.PARAMETER Command
    The subcommand to run: list or info

.PARAMETER StandardId
    The standard ID for info command.

.EXAMPLE
    .\standards.ps1 list
    .\standards.ps1 info -StandardId cmmc-l2
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet("list", "info")]
    [string]$Command = "list",

    [string]$StandardId
)

# Path setup
$Script:ToolRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script:StandardsDir = Join-Path (Join-Path $ToolRoot "core") "standards"

# Source dependencies
. (Join-Path $PSScriptRoot "..\lib\yaml-parser.ps1")
. (Join-Path $PSScriptRoot "..\lib\mapping-engine.ps1")

function Show-StandardsList {
    <#
    .SYNOPSIS
        Display all available compliance standards.
    #>

    Write-Host ""
    Write-Host "  Available Compliance Standards" -ForegroundColor Cyan
    Write-Host "  ===============================" -ForegroundColor Cyan
    Write-Host ""

    $standards = Get-AvailableStandards -StandardsDir $Script:StandardsDir

    if ($standards.Count -eq 0) {
        Write-Host "  No standards found in: $Script:StandardsDir" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Group by domain
    $grouped = $standards | Group-Object -Property Domain

    foreach ($group in $grouped | Sort-Object Name) {
        Write-Host "  [$($group.Name)]" -ForegroundColor Yellow

        foreach ($std in $group.Group | Sort-Object Id) {
            Write-Host "    " -NoNewline
            Write-Host $std.Id -ForegroundColor White -NoNewline
            Write-Host " - $($std.Name)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    Write-Host "  Usage:" -ForegroundColor DarkGray
    Write-Host "    ccl -Standards info -Standard <standard-id>" -ForegroundColor DarkGray
    Write-Host "    ccl -Project ./myproject -Standard <standard-id>" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-StandardInfo {
    <#
    .SYNOPSIS
        Display detailed information about a specific standard.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$StandardId
    )

    $std = Get-StandardById -StandardId $StandardId -StandardsDir $Script:StandardsDir

    if (-not $std) {
        Write-Host ""
        Write-Host "  Standard not found: $StandardId" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Available standards:" -ForegroundColor Gray
        $available = Get-AvailableStandards -StandardsDir $Script:StandardsDir
        foreach ($a in $available) {
            Write-Host "    - $($a.Id)" -ForegroundColor Gray
        }
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  $($std.name)" -ForegroundColor Cyan
    Write-Host "  $("=" * ($std.name.Length + 2))" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ID:      " -NoNewline -ForegroundColor Gray
    Write-Host $std.id -ForegroundColor White
    Write-Host "  Domain:  " -NoNewline -ForegroundColor Gray
    Write-Host $std.domain -ForegroundColor White
    Write-Host "  Version: " -NoNewline -ForegroundColor Gray
    Write-Host $std.version -ForegroundColor White
    Write-Host ""

    # Description
    if ($std.description) {
        Write-Host "  Description:" -ForegroundColor Yellow
        $descLines = $std.description -split "`n"
        foreach ($line in $descLines) {
            if ($line.Trim()) {
                Write-Host "    $($line.Trim())" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    # Control statistics
    $controls = Get-AllControls -Standard $std
    $controlCount = $controls.Count

    Write-Host "  Controls:" -ForegroundColor Yellow
    Write-Host "    Total: " -NoNewline -ForegroundColor Gray
    Write-Host $controlCount -ForegroundColor White

    # Critical controls
    $criticalCount = ($controls | Where-Object { $_.Critical }).Count
    if ($criticalCount -gt 0) {
        Write-Host "    Critical: " -NoNewline -ForegroundColor Gray
        Write-Host $criticalCount -ForegroundColor Red
    }

    Write-Host ""

    # Agent coverage breakdown
    Write-Host "  Agent Coverage:" -ForegroundColor Yellow

    $agentCoverage = @{}
    foreach ($ctrl in $controls) {
        if ($ctrl.Agents) {
            foreach ($agent in $ctrl.Agents) {
                $agentUpper = $agent.ToUpper()
                if (-not $agentCoverage.ContainsKey($agentUpper)) {
                    $agentCoverage[$agentUpper] = 0
                }
                $agentCoverage[$agentUpper]++
            }
        }
    }

    $agentColors = @{
        SENTINEL  = "Yellow"
        GUARDIAN  = "Red"
        ARCHITECT = "Blue"
        NAVIGATOR = "Cyan"
        HERALD    = "Magenta"
        OPERATOR  = "Green"
    }

    foreach ($agent in ($agentCoverage.Keys | Sort-Object)) {
        $count = $agentCoverage[$agent]
        $color = if ($agentColors.ContainsKey($agent)) { $agentColors[$agent] } else { "White" }
        Write-Host "    " -NoNewline
        Write-Host $agent.PadRight(12) -NoNewline -ForegroundColor $color
        Write-Host "$count controls" -ForegroundColor Gray
    }

    Write-Host ""

    # Domain breakdown
    if ($std.domains) {
        Write-Host "  Domains:" -ForegroundColor Yellow
        foreach ($domain in $std.domains) {
            $domainControlCount = if ($domain.controls) { $domain.controls.Count } else { 0 }
            Write-Host "    $($domain.id): " -NoNewline -ForegroundColor White
            Write-Host "$($domain.name) ($domainControlCount controls)" -ForegroundColor Gray
        }
    }
    elseif ($std.subparts) {
        Write-Host "  Subparts:" -ForegroundColor Yellow
        foreach ($subpart in $std.subparts) {
            $subpartControlCount = 0
            if ($subpart.sections) {
                foreach ($section in $subpart.sections) {
                    if ($section.subsections) {
                        $subpartControlCount += $section.subsections.Count
                    }
                    else {
                        $subpartControlCount++
                    }
                }
            }
            Write-Host "    $($subpart.id): " -NoNewline -ForegroundColor White
            Write-Host "$($subpart.name) ($subpartControlCount controls)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor DarkGray
    Write-Host "    ccl -Project ./myproject -Standard $StandardId" -ForegroundColor DarkGray
    Write-Host "    ccl -Map ./myproject/.code-conclave -Standard $StandardId" -ForegroundColor DarkGray
    Write-Host ""
}

# Main execution
switch ($Command) {
    "list" {
        Show-StandardsList
    }
    "info" {
        if (-not $StandardId) {
            Write-Host ""
            Write-Host "  Please specify -StandardId for info command" -ForegroundColor Red
            Write-Host "  Example: .\standards.ps1 info -StandardId cmmc-l2" -ForegroundColor Gray
            Write-Host ""
            exit 1
        }
        Show-StandardInfo -StandardId $StandardId
    }
}
