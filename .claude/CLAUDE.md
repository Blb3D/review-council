# Code Conclave - Pipeline Integration Tasks

## CRITICAL: Read Before Any Agent Work

**`docs/FALSE-POSITIVE-ANALYSIS-2026-02-11.md`** — Full 6-agent run against filaops produced 75% false positive BLOCKERs. Root cause: agents infer from file structure instead of reading file contents. Key fixes needed:
1. **Verification-before-flagging** — agents must read actual files before claiming something is missing
2. **Speculative findings cap at MEDIUM** — hedging language ("likely", "may", "appears to") cannot be BLOCKER/HIGH
3. **Evidence requirements** — BLOCKER/HIGH must include file:line + code snippet
4. **Cross-agent deduplication** — synthesis step should group related findings

Read the full analysis before modifying agent prompts or severity classification.

---

## Project Context

Code Conclave is an AI-powered code review orchestration system. Management has approved moving forward with **CI/CD pipeline integration** as the priority over VS Code extension development.

**Key Requirements from Management:**
1. Containerized solution that runs in ADO pipelines
2. JUnit/NUnit output format for ADO test results integration
3. PR blocking when blockers are found
4. Results posted to Azure DevOps

## Current State

Repository: `C:\repos\review-council` (still needs rename to `code-conclave`)

```
cli/
├── ccl.ps1                    # Main CLI - has -Standard, -Map, -Standards
├── commands/
│   ├── report.ps1             # Has -Format: markdown, json, csv
│   ├── standards.ps1          
│   └── map.ps1                
└── lib/
    ├── yaml-parser.ps1        
    └── mapping-engine.ps1     # Get-ComplianceMapping, Export-ComplianceReport

core/
├── standards/regulated/       # CMMC, FDA 820, FDA Part 11 packs
├── templates/                 # Report templates
└── schemas/standard.schema.json
```

## Task Order

```
TASK-013: JUnit Output Format     ← START HERE (blocks everything else)
    ↓
TASK-014: Exit Codes for CI
    ↓
TASK-015: Containerization
    ↓
TASK-016: ADO Pipeline Template
    ↓
TASK-012: VS Code Extension       ← DEFERRED (do after pipeline works)
```

---

## TASK-013: JUnit/NUnit XML Output

**Priority:** HIGH - Blocks TASK-014, 015, 016
**Estimated Effort:** 2-3 hours

### Goal
Add `-OutputFormat junit` option that produces Azure DevOps compatible JUnit XML test results.

### Acceptance Criteria
- [ ] `ccl.ps1 -Project ./repo -OutputFormat junit` produces valid JUnit XML
- [ ] Output file: `{ReviewsDir}/conclave-results.xml`
- [ ] Each agent = one `<testsuite>`
- [ ] Each finding = one `<testcase>`
- [ ] BLOCKER/HIGH findings = `<failure>` elements (configurable)
- [ ] MEDIUM/LOW = passing tests (no `<failure>` element)
- [ ] File/line info included in testcase attributes when available

### Implementation

#### Step 1: Create `cli/lib/junit-formatter.ps1`

