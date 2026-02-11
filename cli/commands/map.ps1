<#
.SYNOPSIS
    Map existing findings to compliance standards.

.DESCRIPTION
    Analyzes existing Code Conclave review findings and maps them to
    compliance standard controls. Generates a compliance mapping report
    showing coverage and gaps.

.PARAMETER ReviewsPath
    Path to the reviews directory (typically .code-conclave/reviews).

.PARAMETER StandardId
    The compliance standard ID to map against.

.PARAMETER OutputPath
    Optional custom output path for the report.

.EXAMPLE
    .\map.ps1 -ReviewsPath "C:\project\.code-conclave\reviews" -StandardId cmmc-l2
#>

param(
    [Parameter(Mandatory)]
    [string]$ReviewsPath,

    [Parameter(Mandatory)]
    [string]$StandardId,

    [string]$OutputPath
)

# Path setup
$Script:ToolRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script:StandardsDir = Join-Path (Join-Path $ToolRoot "core") "standards"

# Source dependencies
. (Join-Path $PSScriptRoot "..\lib\yaml-parser.ps1")
. (Join-Path $PSScriptRoot "..\lib\mapping-engine.ps1")

function Parse-FindingsMarkdown {
    <#
    .SYNOPSIS
        Extract findings from a markdown findings file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [string]$AgentName = "UNKNOWN"
    )

    $findings = @()

    # Pattern 1: ### AGENT-001: Title [SEVERITY]
    $pattern1 = '###\s+([A-Z]+\-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]'
    $matches1 = [regex]::Matches($Content, $pattern1)

    foreach ($match in $matches1) {
        $findings += @{
            Id = $match.Groups[1].Value
            Title = $match.Groups[2].Value.Trim()
            Severity = $match.Groups[3].Value
            Agent = ($match.Groups[1].Value -split '-')[0]
        }
    }

    # Pattern 2: ## [SEVERITY] Finding Title (with ID in body)
    # This catches alternative formats
    $pattern2 = '##\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]\s*(.+?)(?:\r?\n)'

    # Counter for auto-generated IDs
    $autoIdCounter = 0
    $matches2 = [regex]::Matches($Content, $pattern2)

    foreach ($match in $matches2) {
        # Check if we already have this finding
        $title = $match.Groups[2].Value.Trim()
        $existing = $findings | Where-Object { $_.Title -eq $title }

        if (-not $existing) {
            # Try to extract ID from nearby content
            $idPattern = "($AgentName-\d+)"
            $idMatch = [regex]::Match($Content.Substring($match.Index, [Math]::Min(500, $Content.Length - $match.Index)), $idPattern)

            $autoIdCounter++
            $id = if ($idMatch.Success) { $idMatch.Groups[1].Value } else { "$AgentName-AUTO-$autoIdCounter" }

            $findings += @{
                Id = $id
                Title = $title
                Severity = $match.Groups[1].Value
                Agent = $AgentName
            }
        }
    }

    return $findings
}

function Get-AllFindings {
    <#
    .SYNOPSIS
        Parse all findings from a reviews directory.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ReviewsPath
    )

    $findings = @()

    if (-not (Test-Path $ReviewsPath)) {
        Write-Warning "Reviews path not found: $ReviewsPath"
        return $findings
    }

    $findingsFiles = Get-ChildItem -Path $ReviewsPath -Filter "*-findings.md" -ErrorAction SilentlyContinue

    foreach ($file in $findingsFiles) {
        # Extract agent name from filename (e.g., sentinel-findings.md -> SENTINEL)
        $agentName = ($file.BaseName -replace '-findings$', '').ToUpper()

        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $parsedFindings = Parse-FindingsMarkdown -Content $content -AgentName $agentName
            $findings += $parsedFindings
        }
    }

    return $findings
}

