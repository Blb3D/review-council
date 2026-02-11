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

    # Tiered Standards Support
    [string]$Profile,                    # Use a pre-defined profile (e.g., defense, medical)
    
    [string[]]$AddStandards,             # Add standards to the review
    
    [string[]]$SkipStandards,            # Skip default standards

    # CI/CD Mode - enables exit codes for pipeline integration
    [switch]$CI,

    # AI Provider Override Parameters
    [ValidateSet("anthropic", "azure-openai", "openai", "ollama")]
    [string]$AIProvider,

    [string]$AIModel,

    [string]$AIEndpoint,

    # Base branch for diff-scoped reviews (auto-detected in CI)
    [string]$BaseBranch
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:ToolRoot = Split-Path $PSScriptRoot -Parent
$Script:AgentsDir = Join-Path (Join-Path $Script:ToolRoot "core") "agents"
$Script:StandardsDir = Join-Path (Join-Path $Script:ToolRoot "core") "standards"
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

$configLoaderPath = Join-Path $Script:LibDir "config-loader.ps1"
if (Test-Path $configLoaderPath) {
    . $configLoaderPath
}

$aiEnginePath = Join-Path $Script:LibDir "ai-engine.ps1"
if (Test-Path $aiEnginePath) {
    . $aiEnginePath
}

$projectScannerPath = Join-Path $Script:LibDir "project-scanner.ps1"
if (Test-Path $projectScannerPath) {
    . $projectScannerPath
}

