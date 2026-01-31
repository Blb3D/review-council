<#
.SYNOPSIS
    Review Council - AI-Powered Code Review Orchestrator
    
.DESCRIPTION
    Deploy 6 specialized AI agents to review any codebase. Each agent examines
    the project from a different perspective: Quality, Security, Architecture,
    UX, Documentation, and Production Readiness.
    
.PARAMETER Project
    Path to the project to review (required)
    
.PARAMETER Agent
    Run a single agent: sentinel, guardian, architect, navigator, herald, operator
    
.PARAMETER Agents
    Run specific agents (comma-separated)
    
.PARAMETER StartFrom
    Resume from a specific agent, skipping earlier ones
    
.PARAMETER Parallel
    Run all agents in parallel (faster, but no handoffs)
    
.PARAMETER SkipSynthesis
    Skip generating the final synthesis report
    
.PARAMETER DryRun
    Show what would execute without running
    
.PARAMETER Timeout
    Timeout per agent in minutes (default: 30)

.EXAMPLE
    .\review-council.ps1 -Project "C:\repos\my-app"
    
.EXAMPLE
    .\review-council.ps1 -Project "C:\repos\my-app" -Agent sentinel
    
.EXAMPLE
    .\review-council.ps1 -Project "C:\repos\my-app" -Parallel
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Project,
    
    [string]$Agent,
    
    [string[]]$Agents,
    
    [string]$StartFrom,
    
    [switch]$Parallel,
    
    [switch]$SkipSynthesis,
    
    [switch]$DryRun,
    
    [int]$Timeout = 30
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:ToolRoot = $PSScriptRoot
$Script:AgentsDir = Join-Path $ToolRoot "agents"
$Script:ContractsFile = Join-Path $ToolRoot "CONTRACTS.md"

$Script:AgentDefs = [ordered]@{
    sentinel  = @{ Name = "SENTINEL";  Role = "Quality & Compliance";    Icon = [char]::ConvertFromUtf32(0x1F6E1); Color = "Yellow" }
    guardian  = @{ Name = "GUARDIAN";  Role = "Security";                Icon = [char]::ConvertFromUtf32(0x1F512); Color = "Red" }
    architect = @{ Name = "ARCHITECT"; Role = "Code Health";             Icon = [char]::ConvertFromUtf32(0x1F3D7); Color = "Blue" }
    navigator = @{ Name = "NAVIGATOR"; Role = "UX Review";               Icon = [char]::ConvertFromUtf32(0x1F9ED); Color = "Cyan" }
    herald    = @{ Name = "HERALD";    Role = "Documentation";           Icon = [char]::ConvertFromUtf32(0x1F4DC); Color = "Magenta" }
    operator  = @{ Name = "OPERATOR";  Role = "Production Readiness";    Icon = [char]::ConvertFromUtf32(0x2699);  Color = "Green" }
}

# ============================================================================
# DISPLAY HELPERS  
# ============================================================================

function Write-Logo {
    Write-Host ""
    Write-Host "  ██████╗ ███████╗██╗   ██╗██╗███████╗██╗    ██╗" -ForegroundColor Cyan
    Write-Host "  ██╔══██╗██╔════╝██║   ██║██║██╔════╝██║    ██║" -ForegroundColor Cyan
    Write-Host "  ██████╔╝█████╗  ██║   ██║██║█████╗  ██║ █╗ ██║" -ForegroundColor Cyan
    Write-Host "  ██╔══██╗██╔══╝  ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║" -ForegroundColor Cyan
    Write-Host "  ██║  ██║███████╗ ╚████╔╝ ██║███████╗╚███╔███╔╝" -ForegroundColor Cyan
    Write-Host "  ╚═╝  ╚═╝╚══════╝  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ " -ForegroundColor Cyan
    Write-Host "   ██████╗ ██████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗██╗     " -ForegroundColor DarkCyan
    Write-Host "  ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔════╝██║██║     " -ForegroundColor DarkCyan
    Write-Host "  ██║     ██║   ██║██║   ██║██╔██╗ ██║██║     ██║██║     " -ForegroundColor DarkCyan
    Write-Host "  ██║     ██║   ██║██║   ██║██║╚██╗██║██║     ██║██║     " -ForegroundColor DarkCyan
    Write-Host "  ╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║╚██████╗██║███████╗" -ForegroundColor DarkCyan
    Write-Host "   ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝╚══════╝" -ForegroundColor DarkCyan
    Write-Host "                                              v1.0" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Status {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "RUN"   { "Cyan" }
        default { "Gray" }
    }
    Write-Host "  [$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Msg -ForegroundColor $color
}

