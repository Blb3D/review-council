<#
.SYNOPSIS
    Pester tests for findings-parser.ps1

.DESCRIPTION
    Tests for markdown-to-JSON parsing, JSON export, archive, and cleanup functions.
#>

# Load the module under test
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Join-Path (Join-Path $here "..") "lib") "findings-parser.ps1")

# Sample markdown that mimics real AI agent output
$script:SampleMarkdown = @"
# GUARDIAN Security Review

## Summary
This review identified several security concerns in the codebase.

### GUARDIAN-001: Hardcoded API Key [BLOCKER]

**Location:** `src/config.js:42`
**Effort:** S

**Issue:**
API key is hardcoded in source code, exposing credentials in version control.

**Evidence:**
``````javascript
const API_KEY = "sk-proj-abc123";
``````

**Recommendation:**
Move to environment variable or secrets manager. Use process.env.API_KEY.

---

### GUARDIAN-002: Missing HTTPS Enforcement [HIGH]

**Location:** `src/server.js:15`
**Effort:** M

**Issue:**
Server does not redirect HTTP to HTTPS, allowing unencrypted traffic.

**Recommendation:**
Add HTTPS redirect middleware before other routes.

---

### GUARDIAN-003: Verbose Error Messages [MEDIUM]

**Location:** `src/api/errors.js`
**Effort:** S

**Issue:**
Error responses include stack traces in production mode.

---

### GUARDIAN-004: Console Logging [LOW]

**Location:** `src/utils/logger.js:88`
**Effort:** S

**Issue:**
Console.log used for debug output instead of structured logging.
"@

$script:SampleWithCodeBlock = @"
# GUARDIAN Security Review

Here is an example of the output format:

``````markdown
### GUARDIAN-999: Example Finding [BLOCKER]
This should NOT be parsed as a real finding.
``````

### GUARDIAN-001: Real Finding [HIGH]

**Location:** `src/app.js:10`
**Effort:** S

**Issue:**
This is a real finding that should be parsed.
"@

