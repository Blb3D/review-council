# Regenerate Synthesis Report
# This script rescans existing findings files and generates a correct release readiness report

param(
    [Parameter(Mandatory)]
    [string]$ProjectPath
)

$reviewsDir = Join-Path $ProjectPath ".code-conclave\reviews"

if (-not (Test-Path $reviewsDir)) {
    Write-Error "Reviews directory not found: $reviewsDir"
    exit 1
}

# Agent definitions
$AgentDefs = [ordered]@{
    sentinel  = @{ Name = "SENTINEL";  Role = "Quality and Compliance" }
    guardian  = @{ Name = "GUARDIAN";  Role = "Security" }
    architect = @{ Name = "ARCHITECT"; Role = "Code Health" }
    navigator = @{ Name = "NAVIGATOR"; Role = "UX Review" }
    herald    = @{ Name = "HERALD";    Role = "Documentation" }
    operator  = @{ Name = "OPERATOR";  Role = "Production Readiness" }
}

function Get-FindingsCounts {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0; Missing = $true }
    }

    $content = Get-Content $FilePath -Raw

    $counts = @{
        Blockers = ([regex]::Matches($content, '\[BLOCKER\]')).Count
        High     = ([regex]::Matches($content, '\[HIGH\]')).Count
        Medium   = ([regex]::Matches($content, '\[MEDIUM\]')).Count
        Low      = ([regex]::Matches($content, '\[LOW\]')).Count
    }
    $counts.Total = $counts.Blockers + $counts.High + $counts.Medium + $counts.Low

    return $counts
}

Write-Host "Scanning findings files in: $reviewsDir" -ForegroundColor Cyan
Write-Host ""

# Collect all findings
$allFindings = @{}

foreach ($agentKey in $AgentDefs.Keys) {
    $findingsFile = Join-Path $reviewsDir "$agentKey-findings.md"
    $counts = Get-FindingsCounts $findingsFile
    $allFindings[$agentKey] = $counts

    $status = if ($counts.Missing) { "MISSING" }
              elseif ($counts.Blockers -gt 0) { "FAIL" }
              elseif ($counts.High -gt 0) { "WARN" }
              else { "PASS" }

    Write-Host "  $($AgentDefs[$agentKey].Name): $($counts.Blockers)B $($counts.High)H $($counts.Medium)M $($counts.Low)L [$status]" -ForegroundColor $(
        switch ($status) {
            "FAIL" { "Red" }
            "WARN" { "Yellow" }
            "MISSING" { "Gray" }
            default { "Green" }
        }
    )
}

# Calculate totals
$totalBlockers = 0
$totalHigh = 0
$totalMedium = 0
$totalLow = 0

foreach ($f in $allFindings.Values) {
    $totalBlockers += $f.Blockers
    $totalHigh += $f.High
    $totalMedium += $f.Medium
    $totalLow += $f.Low
}

$totalAll = $totalBlockers + $totalHigh + $totalMedium + $totalLow

# Determine verdict
$verdict = if ($totalBlockers -gt 0) { "HOLD" }
           elseif ($totalHigh -gt 3) { "CONDITIONAL" }
           else { "SHIP" }

Write-Host ""
Write-Host "Totals: $totalBlockers BLOCKER, $totalHigh HIGH, $totalMedium MEDIUM, $totalLow LOW = $totalAll findings" -ForegroundColor White
Write-Host ""

$verdictColor = switch ($verdict) {
    "HOLD" { "Red" }
    "CONDITIONAL" { "Yellow" }
    "SHIP" { "Green" }
}
Write-Host "VERDICT: $verdict" -ForegroundColor $verdictColor

# Generate report
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$projectName = Split-Path $ProjectPath -Leaf

$report = @"
# Release Readiness Report

**Project:** $projectName
**Generated:** $date
**Verdict:** $verdict

---

## Summary

| Severity | Count |
|----------|-------|
| BLOCKER | $totalBlockers |
| HIGH | $totalHigh |
| MEDIUM | $totalMedium |
| LOW | $totalLow |
| **Total** | **$totalAll** |

---

## Agent Reports

| Agent | Role | Blockers | High | Medium | Low | Status |
|-------|------|----------|------|--------|-----|--------|
"@

foreach ($agentKey in $AgentDefs.Keys) {
    $agent = $AgentDefs[$agentKey]
    $f = $allFindings[$agentKey]

    $status = if ($f.Missing) { "MISSING" }
              elseif ($f.Blockers -gt 0) { "FAIL" }
              elseif ($f.High -gt 0) { "WARN" }
              else { "PASS" }

    $report += "| $($agent.Name) | $($agent.Role) | $($f.Blockers) | $($f.High) | $($f.Medium) | $($f.Low) | $status |`n"
}

$report += @"

---

## Findings Summary

### Blockers ($totalBlockers)

"@

# Extract blocker summaries
foreach ($agentKey in $AgentDefs.Keys) {
    $findingsFile = Join-Path $reviewsDir "$agentKey-findings.md"
    if (Test-Path $findingsFile) {
        $content = Get-Content $findingsFile -Raw
        $blockerMatches = [regex]::Matches($content, '### ([A-Z]+-\d+).*?\[BLOCKER\].*?(?=\n### [A-Z]+-\d+|\n## |$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($match in $blockerMatches) {
            $lines = $match.Value -split "`n"
            $id = $lines[0] -replace '### ', '' -replace ' .*', ''
            $title = $lines[0] -replace '### [A-Z]+-\d+ ', '' -replace ' \[BLOCKER\].*', ''
            $report += "- **$id**: $title`n"
        }
    }
}

$report += @"

### High Priority ($totalHigh)

See individual agent reports for details.

---

## Detailed Findings

"@

foreach ($agentKey in $AgentDefs.Keys) {
    $findingsFile = Join-Path $reviewsDir "$agentKey-findings.md"
    if (Test-Path $findingsFile) {
        $agent = $AgentDefs[$agentKey]
        $report += "### $($agent.Name)`n`nSee: [$agentKey-findings.md](./$agentKey-findings.md)`n`n"
    }
}

$report += @"
---

*Generated by Code Conclave - Report Regeneration*
"@

# Save report
$reportPath = Join-Path $reviewsDir "RELEASE-READINESS-REPORT.md"
$report | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "Report saved: $reportPath" -ForegroundColor Green