function Write-AgentHeader {
    param([string]$Key)
    $a = $Script:AgentDefs[$Key]
    Write-Host ""
    Write-Host "  $($a.Icon) " -NoNewline
    Write-Host $a.Name -ForegroundColor $a.Color -NoNewline
    Write-Host " - $($a.Role)" -ForegroundColor Gray
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
}

# ============================================================================
# FINDINGS ANALYSIS
# ============================================================================

function Get-Counts {
    param([string]$File)
    if (-not (Test-Path $File)) { 
        return @{ B = 0; H = 0; M = 0; L = 0; T = 0 } 
    }
    $c = Get-Content $File -Raw
    $r = @{
        B = ([regex]::Matches($c, '\[BLOCKER\]')).Count
        H = ([regex]::Matches($c, '\[HIGH\]')).Count
        M = ([regex]::Matches($c, '\[MEDIUM\]')).Count
        L = ([regex]::Matches($c, '\[LOW\]')).Count
    }
    $r.T = $r.B + $r.H + $r.M + $r.L
    return $r
}

function Write-Counts {
    param([hashtable]$C)
    Write-Host "  Results: " -NoNewline
    if ($C.T -eq 0) { Write-Host "No issues" -ForegroundColor Green; return }
    if ($C.B -gt 0) { Write-Host "$($C.B) BLOCKER " -NoNewline -ForegroundColor Red }
    if ($C.H -gt 0) { Write-Host "$($C.H) HIGH " -NoNewline -ForegroundColor Yellow }
    if ($C.M -gt 0) { Write-Host "$($C.M) MEDIUM " -NoNewline -ForegroundColor Cyan }
    if ($C.L -gt 0) { Write-Host "$($C.L) LOW" -NoNewline -ForegroundColor Gray }
    Write-Host ""
}

# ============================================================================
# AGENT EXECUTION
# ============================================================================

function Invoke-Agent {
    param([string]$Key, [string]$ProjectPath, [string]$OutputDir)
    
    $agent = $Script:AgentDefs[$Key]
    $skillFile = Join-Path $Script:AgentsDir "$Key.md"
    $outputFile = Join-Path $OutputDir "$Key-findings.md"
    
    Write-AgentHeader $Key
    
    if (-not (Test-Path $skillFile)) {
        Write-Status "Skill file missing: $skillFile" "ERROR"
        return @{ B = 0; H = 0; M = 0; L = 0; T = 0; Err = "Missing skill" }
    }
    
    $prompt = @"
You are the $($agent.Name) agent performing a structured code review.

PROJECT TO REVIEW: $ProjectPath

STEP 1: Read the contracts file for severity definitions and output format:
$Script:ContractsFile

STEP 2: Read your agent instructions:
$skillFile  

STEP 3: Change to the project directory and perform your review:
cd "$ProjectPath"

STEP 4: Write findings to this exact path in the format specified:
$outputFile

STEP 5: When done, output exactly:
REVIEW COMPLETE: X BLOCKER, Y HIGH, Z MEDIUM, W LOW

Begin now.
"@

    if ($DryRun) {
        Write-Status "DRY RUN: Would deploy $($agent.Name)" "WARN"
        return @{ B = 0; H = 0; M = 0; L = 0; T = 0 }
    }
    
    Write-Status "Deploying..." "RUN"
    $start = Get-Date
    
    try {
        # Run Claude Code
        $result = $prompt | claude --dangerously-skip-permissions 2>&1
        
        $dur = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
        Write-Status "Done in $dur min" "OK"
        
        $counts = Get-Counts $outputFile
        Write-Counts $counts
        return $counts
    }
    catch {
        Write-Status "Failed: $_" "ERROR"
        return @{ B = 0; H = 0; M = 0; L = 0; T = 0; Err = $_.ToString() }
    }
}