```powershell
<#
.SYNOPSIS
    JUnit XML formatter for Code Conclave findings.

.DESCRIPTION
    Converts Code Conclave findings to JUnit XML format compatible with
    Azure DevOps, Jenkins, and other CI systems.
#>

function Export-JUnitResults {
    <#
    .SYNOPSIS
        Export findings as JUnit XML.
    
    .PARAMETER AllFindings
        Hashtable of findings keyed by agent name.
        Each value is an array of finding objects with: Id, Title, Severity, File, Line, Description
    
    .PARAMETER OutputPath
        Path to write the XML file.
    
    .PARAMETER FailOn
        Array of severities that should be marked as failures. Default: @("BLOCKER", "HIGH")
    
    .PARAMETER ProjectName
        Name to use in the testsuites element.
    
    .PARAMETER Duration
        Total duration in seconds (optional).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$AllFindings,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [string[]]$FailOn = @("BLOCKER", "HIGH"),
        
        [string]$ProjectName = "Code Conclave",
        
        [double]$Duration = 0
    )
    
    # Create XML document
    $xml = New-Object System.Xml.XmlDocument
    $declaration = $xml.CreateXmlDeclaration("1.0", "UTF-8", $null)
    [void]$xml.AppendChild($declaration)
    
    # Root element: <testsuites>
    $testsuites = $xml.CreateElement("testsuites")
    $testsuites.SetAttribute("name", $ProjectName)
    $testsuites.SetAttribute("timestamp", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"))
    
    $totalTests = 0
    $totalFailures = 0
    $totalSkipped = 0
    
    # Process each agent as a testsuite
    foreach ($agentKey in $AllFindings.Keys) {
        $findings = $AllFindings[$agentKey]
        $agentName = $agentKey.ToUpper()
        
        $testsuite = $xml.CreateElement("testsuite")
        $testsuite.SetAttribute("name", $agentName)
        $testsuite.SetAttribute("tests", $findings.Count)
        
        $suiteFailures = 0
        
        foreach ($finding in $findings) {
            $totalTests++
            
            # Create testcase
            $testcase = $xml.CreateElement("testcase")
            $testcase.SetAttribute("name", "$($finding.Id): $($finding.Title)")
            $testcase.SetAttribute("classname", $agentName)
            
            # Add file/line if available
            if ($finding.File) {
                $testcase.SetAttribute("file", $finding.File)
            }
            if ($finding.Line) {
                $testcase.SetAttribute("line", $finding.Line.ToString())
            }
            
            # Determine if this is a failure
            $isFailure = $FailOn -contains $finding.Severity
            
            if ($isFailure) {
                $totalFailures++
                $suiteFailures++
                
                $failure = $xml.CreateElement("failure")
                $failure.SetAttribute("message", "[$($finding.Severity)] $($finding.Title)")
                $failure.SetAttribute("type", $finding.Severity.ToLower())
                
                # Build failure content
                $failureText = @()
                $failureText += "Severity: $($finding.Severity)"
                if ($finding.File) { $failureText += "File: $($finding.File)" }
                if ($finding.Line) { $failureText += "Line: $($finding.Line)" }
                if ($finding.Description) { $failureText += "`nDescription:`n$($finding.Description)" }
                if ($finding.Remediation) { $failureText += "`nRemediation:`n$($finding.Remediation)" }
                
                $failure.InnerText = $failureText -join "`n"
                [void]$testcase.AppendChild($failure)
            }
            
            [void]$testsuite.AppendChild($testcase)
        }
        
        $testsuite.SetAttribute("failures", $suiteFailures)
        $testsuite.SetAttribute("errors", "0")
        $testsuite.SetAttribute("skipped", "0")
        
        [void]$testsuites.AppendChild($testsuite)
    }
    
    # Set totals on root element
    $testsuites.SetAttribute("tests", $totalTests)
    $testsuites.SetAttribute("failures", $totalFailures)
    $testsuites.SetAttribute("errors", "0")
    if ($Duration -gt 0) {
        $testsuites.SetAttribute("time", [math]::Round($Duration, 2).ToString())
    }
    
    [void]$xml.AppendChild($testsuites)
    
    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Save XML
    $xml.Save($OutputPath)
    
    return @{
        Path = $OutputPath
        TotalTests = $totalTests
        Failures = $totalFailures
        Passed = $totalTests - $totalFailures
    }
}

