<#
.SYNOPSIS
    Generate Code Conclave reports from review findings.

.DESCRIPTION
    Generates reports in various formats using templates. Supports
    executive summary, full report, gap analysis, and traceability matrix.

.PARAMETER ProjectPath
    Path to the project or .code-conclave directory.

.PARAMETER Template
    Report template to use: executive-summary, full-report, gap-analysis, traceability-matrix, release-readiness

.PARAMETER Format
    Output format: markdown (default), json, csv

.PARAMETER Standard
    Compliance standard for gap-analysis and traceability templates.

.PARAMETER OutputPath
    Custom output path for the report.

.EXAMPLE
    .\report.ps1 -ProjectPath "C:\project" -Template executive-summary
    .\report.ps1 -ProjectPath "C:\project" -Template gap-analysis -Standard cmmc-l2
#>

param(
    [Parameter(Mandatory)]
    [string]$ProjectPath,

    [ValidateSet("executive-summary", "full-report", "gap-analysis", "traceability-matrix", "release-readiness")]
    [string]$Template = "release-readiness",

    [ValidateSet("markdown", "json", "csv")]
    [string]$Format = "markdown",

    [string]$Standard,

    [string]$OutputPath
)

# Path setup
$Script:ToolRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script:TemplatesDir = Join-Path $ToolRoot "core" "templates"
$Script:StandardsDir = Join-Path $ToolRoot "core" "standards"

# Source dependencies
$libPath = Join-Path $PSScriptRoot "..\lib"
if (Test-Path (Join-Path $libPath "yaml-parser.ps1")) {
    . (Join-Path $libPath "yaml-parser.ps1")
}
if (Test-Path (Join-Path $libPath "mapping-engine.ps1")) {
    . (Join-Path $libPath "mapping-engine.ps1")
}