Describe "ConvertFrom-FindingsMarkdown" {

    Context "Basic Parsing" {
        It "parses findings from markdown" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian" `
                -AgentName "GUARDIAN" `
                -AgentRole "Security" `
                -ProjectName "test-project" `
                -ProjectPath "C:\test" `
                -RunTimestamp "2026-02-11T14:30:00"

            $result.findings.Count | Should Be 4
        }

        It "extracts correct finding IDs" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].id | Should Be "GUARDIAN-001"
            $result.findings[1].id | Should Be "GUARDIAN-002"
            $result.findings[2].id | Should Be "GUARDIAN-003"
            $result.findings[3].id | Should Be "GUARDIAN-004"
        }

        It "extracts correct severities" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].severity | Should Be "BLOCKER"
            $result.findings[1].severity | Should Be "HIGH"
            $result.findings[2].severity | Should Be "MEDIUM"
            $result.findings[3].severity | Should Be "LOW"
        }

        It "extracts finding titles" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].title | Should Be "Hardcoded API Key"
            $result.findings[1].title | Should Be "Missing HTTPS Enforcement"
        }
    }

    Context "Field Extraction" {
        It "parses file path and line number from Location" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].file | Should Be "src/config.js"
            $result.findings[0].line | Should Be 42
        }

        It "parses file path without line number" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[2].file | Should Be "src/api/errors.js"
        }

        It "extracts effort level" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].effort | Should Be "S"
            $result.findings[1].effort | Should Be "M"
        }

        It "extracts issue text" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].issue | Should Not BeNullOrEmpty
            ($result.findings[0].issue.Contains("hardcoded")) | Should Be $true
        }

        It "extracts recommendation text" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.findings[0].recommendation | Should Not BeNullOrEmpty
            ($result.findings[0].recommendation.Contains("environment variable")) | Should Be $true
        }
    }

    Context "Summary Calculation" {
        It "calculates correct severity counts" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.summary.blockers | Should Be 1
            $result.summary.high | Should Be 1
            $result.summary.medium | Should Be 1
            $result.summary.low | Should Be 1
            $result.summary.total | Should Be 4
        }

        It "handles zero findings" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content "# Review`nNo issues found." `
                -AgentKey "guardian"

            $result.summary.total | Should Be 0
            $result.findings.Count | Should Be 0
        }
    }

    Context "Metadata" {
        It "sets agent info correctly" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian" `
                -AgentName "GUARDIAN" `
                -AgentRole "Security" `
                -Tier "primary"

            $result.agent.id | Should Be "guardian"
            $result.agent.name | Should Be "GUARDIAN"
            $result.agent.role | Should Be "Security"
            $result.agent.tier | Should Be "primary"
        }

        It "sets run info correctly" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian" `
                -ProjectName "filaops" `
                -ProjectPath "C:\repos\filaops" `
                -RunTimestamp "2026-02-11T14:30:00" `
                -DryRun

            $result.run.project | Should Be "filaops"
            $result.run.projectPath | Should Be "C:\repos\filaops"
            $result.run.timestamp | Should Be "2026-02-11T14:30:00"
            $result.run.dryRun | Should Be $true
        }

        It "defaults agent name from key" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "sentinel"

            $result.agent.name | Should Be "SENTINEL"
        }

        It "includes version field" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.version | Should Be "1.0.0"
        }

        It "includes token data when provided" {
            $tokens = @{ Input = 14200; Output = 2800; CacheRead = 11500; CacheWrite = 0 }
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian" `
                -TokensUsed $tokens

            $result.tokens.input | Should Be 14200
            $result.tokens.output | Should Be 2800
        }
    }

    Context "Code Block Exclusion" {
        It "skips findings inside code blocks" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleWithCodeBlock `
                -AgentKey "guardian"

            $result.findings.Count | Should Be 1
            $result.findings[0].id | Should Be "GUARDIAN-001"
        }
    }

    Context "Raw Markdown" {
        It "preserves raw markdown in output" {
            $result = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $result.rawMarkdown | Should Be $script:SampleMarkdown
        }
    }
}

Describe "Export-FindingsJson" {
    $testDir = Join-Path $env:TEMP "findings-parser-test"

    # Setup
    if (-not (Test-Path $testDir)) {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    Context "File Output" {
        It "writes JSON file to disk" {
            $findings = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $outputPath = Join-Path $testDir "guardian-findings.json"
            $result = Export-FindingsJson -Findings $findings -OutputPath $outputPath

            Test-Path $outputPath | Should Be $true
            $result | Should Be $outputPath
        }

        It "produces valid JSON" {
            $findings = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $outputPath = Join-Path $testDir "valid-json-test.json"
            Export-FindingsJson -Findings $findings -OutputPath $outputPath

            $content = Get-Content $outputPath -Raw
            $parsed = ConvertFrom-Json $content
            $parsed | Should Not BeNullOrEmpty
            $parsed.version | Should Be "1.0.0"
        }

        It "creates parent directories if needed" {
            $findings = ConvertFrom-FindingsMarkdown `
                -Content $script:SampleMarkdown `
                -AgentKey "guardian"

            $nestedPath = Join-Path (Join-Path $testDir "nested") "deep-test.json"
            Export-FindingsJson -Findings $findings -OutputPath $nestedPath

            Test-Path $nestedPath | Should Be $true
        }
    }

    # Cleanup
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Export-RunArchive" {
    $testDir = Join-Path $env:TEMP "archive-test"
    $reviewsDir = Join-Path $testDir "reviews"

    # Setup
    if (-not (Test-Path $reviewsDir)) {
        New-Item -ItemType Directory -Path $reviewsDir -Force | Out-Null
    }

    Context "Archive Creation" {
        It "creates archive directory and file" {
            $agentFindings = @{
                guardian = ConvertFrom-FindingsMarkdown `
                    -Content $script:SampleMarkdown `
                    -AgentKey "guardian" `
                    -AgentName "GUARDIAN" `
                    -AgentRole "Security"
            }
            $metadata = @{
                Timestamp = [datetime]"2026-02-11T14:30:00"
                Project = "test-project"
                ProjectPath = "C:\test"
                Duration = 42.5
                DryRun = $true
                Verdict = "HOLD"
                ExitCode = 1
                Provider = "anthropic"
                AgentsRequested = @("guardian")
            }

            $archivePath = Export-RunArchive `
                -ReviewsDir $reviewsDir `
                -AgentFindings $agentFindings `
                -RunMetadata $metadata

            Test-Path $archivePath | Should Be $true
            ($archivePath.Contains("archive")) | Should Be $true
        }

        It "produces valid JSON archive" {
            $agentFindings = @{
                guardian = ConvertFrom-FindingsMarkdown `
                    -Content $script:SampleMarkdown `
                    -AgentKey "guardian"
            }
            $metadata = @{
                Timestamp = [datetime]"2026-02-11T15:00:00"
                Project = "test"
                Verdict = "SHIP"
                ExitCode = 0
            }

            $archivePath = Export-RunArchive `
                -ReviewsDir $reviewsDir `
                -AgentFindings $agentFindings `
                -RunMetadata $metadata

            $content = Get-Content $archivePath -Raw
            $parsed = ConvertFrom-Json $content
            $parsed | Should Not BeNullOrEmpty
            $parsed.version | Should Be "1.0.0"
            $parsed.verdict | Should Be "SHIP"
        }

        It "aggregates summary across agents" {
            $agentFindings = @{
                guardian = ConvertFrom-FindingsMarkdown `
                    -Content $script:SampleMarkdown `
                    -AgentKey "guardian"
                sentinel = ConvertFrom-FindingsMarkdown `
                    -Content ("### SENTINEL-001: Test [HIGH]" + "`n" + "**Location:** test.js") `
                    -AgentKey "sentinel"
            }
            $metadata = @{
                Timestamp = [datetime]"2026-02-11T15:30:00"
                Project = "test"
                Verdict = "HOLD"
                ExitCode = 1
            }

            $archivePath = Export-RunArchive `
                -ReviewsDir $reviewsDir `
                -AgentFindings $agentFindings `
                -RunMetadata $metadata

            $parsed = ConvertFrom-Json (Get-Content $archivePath -Raw)
            # guardian: 1 blocker, 1 high, 1 medium, 1 low = 4
            # sentinel: 1 high = 1
            $parsed.summary.total | Should Be 5
            $parsed.summary.blockers | Should Be 1
            ($parsed.summary.high -ge 2) | Should Be $true
        }

        It "includes agents section with findings" {
            $agentFindings = @{
                guardian = ConvertFrom-FindingsMarkdown `
                    -Content $script:SampleMarkdown `
                    -AgentKey "guardian" `
                    -AgentName "GUARDIAN" `
                    -AgentRole "Security"
            }
            $metadata = @{
                Timestamp = [datetime]"2026-02-11T16:00:00"
                Project = "test"
                Verdict = "HOLD"
                ExitCode = 1
            }

            $archivePath = Export-RunArchive `
                -ReviewsDir $reviewsDir `
                -AgentFindings $agentFindings `
                -RunMetadata $metadata

            $parsed = ConvertFrom-Json (Get-Content $archivePath -Raw)
            $parsed.agents.guardian | Should Not BeNullOrEmpty
            $parsed.agents.guardian.name | Should Be "GUARDIAN"
            $parsed.agents.guardian.findings.Count | Should Be 4
        }
    }

    # Cleanup
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Remove-WorkingFindings" {
    $testDir = Join-Path $env:TEMP "cleanup-test"

    Context "File Cleanup" {
        It "removes findings files" {
            # Setup
            if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "test" | Out-File (Join-Path $testDir "guardian-findings.json")
            "test" | Out-File (Join-Path $testDir "guardian-findings.md")
            "test" | Out-File (Join-Path $testDir "sentinel-findings.json")
            "test" | Out-File (Join-Path $testDir "sentinel-findings.md")
            "test" | Out-File (Join-Path $testDir "RELEASE-READINESS-REPORT.md")
            "test" | Out-File (Join-Path $testDir "conclave-results.xml")

            Remove-WorkingFindings -ReviewsDir $testDir

            Test-Path (Join-Path $testDir "guardian-findings.json") | Should Be $false
            Test-Path (Join-Path $testDir "guardian-findings.md") | Should Be $false
            Test-Path (Join-Path $testDir "sentinel-findings.json") | Should Be $false
            Test-Path (Join-Path $testDir "sentinel-findings.md") | Should Be $false
            Test-Path (Join-Path $testDir "RELEASE-READINESS-REPORT.md") | Should Be $false
            Test-Path (Join-Path $testDir "conclave-results.xml") | Should Be $false
        }

        It "does not remove archive directory" {
            # Setup
            if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $archiveDir = Join-Path $testDir "archive"
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            "test" | Out-File (Join-Path $archiveDir "20260211T143000.json")
            "test" | Out-File (Join-Path $testDir "guardian-findings.json")

            Remove-WorkingFindings -ReviewsDir $testDir

            Test-Path $archiveDir | Should Be $true
            Test-Path (Join-Path $archiveDir "20260211T143000.json") | Should Be $true
        }
    }

    # Cleanup
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