# Export function
Export-ModuleMember -Function Export-JUnitResults -ErrorAction SilentlyContinue
```

#### Step 2: Modify `cli/ccl.ps1`

Add to parameter block (around line 70):

```powershell
[ValidateSet("markdown", "json", "junit")]
[string]$OutputFormat = "markdown",
```

Source the new library after existing library loads (around line 100):

```powershell
$junitFormatterPath = Join-Path $Script:LibDir "junit-formatter.ps1"
if (Test-Path $junitFormatterPath) {
    . $junitFormatterPath
}
```

After the synthesis report generation (around line 725), add JUnit output:

```powershell
# Generate JUnit output if requested
if ($OutputFormat -eq "junit") {
    Write-Status "Generating JUnit XML..." "INFO"
    
    # Convert allFindings to the format expected by JUnit formatter
    $junitFindings = @{}
    foreach ($agentKey in $allFindings.Keys) {
        $junitFindings[$agentKey] = @()
        $findingsFile = Join-Path $reviewsDir "$agentKey-findings.md"
        if (Test-Path $findingsFile) {
            # Parse findings from markdown file
            $content = Get-Content $findingsFile -Raw
            $pattern = '###\s+([A-Z]+\-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]'
            $matches = [regex]::Matches($content, $pattern)
            foreach ($match in $matches) {
                $junitFindings[$agentKey] += @{
                    Id = $match.Groups[1].Value
                    Title = $match.Groups[2].Value.Trim()
                    Severity = $match.Groups[3].Value
                    File = $null  # Could be extracted with more parsing
                    Line = $null
                    Description = ""
                }
            }
        }
    }
    
    $junitPath = Join-Path $reviewsDir "conclave-results.xml"
    $junitResult = Export-JUnitResults -AllFindings $junitFindings -OutputPath $junitPath -ProjectName (Split-Path $Project -Leaf)
    
    Write-Status "JUnit XML: $($junitResult.Path)" "OK"
    Write-Status "  Tests: $($junitResult.TotalTests), Failures: $($junitResult.Failures)" "INFO"
}
```

#### Step 3: Also update `cli/commands/report.ps1`

Add "junit" to the ValidateSet for `-Format` parameter:

```powershell
[ValidateSet("markdown", "json", "csv", "junit")]
[string]$Format = "markdown",
```

Add a case in the switch statement for junit format.

### Test Cases

```powershell
# Test 1: Basic JUnit output
.\ccl.ps1 -Project "C:\repos\test-project" -OutputFormat junit -Agent guardian
# Expected: Creates .code-conclave/reviews/conclave-results.xml

# Test 2: Validate XML structure
[xml]$result = Get-Content "C:\repos\test-project\.code-conclave\reviews\conclave-results.xml"
$result.testsuites.testsuite.Count  # Should be 1 (only guardian ran)
$result.testsuites.tests            # Should match finding count

# Test 3: Verify failures are marked correctly
$result.testsuites.testsuite.testcase | Where-Object { $_.failure } | Measure-Object
# Should match BLOCKER + HIGH count
```

### JUnit XML Example Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="my-project" timestamp="2026-02-03T14:30:00" tests="12" failures="3" errors="0">
  <testsuite name="GUARDIAN" tests="5" failures="2" errors="0" skipped="0">
    <testcase name="GUARDIAN-001: Hardcoded API Key" classname="GUARDIAN" file="src/config.js" line="42">
      <failure message="[BLOCKER] Hardcoded API Key" type="blocker">
        Severity: BLOCKER
        File: src/config.js
        Line: 42
        
        Description:
        API key is hardcoded in source code, exposing credentials.
        
        Remediation:
        Move to environment variable or secrets manager.
      </failure>
    </testcase>
    <testcase name="GUARDIAN-002: HTTPS Not Enforced" classname="GUARDIAN">
      <!-- No failure element = passed -->
    </testcase>
  </testsuite>
  <testsuite name="SENTINEL" tests="7" failures="1" errors="0" skipped="0">
    ...
  </testsuite>
</testsuites>
```

---

## TASK-014: Exit Codes for CI

**Priority:** HIGH - Required for PR blocking
**Estimated Effort:** 1 hour
**Depends On:** TASK-013

### Goal
CLI returns meaningful exit codes so pipelines can fail builds on blockers.

### Exit Code Specification

