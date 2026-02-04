<#
.SYNOPSIS
    Code Conclave - AI-Powered Code Review Orchestrator

.DESCRIPTION
    Deploys 6 specialized AI agents to review any codebase from different
    perspectives: Quality, Security, Architecture, UX, Documentation,
    and Production Readiness.

.PARAMETER Project
    Path to the project to review. Required unless using -Init.

.PARAMETER Init
    Initialize Code Conclave in a project (creates .code-conclave folder)

.PARAMETER Agent
    Run a single specific agent

.PARAMETER Agents
    Run multiple specific agents (comma-separated)

.PARAMETER StartFrom
    Resume from a specific agent (skip earlier ones)

.PARAMETER SkipSynthesis
    Skip generating the final synthesis report

.PARAMETER DryRun
    Show what would execute without running agents

.PARAMETER Timeout
    Timeout per agent in minutes (default: 40)

.EXAMPLE
    .\ccl.ps1 -Init -Project "C:\repos\my-app"

.EXAMPLE
    .\ccl.ps1 -Project "C:\repos\my-app"

.EXAMPLE
    .\ccl.ps1 -Project "C:\repos\my-app" -Agent sentinel

.EXAMPLE
    .\ccl.ps1 -Standards list

.EXAMPLE
    .\ccl.ps1 -Standards info -Standard cmmc-l2

.EXAMPLE
    .\ccl.ps1 -Project "C:\repos\my-app" -Standard cmmc-l2

.EXAMPLE
    .\ccl.ps1 -Map "C:\repos\my-app\.code-conclave\reviews" -Standard cmmc-l2
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Project,

    [switch]$Init,

    [string]$Agent,

    [string[]]$Agents,

    [string]$StartFrom,

    [switch]$SkipSynthesis,

    [switch]$DryRun,

    [int]$Timeout = 40,

    # Output Format
    [ValidateSet("markdown", "json", "junit")]
    [string]$OutputFormat = "markdown",

    # Compliance Standard Parameters
    [string]$Standard,

    [ValidateSet("list", "info")]
    [string]$Standards,

    [string]$Map,

    # CI/CD Mode - enables exit codes for pipeline integration
    [switch]$CI
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:ToolRoot = Split-Path $PSScriptRoot -Parent
$Script:AgentsDir = Join-Path $ToolRoot "core" "agents"
$Script:StandardsDir = Join-Path $ToolRoot "core" "standards"
$Script:LibDir = Join-Path $PSScriptRoot "lib"

# Source library files if they exist
$yamlParserPath = Join-Path $Script:LibDir "yaml-parser.ps1"
$mappingEnginePath = Join-Path $Script:LibDir "mapping-engine.ps1"

if (Test-Path $yamlParserPath) {
    . $yamlParserPath
}
if (Test-Path $mappingEnginePath) {
    . $mappingEnginePath
}

$junitFormatterPath = Join-Path $Script:LibDir "junit-formatter.ps1"
if (Test-Path $junitFormatterPath) {
    . $junitFormatterPath
}