# Agent definitions
$AgentDefs = [ordered]@{
    sentinel  = @{ Name = "SENTINEL";  Role = "Quality and Compliance"; Color = "Yellow" }
    guardian  = @{ Name = "GUARDIAN";  Role = "Security"; Color = "Red" }
    architect = @{ Name = "ARCHITECT"; Role = "Code Health"; Color = "Blue" }
    navigator = @{ Name = "NAVIGATOR"; Role = "UX Review"; Color = "Cyan" }
    herald    = @{ Name = "HERALD";    Role = "Documentation"; Color = "Magenta" }
    operator  = @{ Name = "OPERATOR";  Role = "Production Readiness"; Color = "Green" }
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

function Get-FindingsFromFile {
    param([string]$FilePath, [string]$AgentName)

    if (-not (Test-Path $FilePath)) {
        return @()
    }

    $content = Get-Content $FilePath -Raw
    $findings = @()

    # Pattern: ### AGENT-001: Title [SEVERITY]
    $pattern = '###\s+([A-Z]+\-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]'
    $matches = [regex]::Matches($content, $pattern)

    foreach ($match in $matches) {
        $findings += @{
            Id = $match.Groups[1].Value
            Title = $match.Groups[2].Value.Trim()
            Severity = $match.Groups[3].Value
            Agent = $AgentName
        }
    }

    return $findings
}

function Get-AllFindings {
    param([string]$ReviewsDir)

    $allFindings = @()

    foreach ($agentKey in $AgentDefs.Keys) {
        $findingsFile = Join-Path $ReviewsDir "$agentKey-findings.md"
        $findings = Get-FindingsFromFile -FilePath $findingsFile -AgentName $AgentDefs[$agentKey].Name
        $allFindings += $findings
    }

    return $allFindings
}

function New-ReleaseReadinessReport {
    param(
        [string]$ReviewsDir,
        [string]$ProjectName,
        [hashtable]$AllCounts
    )

    $date = Get-Date -Format "yyyy-MM-dd HH:mm"

    # Calculate totals
    $totalBlockers = 0
    $totalHigh = 0
    $totalMedium = 0
    $totalLow = 0

    foreach ($f in $AllCounts.Values) {
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

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("# Release Readiness Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Project:** $ProjectName")
    [void]$sb.AppendLine("**Generated:** $date")
    [void]$sb.AppendLine("**Verdict:** $verdict")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Severity | Count |")
    [void]$sb.AppendLine("|----------|-------|")
    [void]$sb.AppendLine("| BLOCKER | $totalBlockers |")
    [void]$sb.AppendLine("| HIGH | $totalHigh |")
    [void]$sb.AppendLine("| MEDIUM | $totalMedium |")
    [void]$sb.AppendLine("| LOW | $totalLow |")
    [void]$sb.AppendLine("| **Total** | **$totalAll** |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Agent Reports")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Agent | Role | Blockers | High | Medium | Low | Status |")
    [void]$sb.AppendLine("|-------|------|----------|------|--------|-----|--------|")

    foreach ($agentKey in $AgentDefs.Keys) {
        $agent = $AgentDefs[$agentKey]
        $f = $AllCounts[$agentKey]

        $status = if ($f.Missing) { "MISSING" }
                  elseif ($f.Blockers -gt 0) { "FAIL" }
                  elseif ($f.High -gt 0) { "WARN" }
                  else { "PASS" }

        [void]$sb.AppendLine("| $($agent.Name) | $($agent.Role) | $($f.Blockers) | $($f.High) | $($f.Medium) | $($f.Low) | $status |")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Detailed Findings")
    [void]$sb.AppendLine("")

    foreach ($agentKey in $AgentDefs.Keys) {
        $findingsFile = Join-Path $ReviewsDir "$agentKey-findings.md"
        if (Test-Path $findingsFile) {
            $agent = $AgentDefs[$agentKey]
            [void]$sb.AppendLine("### $($agent.Name)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("See: [$agentKey-findings.md](./$agentKey-findings.md)")
            [void]$sb.AppendLine("")
        }
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Code Conclave v2.0*")

    return @{
        Content = $sb.ToString()
        Verdict = $verdict
        Totals = @{
            Blockers = $totalBlockers
            High = $totalHigh
            Medium = $totalMedium
            Low = $totalLow
            Total = $totalAll
        }
    }
}

function New-ExecutiveSummaryReport {
    param(
        [string]$ReviewsDir,
        [string]$ProjectName,
        [hashtable]$AllCounts,
        [array]$AllFindings
    )

    $date = Get-Date -Format "yyyy-MM-dd HH:mm"

    # Calculate totals
    $blockers = $AllFindings | Where-Object { $_.Severity -eq "BLOCKER" }
    $highs = $AllFindings | Where-Object { $_.Severity -eq "HIGH" }

    $totalBlockers = $blockers.Count
    $totalHigh = $highs.Count
    $totalMedium = ($AllFindings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
    $totalLow = ($AllFindings | Where-Object { $_.Severity -eq "LOW" }).Count
    $totalAll = $AllFindings.Count

    # Determine verdict
    $verdict = if ($totalBlockers -gt 0) { "HOLD" }
               elseif ($totalHigh -gt 3) { "CONDITIONAL" }
               else { "SHIP" }

    $verdictBadge = switch ($verdict) {
        "HOLD" { "**HOLD** - Critical issues must be resolved" }
        "CONDITIONAL" { "**CONDITIONAL** - Issues should be addressed" }
        "SHIP" { "**SHIP** - Ready for release" }
    }

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("# Executive Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Project:** $ProjectName")
    [void]$sb.AppendLine("**Generated:** $date")
    [void]$sb.AppendLine("**Review Type:** Full Code Review")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Release Verdict")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($verdictBadge)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Key Metrics")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Value |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Total Findings | $totalAll |")
    [void]$sb.AppendLine("| Blockers | $totalBlockers |")
    [void]$sb.AppendLine("| High Severity | $totalHigh |")
    [void]$sb.AppendLine("| Medium Severity | $totalMedium |")
    [void]$sb.AppendLine("| Low Severity | $totalLow |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Critical Issues")
    [void]$sb.AppendLine("")

    if ($blockers.Count -gt 0) {
        [void]$sb.AppendLine("The following issues must be resolved before release:")
        [void]$sb.AppendLine("")
        foreach ($b in $blockers) {
            [void]$sb.AppendLine("- **$($b.Id)**: $($b.Title)")
        }
    }
    else {
        [void]$sb.AppendLine("No blocking issues identified.")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## High Priority Items")
    [void]$sb.AppendLine("")

    if ($highs.Count -gt 0) {
        foreach ($h in ($highs | Select-Object -First 5)) {
            [void]$sb.AppendLine("- **$($h.Id)**: $($h.Title)")
        }
        if ($highs.Count -gt 5) {
            [void]$sb.AppendLine("- *... and $($highs.Count - 5) more*")
        }
    }
    else {
        [void]$sb.AppendLine("No high-priority issues identified.")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Agent Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Agent | Role | Findings | Status |")
    [void]$sb.AppendLine("|-------|------|----------|--------|")

    foreach ($agentKey in $AgentDefs.Keys) {
        $agent = $AgentDefs[$agentKey]
        $f = $AllCounts[$agentKey]

        $status = if ($f.Missing) { "MISSING" }
                  elseif ($f.Blockers -gt 0) { "FAIL" }
                  elseif ($f.High -gt 0) { "WARN" }
                  else { "PASS" }

        [void]$sb.AppendLine("| $($agent.Name) | $($agent.Role) | $($f.Total) | $status |")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Code Conclave v2.0*")

    return $sb.ToString()
}

function Export-ReportAsJson {
    param(
        [string]$ReviewsDir,
        [string]$ProjectName,
        [hashtable]$AllCounts,
        [array]$AllFindings
    )

    $report = @{
        project = $ProjectName
        generated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        summary = @{
            blockers = ($AllFindings | Where-Object { $_.Severity -eq "BLOCKER" }).Count
            high = ($AllFindings | Where-Object { $_.Severity -eq "HIGH" }).Count
            medium = ($AllFindings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
            low = ($AllFindings | Where-Object { $_.Severity -eq "LOW" }).Count
            total = $AllFindings.Count
        }
        verdict = if (($AllFindings | Where-Object { $_.Severity -eq "BLOCKER" }).Count -gt 0) { "HOLD" }
                  elseif (($AllFindings | Where-Object { $_.Severity -eq "HIGH" }).Count -gt 3) { "CONDITIONAL" }
                  else { "SHIP" }
        agents = @{}
        findings = $AllFindings
    }

    foreach ($agentKey in $AgentDefs.Keys) {
        $report.agents[$agentKey] = @{
            name = $AgentDefs[$agentKey].Name
            role = $AgentDefs[$agentKey].Role
            counts = $AllCounts[$agentKey]
        }
    }

    return $report | ConvertTo-Json -Depth 10
}

function Export-ReportAsCsv {
    param([array]$AllFindings)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("`"Finding ID`",`"Agent`",`"Title`",`"Severity`"")

    foreach ($f in $AllFindings) {
        # Sanitize all fields - escape quotes and remove newlines
        $id = ($f.Id -as [string]) -replace '"', '""'
        $agent = ($f.Agent -as [string]) -replace '"', '""'
        $title = ($f.Title -as [string]) -replace "(`r`n|`n|`r)", ' ' -replace '"', '""'
        $severity = ($f.Severity -as [string]) -replace '"', '""'
        [void]$sb.AppendLine("`"$id`",`"$agent`",`"$title`",`"$severity`"")
    }

    return $sb.ToString()
}

# Main execution
Write-Host ""
Write-Host "  Code Conclave Report Generator" -ForegroundColor Cyan
Write-Host "  ==============================" -ForegroundColor Cyan
Write-Host ""

# Resolve reviews directory
$reviewsDir = if (Test-Path (Join-Path $ProjectPath ".code-conclave\reviews")) {
    Join-Path $ProjectPath ".code-conclave\reviews"
}
elseif (Test-Path (Join-Path $ProjectPath "reviews")) {
    Join-Path $ProjectPath "reviews"
}
elseif (Test-Path $ProjectPath -and (Split-Path $ProjectPath -Leaf) -eq "reviews") {
    $ProjectPath
}
else {
    Write-Host "  ERROR: Reviews directory not found" -ForegroundColor Red
    exit 1
}

# Determine project root based on reviews directory structure
$reviewsParent = Split-Path $reviewsDir -Parent
if ((Split-Path $reviewsParent -Leaf) -eq ".code-conclave") {
    # Layout: project\.code-conclave\reviews
    $projectRoot = Split-Path $reviewsParent -Parent
}
else {
    # Layout: project\reviews or reviews passed directly
    $projectRoot = $reviewsParent
}
$projectName = Split-Path $projectRoot -Leaf

Write-Host "  Project: $projectName" -ForegroundColor White
Write-Host "  Template: $Template" -ForegroundColor White
Write-Host "  Format: $Format" -ForegroundColor White
Write-Host ""

# Collect findings
$allCounts = @{}
foreach ($agentKey in $AgentDefs.Keys) {
    $findingsFile = Join-Path $reviewsDir "$agentKey-findings.md"
    $allCounts[$agentKey] = Get-FindingsCounts $findingsFile
}

$allFindings = Get-AllFindings -ReviewsDir $reviewsDir

Write-Host "  Found $($allFindings.Count) findings" -ForegroundColor Gray
Write-Host ""

# Generate report based on template and format
$reportContent = ""
$extension = switch ($Format) {
    "json" { ".json" }
    "csv" { ".csv" }
    default { ".md" }
}

switch ($Template) {
    "release-readiness" {
        if ($Format -eq "json") {
            $reportContent = Export-ReportAsJson -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        elseif ($Format -eq "csv") {
            $reportContent = Export-ReportAsCsv -AllFindings $allFindings
        }
        else {
            $result = New-ReleaseReadinessReport -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts
            $reportContent = $result.Content
        }
        $defaultName = "RELEASE-READINESS-REPORT"
    }

    "executive-summary" {
        if ($Format -eq "json") {
            $reportContent = Export-ReportAsJson -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        elseif ($Format -eq "csv") {
            $reportContent = Export-ReportAsCsv -AllFindings $allFindings
        }
        else {
            $reportContent = New-ExecutiveSummaryReport -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        $defaultName = "EXECUTIVE-SUMMARY"
    }

    "full-report" {
        if ($Format -eq "json") {
            $reportContent = Export-ReportAsJson -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        elseif ($Format -eq "csv") {
            $reportContent = Export-ReportAsCsv -AllFindings $allFindings
        }
        else {
            # For full-report, use the template file with placeholders
            $templatePath = Join-Path $Script:TemplatesDir "full-report.md"
            if (Test-Path $templatePath) {
                $reportContent = Get-Content $templatePath -Raw

                # Calculate counts
                $blockerCount = ($allFindings | Where-Object { $_.Severity -eq "BLOCKER" }).Count
                $highCount = ($allFindings | Where-Object { $_.Severity -eq "HIGH" }).Count
                $mediumCount = ($allFindings | Where-Object { $_.Severity -eq "MEDIUM" }).Count
                $lowCount = ($allFindings | Where-Object { $_.Severity -eq "LOW" }).Count

                # Determine verdict
                $verdict = if ($blockerCount -gt 0) { "HOLD" }
                           elseif ($highCount -gt 3) { "CONDITIONAL" }
                           else { "SHIP" }

                # Build agent reports section
                $agentReportsSb = New-Object System.Text.StringBuilder
                foreach ($agentKey in $AgentDefs.Keys) {
                    $agent = $AgentDefs[$agentKey]
                    $agentFindings = $allFindings | Where-Object { $_.Agent -eq $agent.Name }
                    if ($agentFindings.Count -gt 0) {
                        [void]$agentReportsSb.AppendLine("### $($agent.Name) - $($agent.Role)")
                        [void]$agentReportsSb.AppendLine("")
                        foreach ($af in $agentFindings) {
                            [void]$agentReportsSb.AppendLine("- **$($af.Id)** [$($af.Severity)]: $($af.Title)")
                        }
                        [void]$agentReportsSb.AppendLine("")
                    }
                }

                # Replace placeholders with actual values
                $reportContent = $reportContent -replace '{{PROJECT_NAME}}', $projectName
                $reportContent = $reportContent -replace '{{TIMESTAMP}}', (Get-Date -Format "yyyy-MM-dd HH:mm")
                $reportContent = $reportContent -replace '{{TOTAL_FINDINGS}}', $allFindings.Count
                $reportContent = $reportContent -replace '{{VERDICT}}', $verdict
                $reportContent = $reportContent -replace '{{BLOCKER_COUNT}}', $blockerCount
                $reportContent = $reportContent -replace '{{HIGH_COUNT}}', $highCount
                $reportContent = $reportContent -replace '{{MEDIUM_COUNT}}', $mediumCount
                $reportContent = $reportContent -replace '{{LOW_COUNT}}', $lowCount
                $reportContent = $reportContent -replace '{{INFO_COUNT}}', '0'
                $reportContent = $reportContent -replace '{{AGENT_REPORTS}}', $agentReportsSb.ToString()

                # Compliance mapping placeholder (requires -Standard)
                if ($Standard) {
                    $reportContent = $reportContent -replace '{{COMPLIANCE_MAPPING}}', "See separate gap-analysis report for $Standard compliance mapping."
                }
                else {
                    $reportContent = $reportContent -replace '{{COMPLIANCE_MAPPING}}', "*Run with -Standard parameter to include compliance mapping.*"
                }
            }
            else {
                $reportContent = "Template not found: $templatePath"
            }
        }
        $defaultName = "FULL-REPORT"
    }

    "gap-analysis" {
        if (-not $Standard) {
            Write-Host "  ERROR: -Standard required for gap-analysis template" -ForegroundColor Red
            exit 1
        }
        if ($Format -eq "json") {
            $reportContent = Export-ReportAsJson -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        elseif ($Format -eq "csv") {
            $reportContent = Export-ReportAsCsv -AllFindings $allFindings
        }
        else {
            # Use mapping engine for gap analysis
            $std = Get-StandardById -StandardId $Standard -StandardsDir $Script:StandardsDir
            if (-not $std) {
                Write-Host "  ERROR: Standard not found: $Standard" -ForegroundColor Red
                exit 1
            }
            $mapping = Get-ComplianceMapping -Findings $allFindings -Standard $std
            $tempOutput = Join-Path $reviewsDir "COMPLIANCE-MAPPING-$($Standard.ToUpper()).md"
            Export-ComplianceReport -Mapping $mapping -OutputPath $tempOutput -ProjectName $projectName
            $reportContent = Get-Content $tempOutput -Raw
            # Clean up temporary file
            Remove-Item -Path $tempOutput -ErrorAction SilentlyContinue
        }
        $defaultName = "GAP-ANALYSIS-$($Standard.ToUpper())"
    }

    "traceability-matrix" {
        if (-not $Standard) {
            Write-Host "  ERROR: -Standard required for traceability-matrix template" -ForegroundColor Red
            exit 1
        }
        if ($Format -eq "json") {
            $reportContent = Export-ReportAsJson -ReviewsDir $reviewsDir -ProjectName $projectName -AllCounts $allCounts -AllFindings $allFindings
        }
        elseif ($Format -eq "csv") {
            $reportContent = Export-ReportAsCsv -AllFindings $allFindings
        }
        else {
            # Generate traceability matrix
            $std = Get-StandardById -StandardId $Standard -StandardsDir $Script:StandardsDir
            if (-not $std) {
                Write-Host "  ERROR: Standard not found: $Standard" -ForegroundColor Red
                exit 1
            }
            $mapping = Get-ComplianceMapping -Findings $allFindings -Standard $std

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine("# Traceability Matrix")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("**Project:** $projectName")
            [void]$sb.AppendLine("**Standard:** $($std.name)")
            [void]$sb.AppendLine("**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Overview")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| Metric | Value |")
            [void]$sb.AppendLine("|--------|-------|")
            [void]$sb.AppendLine("| Total Controls | $($mapping.Coverage.TotalControls) |")
            [void]$sb.AppendLine("| Controls with Findings | $($mapping.Coverage.Addressed) |")
            [void]$sb.AppendLine("| Total Findings | $($allFindings.Count) |")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Reverse Mapping: Finding → Controls")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| Finding ID | Agent | Title | Severity | Mapped Controls |")
            [void]$sb.AppendLine("|------------|-------|-------|----------|-----------------|")

            foreach ($m in $mapping.MappedFindings) {
                $controlIds = ($m.Controls | ForEach-Object { $_.Id }) -join ", "
                $title = ConvertTo-MarkdownSafe -Text $m.Finding.Title
                [void]$sb.AppendLine("| $($m.Finding.Id) | $($m.Finding.Agent) | $title | $($m.Finding.Severity) | $controlIds |")
            }

            # Add unmapped findings
            $mappedIds = $mapping.MappedFindings | ForEach-Object { $_.Finding.Id }
            $unmapped = $allFindings | Where-Object { $_.Id -notin $mappedIds }
            if ($unmapped.Count -gt 0) {
                foreach ($uf in $unmapped) {
                    $title = ConvertTo-MarkdownSafe -Text $uf.Title
                    [void]$sb.AppendLine("| $($uf.Id) | $($uf.Agent) | $title | $($uf.Severity) | *Not mapped* |")
                }
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("## Gaps: Controls Without Findings")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| Control ID | Title | Domain | Recommended Agent |")
            [void]$sb.AppendLine("|------------|-------|--------|-------------------|")

            foreach ($gap in $mapping.Gaps | Select-Object -First 50) {
                $agents = if ($gap.Agents) { ($gap.Agents -join ", ").ToUpper() } else { "-" }
                $title = ConvertTo-MarkdownSafe -Text $gap.Title
                $domain = ConvertTo-MarkdownSafe -Text $gap.DomainName
                [void]$sb.AppendLine("| $($gap.Id) | $title | $domain | $agents |")
            }

            if ($mapping.Gaps.Count -gt 50) {
                [void]$sb.AppendLine("| ... | *$($mapping.Gaps.Count - 50) more gaps* | | |")
            }

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("*Generated by Code Conclave v2.0*")

            $reportContent = $sb.ToString()
        }
        $defaultName = "TRACEABILITY-$($Standard.ToUpper())"
    }
}

# Determine output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $reviewsDir "$defaultName$extension"
}

# Save report
$reportContent | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host "  Report generated: $OutputPath" -ForegroundColor Green
Write-Host ""