| Code | Meaning | Verdict | Pipeline Behavior |
|------|---------|---------|-------------------|
| 0 | Success | SHIP | ✅ Pass |
| 1 | Blockers found | HOLD | ❌ Fail build |
| 2 | High findings exceed threshold | CONDITIONAL | ⚠️ Configurable |
| 10 | Execution error | - | ❌ Fail build |
| 11 | Invalid arguments | - | ❌ Fail build |
| 12 | Project not found | - | ❌ Fail build |
| 13 | Agent execution failed | - | ❌ Fail build |

### Implementation

#### Step 1: Add `-CI` parameter to `cli/ccl.ps1`

Add to parameter block:

```powershell
[switch]$CI,
```

#### Step 2: Add exit code logic at end of Main function

Replace or modify the end of the `Main` function (after line 740):

```powershell
# Calculate exit code based on verdict
$exitCode = switch ($verdict) {
    "SHIP"        { 0 }
    "CONDITIONAL" { 2 }
    "HOLD"        { 1 }
    default       { 0 }
}

# In CI mode, exit with code
# Also detect common CI environment variables
$isCI = $CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:CI -or $env:JENKINS_URL

if ($isCI) {
    Write-Host ""
    Write-Host "  CI Mode: Exiting with code $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
    exit $exitCode
}

Write-Host "  Results: $reviewsDir" -ForegroundColor Cyan
Write-Host ""
```

#### Step 3: Add early exit codes for errors

At various error points in the script, add proper exit handling:

```powershell
# Example: Project not found (around line 619)
if (-not (Test-Path $Project)) {
    Write-Status "Project path does not exist: $Project" "ERROR"
    if ($CI -or $env:TF_BUILD) { exit 12 }
    return
}

# Example: No valid agents (around line 696)
if ($validAgents.Count -eq 0) {
    Write-Status "No valid agents to run" "ERROR"
    if ($CI -or $env:TF_BUILD) { exit 11 }
    return
}
```

### Test Cases

```powershell
# Test in simulated CI mode
$env:TF_BUILD = "true"

# Test SHIP verdict (no blockers)
.\ccl.ps1 -Project "./clean-project" -CI
$LASTEXITCODE  # Should be 0

# Test HOLD verdict (has blockers)
.\ccl.ps1 -Project "./project-with-blockers" -CI
$LASTEXITCODE  # Should be 1

# Test invalid project
.\ccl.ps1 -Project "./nonexistent" -CI
$LASTEXITCODE  # Should be 12

# Cleanup
Remove-Item Env:TF_BUILD
```

---

## TASK-015: Containerization

**Priority:** MEDIUM
**Estimated Effort:** 2 hours
**Depends On:** TASK-013, TASK-014

### Goal
Create a Docker container that can run Code Conclave in any CI environment.

### Deliverables
1. `Dockerfile` in repo root
2. `.dockerignore`
3. `docker-compose.yml` for local testing
4. Documentation update

### Implementation

#### Step 1: Create `Dockerfile`

```dockerfile
# Code Conclave - AI-Powered Code Review Container
# 
# Usage:
#   docker build -t conclave:latest .
#   docker run -v /path/to/repo:/repo conclave:latest -Project /repo -OutputFormat junit -CI

FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

LABEL org.opencontainers.image.title="Code Conclave" \
      org.opencontainers.image.description="AI-Powered Code Review with Compliance Mapping" \
      org.opencontainers.image.version="2.0.0" \
      org.opencontainers.image.source="https://github.com/Blb3D/code-conclave"

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /conclave

# Copy application files
COPY cli/ ./cli/
COPY core/ ./core/

# Create directories for output
RUN mkdir -p /output /repo

# Create non-root user for security
RUN useradd -m -s /bin/bash conclave \
    && chown -R conclave:conclave /conclave /output /repo

USER conclave

# Set environment variables
ENV CONCLAVE_HOME=/conclave
ENV PATH="${CONCLAVE_HOME}/cli:${PATH}"

# Default entrypoint
ENTRYPOINT ["pwsh", "/conclave/cli/ccl.ps1"]

# Default to help if no args
CMD ["--help"]
```

