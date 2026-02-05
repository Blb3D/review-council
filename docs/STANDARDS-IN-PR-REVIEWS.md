# Standards Selection in PR Reviews

How compliance standards integrate with pull request reviews in CI/CD pipelines.

---

## Table of Contents

- [Overview](#overview)
- [How Standards Apply to PRs](#how-standards-apply-to-prs)
- [Configuration](#configuration)
- [Standard Selection Methods](#standard-selection-methods)
- [What Happens During a PR Review](#what-happens-during-a-pr-review)
- [Understanding the Output](#understanding-the-output)
- [Examples](#examples)

---

## Overview

Code Conclave reviews code through AI-powered agents that find security vulnerabilities, quality issues, architecture problems, and more. **Compliance standards** add an additional layer: they map those findings to regulatory controls (CMMC, ITAR, FDA, ISO, etc.), giving teams visibility into which regulations are impacted by code issues.

### Without Standards

```
PR opened --> AI agents review code --> Findings report
                                        "GUARDIAN-001: Hardcoded API key [BLOCKER]"
```

### With Standards

```
PR opened --> AI agents review code --> Findings report
                                        "GUARDIAN-001: Hardcoded API key [BLOCKER]"
                                              |
                                              v
                                        Compliance mapping
                                        "Maps to CMMC AC.L2-3.1.1 (Access Control)"
                                        "Maps to ITAR 120.17 (Data Protection)"
```

Standards do not change what the agents find. They add context about which regulations are affected by those findings.

---

## How Standards Apply to PRs

### The Three-Tier System

Standards are organized into tiers in your project's `.code-conclave/config.yaml`:

```yaml
standards:
  required:        # Tier 1: Always applied, cannot be skipped
    - iso-9001-2015

  default:         # Tier 2: Applied unless explicitly skipped
    - cmmc-l2

  available:       # Tier 3: Only applied when explicitly requested
    - itar
    - fda-21-cfr-11
    - as9100-rev-d
```

When a PR triggers a Code Conclave review:

| Tier | Behavior | Override |
|------|----------|---------|
| **Required** | Always included in every review | Cannot be skipped |
| **Default** | Included unless `-SkipStandards` is used | `-SkipStandards cmmc-l2` |
| **Available** | Not included unless `-AddStandards` is used | `-AddStandards itar` |

### Resolution Order

```
Required standards
  + Default standards (minus any skipped)
  + Explicitly added standards
  = Effective standards for this review
```

---

## Configuration

### Project-Level Configuration

Define standards in your project's `.code-conclave/config.yaml`:

```yaml
# For a defense contractor building medical devices
standards:
  required:
    - cmmc-l2           # Always check CMMC (company mandate)
  default:
    - iso-9001-2015     # QMS applied by default
  available:
    - itar              # Can be added per-review
    - fda-21-cfr-11     # Can be added per-review
    - fda-820-qsr       # Can be added per-review
```

This means every PR automatically checks against CMMC L2 and ISO 9001. Teams can add ITAR or FDA standards when the PR touches export-controlled or medical device code.

### Pipeline-Level Configuration

Override or add standards in your CI pipeline:

**GitHub Actions:**

```yaml
- name: Run Code Conclave Review
  shell: pwsh
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    .\cli\ccl.ps1 `
      -Project ${{ github.workspace }} `
      -AddStandards itar `
      -OutputFormat junit `
      -CI
```

**Azure DevOps:**

```yaml
- task: PowerShell@2
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
  inputs:
    targetType: inline
    pwsh: true
    script: |
      & "$(conclaveDir)/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -AddStandards cmmc-l2,itar `
        -OutputFormat junit `
        -CI
```

### Using Profiles

Profiles bundle multiple standards for common scenarios:

```yaml
# config.yaml
standards:
  profiles:
    defense-medical:
      description: "Medical devices for DoD"
      standards:
        - cmmc-l2
        - itar
        - fda-21-cfr-11
        - iso-13485-2016

    internal-tools:
      description: "Internal applications"
      standards: []    # Only required standards apply
```

Use in pipeline:

```powershell
ccl -Project . -Profile defense-medical -OutputFormat junit -CI
```

---

## Standard Selection Methods

### Method 1: Static in Config (Most Common)

Best for: Teams that always need the same standards.

Set standards in `config.yaml` and forget about them. Every PR review includes them automatically.

```yaml
standards:
  required:
    - cmmc-l2
    - itar
```

Pipeline needs no standard flags:

```powershell
ccl -Project . -OutputFormat junit -CI
# cmmc-l2 and itar are always included
```

### Method 2: Pipeline Parameters (Manual Selection)

Best for: Teams that review different project types with different standards.

**Azure DevOps** supports parameter dropdowns:

```yaml
parameters:
  - name: complianceStandard
    displayName: 'Compliance Standard'
    type: string
    default: 'none'
    values:
      - none
      - cmmc-l2
      - itar
      - fda-21-cfr-11
      - as9100-rev-d

steps:
- task: PowerShell@2
  inputs:
    script: |
      $params = @{
        Project      = "$(Build.SourcesDirectory)"
        OutputFormat = "junit"
        CI           = $true
      }
      if ("${{ parameters.complianceStandard }}" -ne "none") {
        $params.AddStandards = @("${{ parameters.complianceStandard }}")
      }
      & "$conclaveDir/cli/ccl.ps1" @params
```

**GitHub Actions** supports workflow_dispatch inputs:

```yaml
on:
  workflow_dispatch:
    inputs:
      standard:
        description: 'Compliance standard'
        required: false
```

### Method 3: Per-Branch Configuration

Best for: Projects where different branches serve different regulatory environments.

Create different configs per environment:

```
.code-conclave/
  config.yaml              # Default: iso-9001-2015
  config.defense.yaml      # Defense: cmmc-l2, itar
  config.medical.yaml      # Medical: fda-21-cfr-11, fda-820-qsr
```

Pipeline selects based on branch:

```yaml
- task: PowerShell@2
  inputs:
    script: |
      $standard = switch -Wildcard ("$(Build.SourceBranchName)") {
        "release/defense-*" { "cmmc-l2,itar" }
        "release/medical-*" { "fda-21-cfr-11" }
        default { "" }
      }

      $params = @{
        Project      = "$(Build.SourcesDirectory)"
        OutputFormat = "junit"
        CI           = $true
      }
      if ($standard) { $params.AddStandards = $standard.Split(",") }

      & "$conclaveDir/cli/ccl.ps1" @params
```

---

## What Happens During a PR Review

### Step-by-Step Flow

```
1. Developer opens PR to main
      |
2. Pipeline triggers automatically
      |
3. Code Conclave initializes
   - Loads project config.yaml
   - Resolves effective standards (required + default + added)
   - Connects to AI provider
      |
4. Agents review the code
   - Each agent examines source files
   - Produces findings with severity (BLOCKER/HIGH/MEDIUM/LOW)
   - Findings include tags (security, testing, architecture, etc.)
      |
5. Findings are collected
   - JUnit XML generated (each finding = test case)
   - BLOCKER/HIGH = failed tests, MEDIUM/LOW = passed tests
      |
6. Compliance mapping runs (if standards selected)
   - Finding tags matched to standard controls
   - Compliance report generated showing which controls are impacted
      |
7. Results published
   - JUnit results appear in PR as pass/fail checks
   - Full reports uploaded as pipeline artifacts
      |
8. Branch policy evaluates
   - Exit code 0 (SHIP) = merge allowed
   - Exit code 1 (HOLD) = merge BLOCKED
   - Exit code 2 (CONDITIONAL) = merge allowed with warnings
```

### What Blocks a Merge

| Severity | JUnit Status | Blocks Merge? |
|----------|-------------|---------------|
| BLOCKER | Failed test | **Yes** (exit code 1) |
| HIGH | Failed test | **Yes** (exit code 1) |
| MEDIUM | Passed test | No |
| LOW | Passed test | No |

A single BLOCKER or HIGH finding causes exit code 1, which fails the build and blocks the PR from merging (when branch policies are configured as required).

---

## Understanding the Output

### JUnit Test Results (in ADO / GitHub)

Each agent becomes a test suite. Each finding becomes a test case:

```
Test Suites:
  GUARDIAN (5 tests, 2 failures)
    GUARDIAN-001: Hardcoded API Key [BLOCKER]        FAILED
    GUARDIAN-002: Missing CSRF Protection [HIGH]     FAILED
    GUARDIAN-003: Weak Password Policy [MEDIUM]      PASSED
    GUARDIAN-004: Verbose Error Messages [MEDIUM]    PASSED
    GUARDIAN-005: Outdated Dependencies [LOW]        PASSED

  SENTINEL (4 tests, 1 failure)
    SENTINEL-001: No Unit Tests for AuthService [HIGH]   FAILED
    SENTINEL-002: Low Branch Coverage [MEDIUM]           PASSED
    SENTINEL-003: Missing Error Handling [MEDIUM]        PASSED
    SENTINEL-004: Inconsistent Naming [LOW]              PASSED
```

### Compliance Mapping Report (in Artifacts)

When standards are applied, the review artifacts include a compliance mapping:

```markdown
## CMMC Level 2 Compliance Mapping

### AC - Access Control
| Control | Title | Findings |
|---------|-------|----------|
| AC.L2-3.1.1 | Authorized Access Control | GUARDIAN-001 |
| AC.L2-3.1.2 | Transaction Control | - |
| AC.L2-3.1.5 | Least Privilege | GUARDIAN-002 |

### SC - System & Communications Protection
| Control | Title | Findings |
|---------|-------|----------|
| SC.L2-3.13.8 | CUI Encryption | GUARDIAN-001 |

### Summary
- Controls assessed: 110
- Controls with findings: 12
- Controls clear: 98
```

This report provides audit-ready evidence showing which compliance controls were evaluated during code review and which have open issues.

---

## Examples

### Example 1: Defense Contractor (CMMC + ITAR)

**config.yaml:**
```yaml
standards:
  required:
    - cmmc-l2
    - itar
```

**Pipeline:** No standard flags needed. Every PR checks CMMC and ITAR.

**Result:** If a finding maps to an ITAR control, it appears in both the findings report and the ITAR compliance mapping. The team knows immediately that a code issue has export control implications.

### Example 2: Medical Device (FDA + ISO)

**config.yaml:**
```yaml
standards:
  required:
    - fda-21-cfr-11
  default:
    - iso-13485-2016
    - fda-820-qsr
  available:
    - iso-14971-2019
```

**Pipeline:** Add risk management standard for safety-critical PRs:
```powershell
ccl -Project . -AddStandards iso-14971-2019 -CI
```

### Example 3: General Software (No Standards)

**config.yaml:**
```yaml
standards:
  required: []
  default: []
```

Code Conclave still runs all agents and finds issues, but no compliance mapping is generated. The review is purely about code quality and security.

### Example 4: Multiple Environments from One Repo

**config.yaml:**
```yaml
standards:
  required:
    - iso-9001-2015
  available:
    - cmmc-l2
    - itar
    - fda-21-cfr-11
  profiles:
    defense:
      standards: [cmmc-l2, itar]
    medical:
      standards: [fda-21-cfr-11, fda-820-qsr]
```

**Pipeline uses profiles:**
```powershell
# For defense branches
ccl -Project . -Profile defense -CI

# For medical branches
ccl -Project . -Profile medical -CI
```

---

## Available Standards

| ID | Name | Controls | Category |
|----|------|----------|----------|
| `iso-9001-2015` | ISO 9001:2015 | ~50 | Quality Management |
| `cmmc-l2` | CMMC Level 2 | 110 | Cybersecurity |
| `itar` | ITAR | 45 | Export Control |
| `fda-21-cfr-11` | 21 CFR Part 11 | ~30 | Medical/Pharma |
| `fda-820-qsr` | FDA 820 QSR | ~40 | Medical Devices |
| `iso-13485-2016` | ISO 13485:2016 | ~50 | Medical Device QMS |
| `iso-14971-2019` | ISO 14971:2019 | ~30 | Risk Management |
| `as9100-rev-d` | AS9100 Rev D | ~60 | Aerospace |
| `iatf-16949-2016` | IATF 16949:2016 | ~50 | Automotive |

Custom standards can be created by adding YAML definition files to `core/standards/`. See [STANDARDS.md](STANDARDS.md) for the custom standard schema.

---

*Last updated: 2026-02-04*