$findingsParserPath = Join-Path $Script:LibDir "findings-parser.ps1"
if (Test-Path $findingsParserPath) {
    . $findingsParserPath
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

# AI Provider Configuration
# IMPORTANT: Never put actual API keys in this file.
# Set the environment variable name below; the key itself stays in your environment.
ai:
  provider: anthropic          # anthropic | azure-openai | openai | ollama
  temperature: 0.3
  anthropic:
    model: claude-sonnet-4-20250514
    api_key_env: ANTHROPIC_API_KEY
    max_tokens: 16000
  # azure-openai:
  #   endpoint: https://your-resource.openai.azure.com/
  #   deployment: gpt-4o
  #   api_key_env: AZURE_OPENAI_KEY
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
# MOCK FINDINGS FOR DRYRUN
# ============================================================================

function Get-MockFindings {
    param([string]$AgentKey, [string]$AgentName)

    $mockData = @{
        guardian = @"
# GUARDIAN Security Review

## Findings

### GUARDIAN-001: Hardcoded API Key [BLOCKER]

**File:** src/config.js
**Line:** 42

**Evidence:** ``const API_KEY = "sk-proj-abc123..."``

API key is hardcoded in source code, exposing credentials in version control.

**Remediation:** Move to environment variable or secrets manager.

### GUARDIAN-002: SQL Injection Risk [HIGH]

**File:** src/db/queries.js
**Line:** 87

**Evidence:** ``query = "SELECT * FROM users WHERE id=" + userId``

User input is concatenated directly into SQL query string.

**Remediation:** Use parameterized queries or an ORM.

### GUARDIAN-003: Missing HTTPS Enforcement [MEDIUM]

**File:** src/api/client.js
**Line:** 12

HTTP endpoints used for API calls. Data transmitted in plaintext.

**Remediation:** Update all endpoints to HTTPS. Add HSTS headers.

### GUARDIAN-004: Verbose Error Messages [LOW]

**File:** src/middleware/error-handler.js
**Line:** 28

Stack traces exposed in production error responses.

**Remediation:** Return generic error messages in production.

## Summary
| Severity | Count |
|----------|-------|
| BLOCKER | 1 |
| HIGH | 1 |
| MEDIUM | 1 |
| LOW | 1 |

**Verdict: HOLD**
"@
        sentinel = @"
# SENTINEL Quality Review

## Findings

### SENTINEL-001: Missing Unit Tests for Auth Module [BLOCKER]

**File:** src/auth/login.js
**Line:** 1

Authentication module has zero test coverage. Critical path untested.

**Remediation:** Add unit tests covering login, logout, token refresh flows.

### SENTINEL-002: Cyclomatic Complexity Exceeds Threshold [HIGH]

**File:** src/utils/parser.js
**Line:** 145

Function ``parseConfig`` has cyclomatic complexity of 28 (threshold: 15).

**Remediation:** Refactor into smaller, focused functions.

### SENTINEL-003: Inconsistent Error Handling [MEDIUM]

**File:** src/services/
**Line:** 0

Mix of try/catch, .catch(), and uncaught promises across service layer.

**Remediation:** Standardize error handling pattern across services.

## Summary
| Severity | Count |
|----------|-------|
| BLOCKER | 1 |
| HIGH | 1 |
| MEDIUM | 1 |

**Verdict: HOLD**
"@
        architect = @"
# ARCHITECT Code Health Review

## Findings

### ARCHITECT-001: Circular Dependency Detected [HIGH]

**File:** src/services/user.js
**Line:** 3

Circular import between user.js and auth.js causes initialization issues.

**Remediation:** Extract shared logic into a separate module.

### ARCHITECT-002: Dead Code in Legacy Module [MEDIUM]

**File:** src/legacy/helpers.js
**Line:** 200

150 lines of unreachable code after early return statement.

**Remediation:** Remove dead code or restore intended logic.

### ARCHITECT-003: Missing TypeScript Strict Mode [LOW]

**File:** tsconfig.json
**Line:** 5

Strict mode disabled, allowing implicit any types.

**Remediation:** Enable ``strict: true`` and fix resulting type errors.

## Summary
| Severity | Count |
|----------|-------|
| HIGH | 1 |
| MEDIUM | 1 |
| LOW | 1 |

**Verdict: CONDITIONAL**
"@
        navigator = @"
# NAVIGATOR UX Review

## Findings

### NAVIGATOR-001: No Loading States on API Calls [MEDIUM]

**File:** src/components/Dashboard.jsx
**Line:** 45

API calls show no loading indicator. Users see blank screen during fetch.

**Remediation:** Add loading spinners or skeleton screens.

### NAVIGATOR-002: Missing Alt Text on Images [LOW]

**File:** src/components/Gallery.jsx
**Line:** 22

Images rendered without alt attributes. Accessibility violation.

**Remediation:** Add descriptive alt text to all images.

## Summary
| Severity | Count |
|----------|-------|
| MEDIUM | 1 |
| LOW | 1 |

**Verdict: SHIP**
"@
        herald = @"
# HERALD Documentation Review

## Findings

### HERALD-001: Missing API Documentation [MEDIUM]

**File:** src/api/
**Line:** 0

No API documentation or OpenAPI spec found for 12 endpoints.

**Remediation:** Add JSDoc comments and generate OpenAPI spec.

### HERALD-002: Outdated README [LOW]

**File:** README.md
**Line:** 1

README references deprecated setup steps and removed dependencies.

**Remediation:** Update README to reflect current project state.

## Summary
| Severity | Count |
|----------|-------|
| MEDIUM | 1 |
| LOW | 1 |

**Verdict: SHIP**
"@
        operator = @"
# OPERATOR Production Readiness Review

## Findings

### OPERATOR-001: No Health Check Endpoint [HIGH]

**File:** src/server.js
**Line:** 1

No /health or /readiness endpoint for container orchestration.

**Remediation:** Add health check endpoint returning service status.

### OPERATOR-002: Missing Rate Limiting [MEDIUM]

**File:** src/middleware/
**Line:** 0

No rate limiting configured on public API endpoints.

**Remediation:** Add rate limiting middleware (e.g., express-rate-limit).

### OPERATOR-003: Hardcoded Port Number [LOW]

**File:** src/server.js
**Line:** 8

Port 3000 hardcoded instead of using environment variable.

**Remediation:** Use ``process.env.PORT || 3000``.

## Summary
| Severity | Count |
|----------|-------|
| HIGH | 1 |
| MEDIUM | 1 |
| LOW | 1 |

**Verdict: CONDITIONAL**
"@
    }

    if ($mockData.ContainsKey($AgentKey)) {
        return $mockData[$AgentKey]
    }

    # Fallback for unknown agents
    return @"
# $AgentName Review

## Findings

### $($AgentName.Substring(0,3).ToUpper())-001: Sample Finding [MEDIUM]

**File:** src/index.js
**Line:** 1

This is a mock finding generated by DryRun mode.

## Summary
| Severity | Count |
|----------|-------|
| MEDIUM | 1 |

**Verdict: SHIP**
"@
}

# ============================================================================
# AGENT EXECUTION
# ============================================================================

function Invoke-ReviewAgent {
    param(
        [string]$AgentKey,
        [string]$ProjectPath,
        [string]$ReviewsDir,
        [int]$TimeoutMinutes,
        [hashtable]$AIProvider,
        [string]$SharedContext,
        [hashtable]$EffectiveConfig
    )

    $agent = $Script:AgentDefs[$AgentKey]
    $outputFile = Join-Path $ReviewsDir "$AgentKey-findings.md"

    # Look for agent skill file (project override or default)
    $projectAgentFile = Join-Path $ProjectPath ".code-conclave\agents\$AgentKey.md"
    $defaultAgentFile = Join-Path $Script:AgentsDir "$AgentKey.md"

    $agentSkillFile = if (Test-Path $projectAgentFile) { $projectAgentFile } else { $defaultAgentFile }

    Write-AgentHeader $AgentKey

    if (-not (Test-Path $agentSkillFile)) {
        Write-Status "Agent skill file not found: $agentSkillFile" "ERROR"
        return $null
    }

    # Handle DryRun mode
    if ($DryRun) {
        Write-Status "DRY RUN - Generating mock findings for $($agent.Name)" "WARN"
        $mockContent = Get-MockFindings -AgentKey $AgentKey -AgentName $agent.Name
        $mockContent | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Status "Mock findings written: $outputFile" "OK"

        # Parse to JSON for dashboard consumption
        if (Get-Command ConvertFrom-FindingsMarkdown -ErrorAction SilentlyContinue) {
            $projectName = Split-Path $ProjectPath -Leaf
            $jsonFindings = ConvertFrom-FindingsMarkdown `
                -Content $mockContent `
                -AgentKey $AgentKey `
                -AgentName $agent.Name `
                -AgentRole $agent.Role `
                -ProjectName $projectName `
                -ProjectPath $ProjectPath `
                -DryRun
            $jsonOutputFile = Join-Path $ReviewsDir "$AgentKey-findings.json"
            Export-FindingsJson -Findings $jsonFindings -OutputPath $jsonOutputFile | Out-Null
        }

        $counts = Get-FindingsCounts $outputFile
        Write-FindingsSummary $counts
        # Attach parsed JSON data for archival
        if ($jsonFindings) { $counts.JsonFindings = $jsonFindings }
        return $counts
    }

    # Resolve agent tier
    $agentTier = "primary"
    if ($EffectiveConfig -and $EffectiveConfig.agents -and $EffectiveConfig.agents[$AgentKey]) {
        $agentCfg = $EffectiveConfig.agents[$AgentKey]
        if ($agentCfg.tier) { $agentTier = $agentCfg.tier }
    }

    $tierLabel = if ($agentTier -eq "lite") { " (lite)" } else { "" }
    Write-Status "Deploying $($agent.Name) via $($AIProvider.Name)${tierLabel}..." "RUNNING"

    # Read agent instructions
    $agentInstructions = Get-Content $agentSkillFile -Raw -Encoding UTF8

    # Build agent-specific system prompt (NOT cached — varies per agent)
    $agentSystemPrompt = @"
You are the $($agent.Name) agent performing a structured code review.

# YOUR SPECIFIC INSTRUCTIONS
$agentInstructions

# CRITICAL REQUIREMENTS
1. Output your findings in EXACTLY the format specified in CONTRACTS
2. Each finding must have: ID, Title, Severity with proper markdown headers
3. Use the format: ### $($agent.Name)-NNN: Title [SEVERITY]
4. Include Location, Effort, Issue, Evidence, Recommendation sections
5. End with a Summary table and Verdict (SHIP/CONDITIONAL/HOLD)
6. Be thorough but concise
"@

    # User prompt is minimal — project context is in SharedContext (system prompt block 1)
    $projectName = Split-Path $ProjectPath -Leaf
    $userPrompt = "Execute your $($agent.Name) review of project '$projectName' now. Analyze the code provided in the system context and produce your findings report."

    try {
        $startTime = Get-Date

        # Call AI provider with SharedContext for caching + Tier for model selection
        $aiResult = Invoke-AICompletion `
            -Provider $AIProvider `
            -SharedContext $SharedContext `
            -SystemPrompt $agentSystemPrompt `
            -UserPrompt $userPrompt `
            -Tier $agentTier

        $duration = (Get-Date) - $startTime
        $mins = [math]::Round($duration.TotalMinutes, 1)

        if (-not $aiResult.Success) {
            Write-Status "Agent failed: $($aiResult.Error)" "ERROR"
            return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0; Error = $aiResult.Error; TokensUsed = $null }
        }

        Write-Status "Completed in $mins minutes" "OK"

        if ($aiResult.TokensUsed) {
            $tokenMsg = "Tokens: $($aiResult.TokensUsed.Input) in / $($aiResult.TokensUsed.Output) out"
            $cacheDetails = @()
            if ($aiResult.TokensUsed.CacheWrite -gt 0) {
                $cacheDetails += "cache write: $($aiResult.TokensUsed.CacheWrite)"
            }
            if ($aiResult.TokensUsed.CacheRead -gt 0) {
                $cacheDetails += "cache read: $($aiResult.TokensUsed.CacheRead)"
            }
            if ($cacheDetails.Count -gt 0) {
                $tokenMsg += " ($($cacheDetails -join ', '))"
            }
            Write-Status $tokenMsg "INFO"
        }

        # Write AI response to findings file
        $aiResult.Content | Out-File -FilePath $outputFile -Encoding UTF8

        # Parse to JSON for dashboard consumption
        $jsonFindings = $null
        if (Get-Command ConvertFrom-FindingsMarkdown -ErrorAction SilentlyContinue) {
            $projectName = Split-Path $ProjectPath -Leaf
            $jsonFindings = ConvertFrom-FindingsMarkdown `
                -Content $aiResult.Content `
                -AgentKey $AgentKey `
                -AgentName $agent.Name `
                -AgentRole $agent.Role `
                -ProjectName $projectName `
                -ProjectPath $ProjectPath `
                -DurationSeconds $duration.TotalSeconds `
                -TokensUsed $aiResult.TokensUsed `
                -Tier $agentTier
            $jsonOutputFile = Join-Path $ReviewsDir "$AgentKey-findings.json"
            Export-FindingsJson -Findings $jsonFindings -OutputPath $jsonOutputFile | Out-Null
        }

        # Get findings counts
        $counts = Get-FindingsCounts $outputFile
        $counts.TokensUsed = $aiResult.TokensUsed
        # Attach parsed JSON data for archival
        if ($jsonFindings) { $counts.JsonFindings = $jsonFindings }
        Write-FindingsSummary $counts

        return $counts
    }
    catch {
        Write-Status "Agent execution failed: $_" "ERROR"
        return @{ Blockers = 0; High = 0; Medium = 0; Low = 0; Total = 0; Error = $_.ToString(); TokensUsed = $null }
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

    # Calculate totals (sum hashtable values directly for PS 5.1 compatibility)
    $totalBlockers = 0; $totalHigh = 0; $totalMedium = 0; $totalLow = 0
    foreach ($val in $AllFindings.Values) {
        if ($val) {
            $totalBlockers += [int]$val.Blockers
            $totalHigh += [int]$val.High
            $totalMedium += [int]$val.Medium
            $totalLow += [int]$val.Low
        }
    }

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
        $totalBlockers = 0; $totalHigh = 0; $totalMedium = 0; $totalLow = 0
        foreach ($val in $AllFindings.Values) {
            if ($val) {
                $totalBlockers += [int]$val.Blockers
                $totalHigh += [int]$val.High
                $totalMedium += [int]$val.Medium
                $totalLow += [int]$val.Low
            }
        }
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
        $standardsScript = Join-Path (Join-Path $PSScriptRoot "commands") "standards.ps1"
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
        $mapScript = Join-Path (Join-Path $PSScriptRoot "commands") "map.ps1"
        if (Test-Path $mapScript) {
            & $mapScript -ReviewsPath $Map -StandardId $Standard
        }
        else {
            Write-Status "Map command not found: $mapScript" "ERROR"
        }
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
        $isCI = $CI -or $DryRun -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:CI
        if ($isCI) {
            Write-Status "Auto-initializing project for CI..." "INFO"
            Initialize-Project -ProjectPath $Project
        } else {
            Write-Status "Project not initialized. Run with -Init first:" "WARN"
            Write-Host "    .\ccl.ps1 -Init -Project `"$Project`"" -ForegroundColor Gray
            Write-Host ""
            $response = Read-Host "  Initialize now? (Y/n)"
            if ($response -ne 'n') {
                Initialize-Project -ProjectPath $Project
            }
            return
        }
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

    # Load effective config (always needed for agent tier resolution)
    $effectiveConfig = Get-EffectiveConfig -ProjectPath $Project -Profile $Profile `
        -AddStandards $AddStandards -SkipStandards $SkipStandards

    # Build project context ONCE (before agent loop — shared across all agents)
    Write-Status "Scanning project context..." "INFO"
    $diffContext = Get-DiffContext -ProjectPath $Project -BaseBranch $BaseBranch

    if ($diffContext) {
        Write-Status "Diff-scoped: $($diffContext.FileCount) changed files ($($diffContext.TotalSizeKB) KB) against $($diffContext.BaseRef)" "OK"
        $fileTree = Get-ProjectFileTree -ProjectPath $Project -MaxDepth 3
        $projectSourceContent = $diffContext.FileContents
        $diffSection = "`n# GIT DIFF (what changed in this PR)`n``````diff`n$($diffContext.Diff)`n```````n"
    } else {
        $fileTree = Get-ProjectFileTree -ProjectPath $Project
        $projectSourceContent = Get-SourceFilesContent -ProjectPath $Project -MaxFiles 50 -MaxSizeKB 500
        # Extract file count from the header line: "# Source Files (N files, X KB)"
        if ($projectSourceContent -match '# Source Files \((\d+) files, ([\d.]+) KB\)') {
            Write-Status "Full scan: $($Matches[1]) files ($($Matches[2]) KB)" "INFO"
        } else {
            Write-Status "Full scan mode (no diff context available)" "INFO"
        }
        $diffSection = ""
    }

    # Build shared context (cacheable — identical across all agents)
    # This goes in system prompt block 1 for prompt caching
    $projectContracts = Join-Path $Project ".code-conclave\CONTRACTS.md"
    $defaultContracts = Join-Path $Script:ToolRoot "CONTRACTS.md"
    $contractsFile = if (Test-Path $projectContracts) { $projectContracts } else { $defaultContracts }
    $contracts = Get-Content $contractsFile -Raw -Encoding UTF8

    $projectName = Split-Path $Project -Leaf
    $sharedContext = @"
# CONTRACTS (Severity Definitions & Output Format)
$contracts

# TARGET PROJECT
Project: $projectName

# FILE STRUCTURE
$fileTree

# SOURCE FILES
$projectSourceContent
$diffSection
"@

    $contextChars = $sharedContext.Length
    $estimatedTokens = [math]::Round($contextChars / 4)
    Write-Status "Project context: ~${estimatedTokens} tokens (shared across all agents)" "INFO"

    # Initialize AI Provider (not needed for DryRun)
    $provider = $null
    if (-not $DryRun) {
        try {
            $provider = Get-AIProvider -Config $effectiveConfig `
                -ProviderOverride $AIProvider `
                -ModelOverride $AIModel `
                -EndpointOverride $AIEndpoint

            Write-Host "  AI Provider: $($provider.Name)" -ForegroundColor Magenta
            Write-Host ""

            Write-Status "Testing AI provider connection..." "INFO"
            if (-not (Test-AIProvider -Provider $provider)) {
                Write-Status "Failed to connect to AI provider: $($provider.Name)" "ERROR"
                Write-Status "Check your API key and configuration" "WARN"
                if ($CI -or $env:TF_BUILD) { exit 14 }
                return
            }
            Write-Status "AI provider connected" "OK"
        }
        catch {
            Write-Status "AI provider initialization failed: $_" "ERROR"
            if ($CI -or $env:TF_BUILD) { exit 10 }
            return
        }
    }
    else {
        Write-Host ""
    }

    # Run agents
    $allFindings = @{}
    $allTokenUsage = @{}
    $startTime = Get-Date

    foreach ($agentKey in $validAgents) {
        $findings = Invoke-ReviewAgent -AgentKey $agentKey -ProjectPath $Project `
            -ReviewsDir $reviewsDir -TimeoutMinutes $Timeout -AIProvider $provider `
            -SharedContext $sharedContext -EffectiveConfig $effectiveConfig
        $allFindings[$agentKey] = $findings

        if ($findings -and $findings.TokensUsed) {
            $allTokenUsage[$agentKey] = $findings.TokensUsed
        }

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

    # Cumulative token usage summary
    if ($allTokenUsage.Count -gt 0) {
        $totalIn = 0; $totalOut = 0; $totalCached = 0
        foreach ($t in $allTokenUsage.Values) {
            if ($t.Input) { $totalIn += $t.Input }
            if ($t.Output) { $totalOut += $t.Output }
            if ($t.CacheRead) { $totalCached += $t.CacheRead }
        }
        $tokenSummary = "  Tokens: $totalIn input, $totalOut output"
        if ($totalCached -gt 0) {
            $tokenSummary += " ($totalCached cached)"
        }
        Write-Host $tokenSummary -ForegroundColor Gray
    }

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

        # Prefer JSON data if available; fall back to markdown parsing
        $jsonFindingsForJUnit = @{}
        foreach ($key in $allFindings.Keys) {
            if ($allFindings[$key] -and $allFindings[$key].JsonFindings) {
                $jsonFindingsForJUnit[$key] = $allFindings[$key].JsonFindings
            }
        }

        $junitFindings = $null
        if ($jsonFindingsForJUnit.Count -gt 0 -and (Get-Command ConvertTo-JUnitFindings -ErrorAction SilentlyContinue)) {
            $junitFindings = ConvertTo-JUnitFindings -JsonFindings $jsonFindingsForJUnit
        } else {
            $junitFindings = Get-FindingsForJUnit -ReviewsDir $reviewsDir -AgentDefs $Script:AgentDefs
        }

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
        $mapScript = Join-Path (Join-Path $PSScriptRoot "commands") "map.ps1"
        if (Test-Path $mapScript) {
            & $mapScript -ReviewsPath $reviewsDir -StandardId $Standard
        }
        else {
            Write-Status "Compliance mapping not available" "WARN"
        }
    }

    # Calculate verdict for exit codes
    $totalBlockers = 0; $totalHigh = 0
    foreach ($val in $allFindings.Values) {
        if ($val) { $totalBlockers += [int]$val.Blockers; $totalHigh += [int]$val.High }
    }

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

    # Archive run results and clean up working files
    if (Get-Command Export-RunArchive -ErrorAction SilentlyContinue) {
        try {
            # Collect JSON findings from agent results
            $allJsonFindings = @{}
            foreach ($key in $allFindings.Keys) {
                if ($allFindings[$key] -and $allFindings[$key].JsonFindings) {
                    $allJsonFindings[$key] = $allFindings[$key].JsonFindings
                }
            }

            if ($allJsonFindings.Count -gt 0) {
                $providerName = if ($provider) { $provider.Name } else { "dryrun" }
                $archivePath = Export-RunArchive `
                    -ReviewsDir $reviewsDir `
                    -AgentFindings $allJsonFindings `
                    -RunMetadata @{
                        Timestamp       = $startTime
                        Project         = (Split-Path $Project -Leaf)
                        ProjectPath     = $Project
                        Duration        = $totalDuration.TotalSeconds
                        DryRun          = [bool]$DryRun
                        BaseBranch      = $BaseBranch
                        Standard        = $Standard
                        Provider        = $providerName
                        AgentsRequested = $validAgents
                        Verdict         = $verdict
                        ExitCode        = $exitCode
                    }
                Write-Status "Run archived: $archivePath" "OK"

                # Clean up working files (dashboard will use archive for history)
                Remove-WorkingFindings -ReviewsDir $reviewsDir
                Write-Status "Working files cleaned up" "INFO"
            }
        }
        catch {
            Write-Status "Archive failed: $_" "WARN"
        }
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