#### Step 2: Create `.dockerignore`

```
# Git
.git
.gitignore

# IDE
.vscode
.idea
*.swp
*.swo

# Node modules (dashboard)
dashboard/node_modules
node_modules

# Local config
*.local.*
.env
.env.*

# Build artifacts
*.log
*.tmp

# Documentation source (not needed in container)
docs/*.md

# Examples (not needed in container)
examples/

# Tests
tests/
*.test.ps1
```

#### Step 3: Create `docker-compose.yml` for local testing

```yaml
version: '3.8'

services:
  conclave:
    build: .
    image: conclave:latest
    volumes:
      - ./test-repo:/repo:ro           # Mount repo read-only
      - ./output:/output               # Output directory
    environment:
      - CI=true
    command: ["-Project", "/repo", "-OutputFormat", "junit", "-CI"]
```

#### Step 4: Add to documentation

Create or update `docs/CONTAINER.md`:

```markdown
# Running Code Conclave in Containers

## Quick Start

```bash
# Build the image
docker build -t conclave:latest .

# Run a review
docker run -v /path/to/your/repo:/repo conclave:latest \
  -Project /repo \
  -OutputFormat junit \
  -CI
```

## Azure DevOps Pipeline

```yaml
- task: Docker@2
  inputs:
    command: run
    arguments: >
      -v $(Build.SourcesDirectory):/repo
      conclave:latest
      -Project /repo
      -Standard cmmc-l2
      -OutputFormat junit
      -CI
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | SHIP - Ready for release |
| 1 | HOLD - Blockers found |
| 2 | CONDITIONAL - Review recommended |
| 10+ | Error conditions |
```

### Test Cases

```bash
# Build container
docker build -t conclave:latest .

# Test help
docker run conclave:latest --help

# Test with a real repo
docker run -v /path/to/test-repo:/repo conclave:latest \
  -Project /repo \
  -Agent guardian \
  -OutputFormat junit \
  -CI

echo "Exit code: $?"

# Check output
cat /path/to/test-repo/.code-conclave/reviews/conclave-results.xml
```

---

## TASK-016: ADO Pipeline Template

**Priority:** MEDIUM
**Estimated Effort:** 1-2 hours
**Depends On:** TASK-015

### Goal
Provide ready-to-use Azure Pipelines YAML that teams can copy into their repos.

### Deliverables
- `examples/azure-pipelines.yml`
- `examples/azure-pipelines-pr.yml` (PR-specific)
- Documentation

### Implementation

#### Create `examples/azure-pipelines.yml`

```yaml
# Code Conclave - Azure DevOps Pipeline
# 
# This pipeline runs Code Conclave reviews on your codebase.
# Copy this file to your repo root as azure-pipelines.yml
#
# Prerequisites:
# - Code Conclave container image available (or build from source)
# - Optional: AZURE_OPENAI_KEY variable for AI provider

trigger:
  branches:
    include:
      - main
      - develop
      - release/*

pr:
  branches:
    include:
      - main
      - develop

variables:
  # Compliance standard to check against (or 'none')
  CONCLAVE_STANDARD: 'cmmc-l2'
  # Container image location
  CONCLAVE_IMAGE: 'ghcr.io/blb3d/conclave:latest'  # Update to your registry

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: CodeReview
  displayName: 'Code Conclave Review'
  jobs:
  - job: Review
    displayName: 'Run AI Code Review'
    
    # Option 1: Use pre-built container
    container: ${{ variables.CONCLAVE_IMAGE }}
    
    steps:
    - checkout: self
      fetchDepth: 0  # Full history for better analysis
    
    # Run Code Conclave
    - pwsh: |
        /conclave/cli/ccl.ps1 `
          -Project $(Build.SourcesDirectory) `
          -Standard $(CONCLAVE_STANDARD) `
          -OutputFormat junit `
          -CI
      displayName: 'Run Code Conclave Review'
      continueOnError: true  # Let test publish handle pass/fail
    
    # Publish test results to ADO
    - task: PublishTestResults@2
      displayName: 'Publish Code Review Results'
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '**/.code-conclave/reviews/conclave-results.xml'
        testRunTitle: 'Code Conclave Review'
        failTaskOnFailedTests: true  # Fail build on BLOCKER/HIGH findings
      condition: always()
    
    # Publish full reports as artifacts
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Review Reports'
      inputs:
        pathToPublish: '$(Build.SourcesDirectory)/.code-conclave/reviews'
        artifactName: 'CodeConclaveReports'
      condition: always()