function Invoke-AgentParallel {
    param([string[]]$Keys, [string]$ProjectPath, [string]$OutputDir)
    
    Write-Status "Launching $($Keys.Count) agents in parallel..." "RUN"
    
    $jobs = @{}
    foreach ($key in $Keys) {
        $agent = $Script:AgentDefs[$key]
        $skillFile = Join-Path $Script:AgentsDir "$key.md"
        $outputFile = Join-Path $OutputDir "$key-findings.md"
        
        $prompt = @"
You are the $($agent.Name) agent performing a structured code review.

PROJECT TO REVIEW: $ProjectPath

STEP 1: Read the contracts file for severity definitions and output format:
$Script:ContractsFile

STEP 2: Read your agent instructions:
$skillFile  

STEP 3: Change to the project directory and perform your review:
cd "$ProjectPath"

STEP 4: Write findings to this exact path in the format specified:
$outputFile

STEP 5: When done, output exactly:
REVIEW COMPLETE: X BLOCKER, Y HIGH, Z MEDIUM, W LOW

Begin now.
"@
        
        Write-Host "  $($agent.Icon) $($agent.Name) " -NoNewline -ForegroundColor $agent.Color
        Write-Host "launched" -ForegroundColor DarkGray
        
        if (-not $DryRun) {
            $jobs[$key] = Start-Job -ScriptBlock {
                param($p)
                $p | claude --dangerously-skip-permissions 2>&1
            } -ArgumentList $prompt
        }
    }
    
    if ($DryRun) {
        return @{}
    }
    
    Write-Host ""
    Write-Status "Waiting for agents to complete..." "RUN"
    
    # Wait and collect results
    $results = @{}
    $completed = @()
    
    while ($completed.Count -lt $Keys.Count) {
        foreach ($key in $Keys) {
            if ($key -in $completed) { continue }
            
            $job = $jobs[$key]
            if ($job.State -eq 'Completed' -or $job.State -eq 'Failed') {
                $agent = $Script:AgentDefs[$key]
                $outputFile = Join-Path $OutputDir "$key-findings.md"
                
                $null = Receive-Job $job
                Remove-Job $job
                
                $counts = Get-Counts $outputFile
                $results[$key] = $counts
                $completed += $key
                
                Write-Host "  $($agent.Icon) $($agent.Name) " -NoNewline -ForegroundColor $agent.Color
                if ($counts.B -gt 0) { Write-Host "$($counts.B)B " -NoNewline -ForegroundColor Red }
                if ($counts.H -gt 0) { Write-Host "$($counts.H)H " -NoNewline -ForegroundColor Yellow }
                if ($counts.M -gt 0) { Write-Host "$($counts.M)M " -NoNewline -ForegroundColor Cyan }
                if ($counts.L -gt 0) { Write-Host "$($counts.L)L " -NoNewline -ForegroundColor Gray }
                if ($counts.T -eq 0) { Write-Host "clean" -NoNewline -ForegroundColor Green }
                Write-Host ""
            }
        }
        Start-Sleep -Milliseconds 500
    }
    
    return $results
}

# ============================================================================
# SYNTHESIS REPORT
# ============================================================================