function Show-MappingSummary {
    <#
    .SYNOPSIS
        Display a summary of the compliance mapping.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Mapping
    )

    # Determine verdict color
    $verdictColor = if ($Mapping.CriticalGaps.Count -gt 0) { "Red" }
                    elseif ($Mapping.CoveragePercent -lt 50) { "Yellow" }
                    elseif ($Mapping.CoveragePercent -lt 80) { "Cyan" }
                    else { "Green" }

    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor $verdictColor
    Write-Host "       COMPLIANCE MAPPING SUMMARY" -ForegroundColor $verdictColor
    Write-Host "  ============================================" -ForegroundColor $verdictColor
    Write-Host ""

    Write-Host "  Standard:    " -NoNewline -ForegroundColor Gray
    Write-Host $Mapping.StandardName -ForegroundColor White

    Write-Host "  Coverage:    " -NoNewline -ForegroundColor Gray
    Write-Host "$($Mapping.CoveragePercent)%" -ForegroundColor $verdictColor

    Write-Host ""
    Write-Host "  Controls:    " -NoNewline -ForegroundColor Gray
    Write-Host "$($Mapping.AddressedControls) / $($Mapping.TotalControls) addressed" -ForegroundColor White

    Write-Host "  Gaps:        " -NoNewline -ForegroundColor Gray
    Write-Host $Mapping.GappedControls -ForegroundColor $(if ($Mapping.GappedControls -gt 0) { "Yellow" } else { "Green" })

    if ($Mapping.CriticalGaps.Count -gt 0) {
        Write-Host "  Critical:    " -NoNewline -ForegroundColor Gray
        Write-Host "$($Mapping.CriticalGaps.Count) critical gaps" -ForegroundColor Red
    }

    Write-Host ""

    # Top gaps to address
    if ($Mapping.CriticalGaps.Count -gt 0) {
        Write-Host "  Priority Gaps:" -ForegroundColor Yellow
        $topGaps = $Mapping.CriticalGaps | Select-Object -First 5
        foreach ($gap in $topGaps) {
            Write-Host "    - $($gap.Id): $($gap.Title)" -ForegroundColor Gray
        }
        if ($Mapping.CriticalGaps.Count -gt 5) {
            Write-Host "    ... and $($Mapping.CriticalGaps.Count - 5) more" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

function Invoke-FindingsMapping {
    <#
    .SYNOPSIS
        Main function to map findings to a compliance standard.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ReviewsPath,

        [Parameter(Mandatory)]
        [string]$StandardId,

        [string]$OutputPath
    )

    Write-Host ""
    Write-Host "  Mapping Findings to Compliance Standard" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Resolve reviews path
    $ReviewsPath = Resolve-Path $ReviewsPath -ErrorAction SilentlyContinue
    if (-not $ReviewsPath) {
        Write-Host "  ERROR: Reviews path not found" -ForegroundColor Red
        return $null
    }

    Write-Host "  Reviews:  $ReviewsPath" -ForegroundColor Gray
    Write-Host "  Standard: $StandardId" -ForegroundColor Gray
    Write-Host ""

    # Load standard
    $standard = Get-StandardById -StandardId $StandardId -StandardsDir $Script:StandardsDir
    if (-not $standard) {
        Write-Host "  ERROR: Standard not found: $StandardId" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Available standards:" -ForegroundColor Gray
        $available = Get-AvailableStandards -StandardsDir $Script:StandardsDir
        foreach ($a in $available) {
            Write-Host "    - $($a.Id)" -ForegroundColor Gray
        }
        Write-Host ""
        return $null
    }

    Write-Host "  Loaded: $($standard.name)" -ForegroundColor Green

    # Parse findings
    Write-Host "  Parsing findings..." -ForegroundColor Gray
    $findings = Get-AllFindings -ReviewsPath $ReviewsPath

    if ($findings.Count -eq 0) {
        Write-Host "  WARNING: No findings found in $ReviewsPath" -ForegroundColor Yellow
        Write-Host "  Make sure you have run a review first." -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-Host "  Found $($findings.Count) findings" -ForegroundColor Green
    }

    # Perform mapping
    Write-Host "  Mapping to controls..." -ForegroundColor Gray
    $mapping = Get-ComplianceMapping -Findings $findings -Standard $standard

    # Determine output path
    if (-not $OutputPath) {
        $OutputPath = Join-Path $ReviewsPath "COMPLIANCE-MAPPING-$($StandardId.ToUpper()).md"
    }

    # Get project name from path
    $projectPath = Split-Path (Split-Path $ReviewsPath -Parent) -Parent
    $projectName = Split-Path $projectPath -Leaf

    # Generate report
    Write-Host "  Generating report..." -ForegroundColor Gray
    Export-ComplianceReport -Mapping $mapping -OutputPath $OutputPath -ProjectName $projectName

    # Display summary
    Show-MappingSummary -Mapping $mapping

    Write-Host "  Report saved: $OutputPath" -ForegroundColor Green
    Write-Host ""

    return $mapping
}

# Main execution
Invoke-FindingsMapping -ReviewsPath $ReviewsPath -StandardId $StandardId -OutputPath $OutputPath