# Optional: Compliance report stage
- stage: ComplianceReport
  displayName: 'Compliance Mapping'
  dependsOn: CodeReview
  condition: and(succeeded(), ne(variables['CONCLAVE_STANDARD'], 'none'))
  jobs:
  - job: Mapping
    displayName: 'Generate Compliance Report'
    container: ${{ variables.CONCLAVE_IMAGE }}
    steps:
    - checkout: self
    
    - pwsh: |
        /conclave/cli/ccl.ps1 `
          -Map $(Build.SourcesDirectory)/.code-conclave/reviews `
          -Standard $(CONCLAVE_STANDARD)
      displayName: 'Generate Compliance Mapping'
    
    - task: PublishBuildArtifacts@1
      inputs:
        pathToPublish: '$(Build.SourcesDirectory)/.code-conclave/reviews'
        artifactName: 'ComplianceReports'
```

#### Create `examples/azure-pipelines-pr.yml` (lightweight PR check)

```yaml
# Code Conclave - PR Validation Pipeline
#
# Lightweight version that runs only critical checks on PRs.
# Blocks merge if BLOCKER findings are present.

trigger: none  # Only runs on PR

pr:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'ubuntu-latest'

jobs:
- job: QuickReview
  displayName: 'PR Security & Quality Check'
  container: ghcr.io/blb3d/conclave:latest
  timeoutInMinutes: 30
  
  steps:
  - checkout: self
  
  # Run only GUARDIAN and SENTINEL (security + quality)
  - pwsh: |
      /conclave/cli/ccl.ps1 `
        -Project $(Build.SourcesDirectory) `
        -Agents guardian,sentinel `
        -OutputFormat junit `
        -CI
    displayName: 'Security & Quality Review'
    continueOnError: true
  
  - task: PublishTestResults@2
    inputs:
      testResultsFormat: 'JUnit'
      testResultsFiles: '**/.code-conclave/reviews/conclave-results.xml'
      testRunTitle: 'PR Review - Security & Quality'
      failTaskOnFailedTests: true
    condition: always()
```

---

## Summary Checklist

Before starting implementation, ensure:

- [ ] PR #8 (documentation) is merged
- [ ] Working on latest main branch
- [ ] Test project available for validation

Implementation order:

1. [ ] **TASK-013**: Create `cli/lib/junit-formatter.ps1`
2. [ ] **TASK-013**: Modify `cli/ccl.ps1` to add `-OutputFormat junit`
3. [ ] **TASK-013**: Test JUnit output validates
4. [ ] **TASK-014**: Add `-CI` parameter and exit codes
5. [ ] **TASK-014**: Test exit codes in simulated CI
6. [ ] **TASK-015**: Create `Dockerfile` and `.dockerignore`
7. [ ] **TASK-015**: Test container builds and runs
8. [ ] **TASK-016**: Create ADO pipeline templates
9. [ ] **TASK-016**: Document in `docs/CONTAINER.md` and `docs/PIPELINE.md`

## Notes for Implementation

- Keep changes backward-compatible (existing `-Format` in report.ps1 should still work)
- JUnit formatter should be a separate file for modularity
- Test with real findings before marking complete
- Container should work without any AI provider configured (for basic parsing)