function New-Report {
    param([string]$ProjectPath, [string]$OutputDir, [hashtable]$All)
    
    $reportPath = Join-Path $OutputDir "RELEASE-READINESS-REPORT.md"
    $projectName = Split-Path $ProjectPath -Leaf
    $date = Get-Date -Format "yyyy-MM-dd HH:mm"
    
    $tB = ($All.Values | Measure-Object -Property B -Sum).Sum
    $tH = ($All.Values | Measure-Object -Property H -Sum).Sum
    $tM = ($All.Values | Measure-Object -Property M -Sum).Sum
    $tL = ($All.Values | Measure-Object -Property L -Sum).Sum
    
    $verdict = if ($tB -gt 0) { "HOLD" } elseif ($tH -gt 3) { "CONDITIONAL" } else { "SHIP" }
    $vColor = switch ($verdict) { "SHIP" { "Green" } "CONDITIONAL" { "Yellow" } "HOLD" { "Red" } }
    
    $report = @"
# Release Readiness Report

**Project:** $projectName  
**Date:** $date  
**Verdict:** $verdict

## Summary

| Severity | Count |
|----------|-------|
| BLOCKER | $tB |
| HIGH | $tH |
| MEDIUM | $tM |
| LOW | $tL |

## Agent Reports

| Agent | B | H | M | L |
|-------|---|---|---|---|
"@

    foreach ($key in $Script:AgentDefs.Keys) {
        $a = $Script:AgentDefs[$key]
        $f = $All[$key]
        if ($f) {
            $report += "| $($a.Name) | $($f.B) | $($f.H) | $($f.M) | $($f.L) |`n"
        }
    }

    $report += @"

## Findings

"@
    foreach ($key in $Script:AgentDefs.Keys) {
        $file = Join-Path $OutputDir "$key-findings.md"
        if (Test-Path $file) {
            $report += "- [$key-findings.md](./$key-findings.md)`n"
        }
    }

    $report | Out-File $reportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor $vColor
    Write-Host "  ║     VERDICT: " -NoNewline -ForegroundColor $vColor
    Write-Host ("{0,-12}" -f $verdict) -NoNewline -ForegroundColor $vColor
    Write-Host "           ║" -ForegroundColor $vColor
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor $vColor
    Write-Host ""
    
    return $reportPath
}

# ============================================================================
# MAIN
# ============================================================================

Write-Logo

# Validate Claude CLI
if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not $DryRun) {
    Write-Status "Claude Code CLI not found. Install: npm install -g @anthropic-ai/claude-code" "ERROR"
    exit 1
}

# Validate project
if (-not (Test-Path $Project)) {
    Write-Status "Project not found: $Project" "ERROR"
    exit 1
}

$Project = (Resolve-Path $Project).Path
$outputDir = Join-Path $Project ".review-council"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Host "  Project: $Project" -ForegroundColor White
Write-Host "  Output:  $outputDir" -ForegroundColor Gray
Write-Host ""

# Determine agents
$toRun = @()
if ($Agent) {
    $toRun = @($Agent.ToLower())
}
elseif ($Agents.Count -gt 0) {
    $toRun = $Agents | ForEach-Object { $_.ToLower() }
}
else {
    $toRun = @($Script:AgentDefs.Keys)
}

# StartFrom filter
if ($StartFrom) {
    $found = $false
    $toRun = $toRun | Where-Object { if ($_ -eq $StartFrom.ToLower()) { $found = $true }; $found }
}

# Validate agent names
$toRun = $toRun | Where-Object { $Script:AgentDefs.ContainsKey($_) }

if ($toRun.Count -eq 0) {
    Write-Status "No valid agents specified" "ERROR"
    exit 1
}

Write-Host "  Agents: $($toRun -join ', ')" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date
$allResults = @{}

if ($Parallel -and $toRun.Count -gt 1) {
    $allResults = Invoke-AgentParallel -Keys $toRun -ProjectPath $Project -OutputDir $outputDir
}
else {
    foreach ($key in $toRun) {
        $allResults[$key] = Invoke-Agent -Key $key -ProjectPath $Project -OutputDir $outputDir
    }
}

$duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

Write-Host ""
Write-Host "  ═══════════════════════════════════════════" -ForegroundColor Green
Write-Host "  REVIEW COMPLETE - $duration minutes" -ForegroundColor Green
Write-Host "  ═══════════════════════════════════════════" -ForegroundColor Green

if (-not $SkipSynthesis -and $toRun.Count -gt 1 -and -not $DryRun) {
    $reportPath = New-Report -ProjectPath $Project -OutputDir $outputDir -All $allResults
}

Write-Host "  Results: $outputDir" -ForegroundColor Cyan
Write-Host ""