$Script:AgentDefs = [ordered]@{
    sentinel  = @{ Name = "SENTINEL";  Role = "Quality and Compliance"; Color = "Yellow" }
    guardian  = @{ Name = "GUARDIAN";  Role = "Security";               Color = "Red" }
    architect = @{ Name = "ARCHITECT"; Role = "Code Health";            Color = "Blue" }
    navigator = @{ Name = "NAVIGATOR"; Role = "UX Review";              Color = "Cyan" }
    herald    = @{ Name = "HERALD";    Role = "Documentation";          Color = "Magenta" }
    operator  = @{ Name = "OPERATOR";  Role = "Production Readiness";   Color = "Green" }
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $width = 60
    $line = "=" * $width
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    $pad = [math]::Floor(($width - $Text.Length) / 2)
    Write-Host (" " * $pad + $Text) -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-AgentHeader {
    param([string]$AgentKey)
    $agent = $Script:AgentDefs[$AgentKey]
    Write-Host ""
    Write-Host "  [$($agent.Name)] - $($agent.Role)" -ForegroundColor $agent.Color
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Status) {
        "OK"      { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "RUNNING" { "Cyan" }
        default   { "Gray" }
    }
    Write-Host "  [$timestamp] $Message" -ForegroundColor $color
}

function Write-Logo {
    Write-Host ""
    Write-Host "  =====================================================" -ForegroundColor Cyan
    Write-Host "       CODE CONCLAVE - Code Review Orchestrator" -ForegroundColor Cyan
    Write-Host "  =====================================================" -ForegroundColor Cyan
    Write-Host "                        v2.0" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================================
# PROJECT INITIALIZATION
# ============================================================================

function Initialize-Project {
    param([string]$ProjectPath)

    Write-Banner "INITIALIZING PROJECT" "Yellow"

    if (-not (Test-Path $ProjectPath)) {
        Write-Status "Project path does not exist: $ProjectPath" "ERROR"
        return $false
    }

    $ccDir = Join-Path $ProjectPath ".code-conclave"
    $agentsDir = Join-Path $ccDir "agents"
    $reviewsDir = Join-Path $ccDir "reviews"

    # Create directories
    @($ccDir, $agentsDir, $reviewsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Status "Created: $_" "OK"
        }
    }

    # Create default config
    $configPath = Join-Path $ccDir "config.yaml"
    if (-not (Test-Path $configPath)) {
        $projectName = Split-Path $ProjectPath -Leaf
        $configContent = @"
# Code Conclave Configuration
# Generated: $(Get-Date -Format "yyyy-MM-dd")

project:
  name: "$projectName"
  version: "1.0.0"

agents:
  sentinel:
    coverage_target: 80

  guardian:
    scan_dependencies: true

  herald:
    required_docs:
      - "README.md"

output:
  format: "markdown"
"@
        $configContent | Out-File -FilePath $configPath -Encoding UTF8
        Write-Status "Created: $configPath" "OK"
    }

    # Copy contracts file
    $contractsPath = Join-Path $ccDir "CONTRACTS.md"
    $contractsSource = Join-Path $Script:ToolRoot "CONTRACTS.md"
    if ((Test-Path $contractsSource) -and -not (Test-Path $contractsPath)) {
        Copy-Item $contractsSource $contractsPath
        Write-Status "Created: $contractsPath" "OK"
    }

    Write-Host ""
    Write-Status "Add to your .gitignore: .code-conclave/reviews/" "WARN"
    Write-Host ""
    Write-Status "Project initialized! Run reviews with:" "OK"
    Write-Host "    .\ccl.ps1 -Project `"$ProjectPath`"" -ForegroundColor White
    Write-Host ""

    return $true
}

# ============================================================================
# FINDINGS ANALYSIS
# ============================================================================

function Get-FindingsCounts {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0 }
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

function Write-FindingsSummary {
    param([hashtable]$Counts)

    Write-Host "  Results: " -NoNewline

    if ($Counts.Total -eq 0) {
        Write-Host "No issues found" -ForegroundColor Green
        return
    }

    if ($Counts.Blockers -gt 0) {
        Write-Host "$($Counts.Blockers) BLOCKER " -NoNewline -ForegroundColor Red
    }
    if ($Counts.High -gt 0) {
        Write-Host "$($Counts.High) HIGH " -NoNewline -ForegroundColor Yellow
    }
    if ($Counts.Medium -gt 0) {
        Write-Host "$($Counts.Medium) MEDIUM " -NoNewline -ForegroundColor Cyan
    }
    if ($Counts.Low -gt 0) {
        Write-Host "$($Counts.Low) LOW" -NoNewline -ForegroundColor Gray
    }
    Write-Host ""
}

# ============================================================================
# AGENT EXECUTION
# ============================================================================

function Invoke-ReviewAgent {
    param(
        [string]$AgentKey,
        [string]$ProjectPath,
        [string]$ReviewsDir,
        [int]$TimeoutMinutes
    )

    $agent = $Script:AgentDefs[$AgentKey]
    $outputFile = Join-Path $ReviewsDir "$AgentKey-findings.md"

    # Look for agent skill file (project override or default)
    $projectAgentFile = Join-Path $ProjectPath ".code-conclave\agents\$AgentKey.md"
    $defaultAgentFile = Join-Path $Script:AgentsDir "$AgentKey.md"

    $agentSkillFile = if (Test-Path $projectAgentFile) { $projectAgentFile } else { $defaultAgentFile }

    # Look for contracts file
    $projectContracts = Join-Path $ProjectPath ".code-conclave\CONTRACTS.md"
    $defaultContracts = Join-Path $Script:ToolRoot "CONTRACTS.md"
    $contractsFile = if (Test-Path $projectContracts) { $projectContracts } else { $defaultContracts }

    Write-AgentHeader $AgentKey

    if (-not (Test-Path $agentSkillFile)) {
        Write-Status "Agent skill file not found: $agentSkillFile" "ERROR"
        return $null
    }

    # Build prompt
    $prompt = @"
You are executing a structured code review as the $($agent.Name) agent.

TARGET PROJECT: $ProjectPath

INSTRUCTIONS:
1. First, read the contracts file for shared rules and severity definitions:
   $contractsFile

2. Then read your agent-specific instructions:
   $agentSkillFile

3. Navigate to the target project and execute your review:
   cd "$ProjectPath"

4. Save findings in the EXACT format specified in CONTRACTS.md to:
   $outputFile

5. When complete, output a single summary line:
   COMPLETE: X BLOCKER, Y HIGH, Z MEDIUM, W LOW

Begin the $($agent.Name) review now.
"@

    if ($DryRun) {
        Write-Status "DRY RUN - Would execute $($agent.Name) agent" "WARN"
        Write-Host "    Target: $ProjectPath" -ForegroundColor DarkGray
        Write-Host "    Output: $outputFile" -ForegroundColor DarkGray
        return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0 }
    }

    Write-Status "Deploying $($agent.Name)..." "RUNNING"

    try {
        $startTime = Get-Date

        # Execute Claude Code with timeout
        $job = Start-Job -ScriptBlock {
            param($p)
            $p | claude --dangerously-skip-permissions 2>&1
        } -ArgumentList $prompt

        $completed = Wait-Job $job -Timeout ($TimeoutMinutes * 60)

        if (-not $completed) {
            Stop-Job $job
            Remove-Job $job
            Write-Status "Agent timed out after $TimeoutMinutes minutes" "WARN"

            # BUG FIX: Even on timeout, check if the output file was written
            # The agent may have completed but the job detection missed it
            if (Test-Path $outputFile) {
                Write-Status "Output file exists - parsing findings despite timeout" "INFO"
                $counts = Get-FindingsCounts $outputFile
                $counts.TimedOut = $true
                return $counts
            }

            return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0; TimedOut = $true }
        }

        $result = Receive-Job $job
        Remove-Job $job

        $duration = (Get-Date) - $startTime
        $mins = [math]::Round($duration.TotalMinutes, 1)
        Write-Status "Completed in $mins minutes" "OK"

        # Get findings counts
        $counts = Get-FindingsCounts $outputFile
        Write-FindingsSummary $counts

        return $counts
    }
    catch {
        Write-Status "Agent execution failed: $_" "ERROR"
        return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0; Error = $_.ToString() }
    }
}

# ============================================================================
# SYNTHESIS REPORT
# ============================================================================

function New-SynthesisReport {
    param(
        [string]$ProjectPath,
        [string]$ReviewsDir,
        [hashtable]$AllFindings
    )

    Write-Banner "GENERATING SYNTHESIS REPORT" "Yellow"

    $reportPath = Join-Path $ReviewsDir "RELEASE-READINESS-REPORT.md"
    $date = Get-Date -Format "yyyy-MM-dd HH:mm"
    $projectName = Split-Path $ProjectPath -Leaf

    # Calculate totals (BUG FIX: Default $null to 0)
    $totalBlockers = ($AllFindings.Values | Measure-Object -Property Blockers -Sum).Sum
    $totalHigh = ($AllFindings.Values | Measure-Object -Property High -Sum).Sum
    $totalMedium = ($AllFindings.Values | Measure-Object -Property Medium -Sum).Sum
    $totalLow = ($AllFindings.Values | Measure-Object -Property Low -Sum).Sum

    # PowerShell Measure-Object returns $null for sum of zeros, not 0
    if ($null -eq $totalBlockers) { $totalBlockers = 0 }
    if ($null -eq $totalHigh) { $totalHigh = 0 }
    if ($null -eq $totalMedium) { $totalMedium = 0 }
    if ($null -eq $totalLow) { $totalLow = 0 }

    # BUG FIX: If we have existing findings files but AllFindings is empty/wrong,
    # re-scan the files directly
    $actualTotal = $totalBlockers + $totalHigh + $totalMedium + $totalLow
    if ($actualTotal -eq 0) {
        Write-Status "Totals are zero - rescanning findings files directly..." "WARN"
        foreach ($agentKey in $Script:AgentDefs.Keys) {
            $findingsFile = Join-Path $ReviewsDir "$agentKey-findings.md"
            if (Test-Path $findingsFile) {
                $fileCounts = Get-FindingsCounts $findingsFile
                if (-not $AllFindings.ContainsKey($agentKey)) {
                    $AllFindings[$agentKey] = $fileCounts
                } elseif ($AllFindings[$agentKey].Total -eq 0 -and $fileCounts.Total -gt 0) {
                    # Override zero counts with actual file counts
                    $AllFindings[$agentKey] = $fileCounts
                }
            }
        }
        # Recalculate totals
        $totalBlockers = ($AllFindings.Values | Measure-Object -Property Blockers -Sum).Sum
        $totalHigh = ($AllFindings.Values | Measure-Object -Property High -Sum).Sum
        $totalMedium = ($AllFindings.Values | Measure-Object -Property Medium -Sum).Sum
        $totalLow = ($AllFindings.Values | Measure-Object -Property Low -Sum).Sum
        if ($null -eq $totalBlockers) { $totalBlockers = 0 }
        if ($null -eq $totalHigh) { $totalHigh = 0 }
        if ($null -eq $totalMedium) { $totalMedium = 0 }
        if ($null -eq $totalLow) { $totalLow = 0 }
    }

    # Determine verdict
    $verdict = if ($totalBlockers -gt 0) { "HOLD" }
               elseif ($totalHigh -gt 3) { "CONDITIONAL" }
               else { "SHIP" }

    # Build report
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Release Readiness Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Project:** $projectName")
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
    [void]$sb.AppendLine("| **Total** | $($totalBlockers + $totalHigh + $totalMedium + $totalLow) |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Agent Reports")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Agent | Role | Blockers | High | Medium | Low | Status |")
    [void]$sb.AppendLine("|-------|------|----------|------|--------|-----|--------|")

    foreach ($agentKey in $Script:AgentDefs.Keys) {
        $agent = $Script:AgentDefs[$agentKey]
        $f = $AllFindings[$agentKey]

        if ($f) {
            $status = if ($f.TimedOut) { "TIMEOUT" }
                      elseif ($f.Error) { "ERROR" }
                      elseif ($f.Blockers -gt 0) { "FAIL" }
                      elseif ($f.High -gt 0) { "WARN" }
                      else { "PASS" }

            [void]$sb.AppendLine("| $($agent.Name) | $($agent.Role) | $($f.Blockers) | $($f.High) | $($f.Medium) | $($f.Low) | $status |")
        } else {
            [void]$sb.AppendLine("| $($agent.Name) | $($agent.Role) | - | - | - | - | SKIPPED |")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Detailed Findings")
    [void]$sb.AppendLine("")

    foreach ($agentKey in $Script:AgentDefs.Keys) {
        $findingsFile = Join-Path $ReviewsDir "$agentKey-findings.md"
        if (Test-Path $findingsFile) {
            $agent = $Script:AgentDefs[$agentKey]
            [void]$sb.AppendLine("### $($agent.Name)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("See: [$agentKey-findings.md](./$agentKey-findings.md)")
            [void]$sb.AppendLine("")
        }
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Code Conclave*")

    $sb.ToString() | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Status "Report saved: $reportPath" "OK"

    # Display verdict
    $verdictColor = switch ($verdict) {
        "SHIP"        { "Green" }
        "CONDITIONAL" { "Yellow" }
        "HOLD"        { "Red" }
    }

    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor $verdictColor
    Write-Host "       RELEASE VERDICT: $verdict" -ForegroundColor $verdictColor
    Write-Host "  ============================================" -ForegroundColor $verdictColor
    Write-Host ""

    return $reportPath
}

# ============================================================================
# MAIN
# ============================================================================

function Main {
    Write-Logo

    # Handle -Standards command (no Claude required)
    if ($Standards) {
        $standardsScript = Join-Path $PSScriptRoot "commands" "standards.ps1"
        if (Test-Path $standardsScript) {
            switch ($Standards) {
                "list" {
                    & $standardsScript -Command "list"
                }
                "info" {
                    if (-not $Standard) {
                        Write-Status "Please specify -Standard for info command" "ERROR"
                        Write-Host "    Example: .\ccl.ps1 -Standards info -Standard cmmc-l2" -ForegroundColor Gray
                        return
                    }
                    & $standardsScript -Command "info" -StandardId $Standard
                }
            }
        }
        else {
            Write-Status "Standards command not found: $standardsScript" "ERROR"
        }
        return
    }

    # Handle -Map command (no Claude required)
    if ($Map) {
        if (-not $Standard) {
            Write-Status "Please specify -Standard for mapping" "ERROR"
            Write-Host "    Example: .\ccl.ps1 -Map `"./project/.code-conclave/reviews`" -Standard cmmc-l2" -ForegroundColor Gray
            return
        }
        $mapScript = Join-Path $PSScriptRoot "commands" "map.ps1"
        if (Test-Path $mapScript) {
            & $mapScript -ReviewsPath $Map -StandardId $Standard
        }
        else {
            Write-Status "Map command not found: $mapScript" "ERROR"
        }
        return
    }

    # Check for Claude Code (only needed for reviews)
    $claudeExists = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeExists -and -not $DryRun) {
        Write-Status "Claude Code CLI not found. Install from: https://docs.anthropic.com/claude-code" "ERROR"
        if ($CI -or $env:TF_BUILD) { exit 10 }
        return
    }

    # Handle -Init
    if ($Init) {
        if (-not $Project) {
            Write-Status "Please specify -Project path for initialization" "ERROR"
            Write-Host "    Example: .\ccl.ps1 -Init -Project `"C:\repos\my-app`"" -ForegroundColor Gray
            return
        }
        Initialize-Project -ProjectPath $Project
        return
    }

    # Require project for reviews
    if (-not $Project) {
        Write-Status "Please specify -Project path" "ERROR"
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor White
        Write-Host "    .\ccl.ps1 -Project `"C:\path\to\project`"" -ForegroundColor Gray
        Write-Host "    .\ccl.ps1 -Init -Project `"C:\path\to\project`"" -ForegroundColor Gray
        Write-Host ""
        return
    }

    # Validate project
    if (-not (Test-Path $Project)) {
        Write-Status "Project path does not exist: $Project" "ERROR"
        if ($CI -or $env:TF_BUILD) { exit 12 }
        return
    }

    $Project = Resolve-Path $Project

    # Check if initialized
    $ccDir = Join-Path $Project ".code-conclave"
    if (-not (Test-Path $ccDir)) {
        Write-Status "Project not initialized. Run with -Init first:" "WARN"
        Write-Host "    .\ccl.ps1 -Init -Project `"$Project`"" -ForegroundColor Gray
        Write-Host ""
        $response = Read-Host "  Initialize now? (Y/n)"
        if ($response -ne 'n') {
            Initialize-Project -ProjectPath $Project
        }
        return
    }

    $reviewsDir = Join-Path $ccDir "reviews"
    if (-not (Test-Path $reviewsDir)) {
        New-Item -ItemType Directory -Path $reviewsDir -Force | Out-Null
    }

    Write-Host "  Project: $Project" -ForegroundColor White

    # Display compliance standard if specified
    if ($Standard) {
        $standardInfo = Get-StandardById -StandardId $Standard -StandardsDir $Script:StandardsDir
        if ($standardInfo) {
            Write-Host "  Standard: $($standardInfo.name) ($Standard)" -ForegroundColor Magenta
        }
        else {
            Write-Status "Standard not found: $Standard" "WARN"
            Write-Host "  Run 'ccl -Standards list' to see available standards" -ForegroundColor Gray
            $Standard = $null  # Clear to skip compliance mapping later
        }
    }

    Write-Host ""

    # Determine agents to run
    $agentsToRun = @()

    if ($Agent) {
        $agentsToRun = @($Agent.ToLower())
    }
    elseif ($Agents -and $Agents.Count -gt 0) {
        $agentsToRun = $Agents | ForEach-Object { $_.ToLower() }
    }
    else {
        $agentsToRun = @($Script:AgentDefs.Keys)
    }

    # Handle -StartFrom
    if ($StartFrom) {
        $startKey = $StartFrom.ToLower()
        $found = $false
        $agentsToRun = $agentsToRun | Where-Object {
            if ($_ -eq $startKey) { $found = $true }
            $found
        }
    }

    # Validate agent names
    $validAgents = @()
    foreach ($a in $agentsToRun) {
        if ($Script:AgentDefs.Contains($a)) {
            $validAgents += $a
        }
        else {
            Write-Status "Unknown agent: $a (skipping)" "WARN"
        }
    }

    if ($validAgents.Count -eq 0) {
        Write-Status "No valid agents to run" "ERROR"
        if ($CI -or $env:TF_BUILD) { exit 11 }
        return
    }

    Write-Host "  Agents: $($validAgents -join ', ')" -ForegroundColor White
    Write-Host ""

    # Run agents
    $allFindings = @{}
    $startTime = Get-Date

    foreach ($agentKey in $validAgents) {
        $findings = Invoke-ReviewAgent -AgentKey $agentKey -ProjectPath $Project -ReviewsDir $reviewsDir -TimeoutMinutes $Timeout
        $allFindings[$agentKey] = $findings

        if ($findings -and $findings.Blockers -gt 0) {
            Write-Host ""
            Write-Host "  ** BLOCKER(S) FOUND **" -ForegroundColor Red
        }
    }

    $totalDuration = (Get-Date) - $startTime
    $totalMins = [math]::Round($totalDuration.TotalMinutes, 1)

    # Check if all agents failed
    $failedAgents = @($allFindings.Values | Where-Object { $_ -and $_.Error })
    $allFailed = $failedAgents.Count -eq $validAgents.Count
    if ($allFailed -and $validAgents.Count -gt 0 -and -not $DryRun) {
        Write-Status "All agents failed to execute" "ERROR"
        if ($CI -or $env:TF_BUILD) { exit 13 }
    }

    Write-Banner "REVIEW COMPLETE" "Green"
    Write-Host "  Duration: $totalMins minutes" -ForegroundColor Gray

    # Generate synthesis
    if (-not $SkipSynthesis -and $validAgents.Count -gt 1) {
        New-SynthesisReport -ProjectPath $Project -ReviewsDir $reviewsDir -AllFindings $allFindings
    }

    # Generate JUnit output if requested
    if ($OutputFormat -eq "junit") {
        if (-not (Get-Command Export-JUnitResults -ErrorAction SilentlyContinue)) {
            Write-Status "JUnit formatter not available. Ensure junit-formatter.ps1 is present in cli/lib/" "ERROR"
            return
        }
        Write-Status "Generating JUnit XML..." "INFO"

        # Parse findings from markdown files for JUnit format
        $junitFindings = Get-FindingsForJUnit -ReviewsDir $reviewsDir -AgentDefs $Script:AgentDefs

        $junitPath = Join-Path $reviewsDir "conclave-results.xml"
        $junitResult = Export-JUnitResults `
            -AllFindings $junitFindings `
            -OutputPath $junitPath `
            -ProjectName (Split-Path $Project -Leaf) `
            -Duration $totalDuration.TotalSeconds

        Write-Status "JUnit XML: $($junitResult.Path)" "OK"
        Write-Status "  Tests: $($junitResult.TotalTests), Failures: $($junitResult.Failures), Passed: $($junitResult.Passed)" "INFO"
    }

    # Generate compliance mapping if -Standard was specified
    if ($Standard -and -not $DryRun) {
        Write-Banner "COMPLIANCE MAPPING" "Magenta"
        $mapScript = Join-Path $PSScriptRoot "commands" "map.ps1"
        if (Test-Path $mapScript) {
            & $mapScript -ReviewsPath $reviewsDir -StandardId $Standard
        }
        else {
            Write-Status "Compliance mapping not available" "WARN"
        }
    }

    # Calculate verdict for exit codes
    $totalBlockers = ($allFindings.Values | Where-Object { $_ } | Measure-Object -Property Blockers -Sum).Sum
    $totalHigh = ($allFindings.Values | Where-Object { $_ } | Measure-Object -Property High -Sum).Sum
    if ($null -eq $totalBlockers) { $totalBlockers = 0 }
    if ($null -eq $totalHigh) { $totalHigh = 0 }

    $verdict = if ($totalBlockers -gt 0) { "HOLD" }
               elseif ($totalHigh -gt 3) { "CONDITIONAL" }
               else { "SHIP" }

    # Determine exit code based on verdict
    $exitCode = switch ($verdict) {
        "SHIP"        { 0 }
        "CONDITIONAL" { 2 }
        "HOLD"        { 1 }
        default       { 0 }
    }

    # Detect CI environment
    $isCI = $CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:CI -or $env:JENKINS_URL

    if ($isCI) {
        Write-Host ""
        $exitColor = if ($exitCode -eq 0) { "Green" } elseif ($exitCode -eq 2) { "Yellow" } else { "Red" }
        Write-Host "  CI Mode: Verdict=$verdict, Exit code=$exitCode" -ForegroundColor $exitColor
        Write-Host "  Results: $reviewsDir" -ForegroundColor Cyan
        Write-Host ""
        exit $exitCode
    }

    Write-Host "  Results: $reviewsDir" -ForegroundColor Cyan
    Write-Host ""
}

# Run
Main
