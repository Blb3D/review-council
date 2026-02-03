# CLI Reference

Complete command-line reference for Code Conclave.

---

## Main Entry Point

```powershell
.\cli\ccl.ps1 [options]
```

### Synopsis

```powershell
.\cli\ccl.ps1 -Project <path> [-Agent <name>] [-Agents <list>] [-Standard <id>]
              [-StartFrom <agent>] [-DryRun] [-OutputDir <path>]

.\cli\ccl.ps1 -Map <path> -Standard <id>

.\cli\ccl.ps1 -Standards <command> [-Standard <id>]

.\cli\ccl.ps1 -Report <path> [-Template <name>] [-Format <type>] [-Standard <id>]

.\cli\ccl.ps1 -Help
```

---

## Review Commands

### Full Review

Run all 6 agents on a project:

```powershell
.\cli\ccl.ps1 -Project "C:\path\to\project"
```

**Output**: Creates `.code-conclave/reviews/` with findings from each agent.

### Single Agent

Run a specific agent:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -Agent sentinel
.\cli\ccl.ps1 -Project "C:\myproject" -Agent guardian
.\cli\ccl.ps1 -Project "C:\myproject" -Agent architect
.\cli\ccl.ps1 -Project "C:\myproject" -Agent navigator
.\cli\ccl.ps1 -Project "C:\myproject" -Agent herald
.\cli\ccl.ps1 -Project "C:\myproject" -Agent operator
```

### Multiple Agents

Run a subset of agents:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -Agents sentinel,guardian,architect
```

### Resume From Agent

Continue from a specific agent (useful if interrupted):

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -StartFrom architect
```

This runs architect, navigator, herald, and operator.

### With Compliance Context

Include compliance standard context in agent prompts:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -Standard cmmc-l2
```

### Dry Run

Preview what would be executed without running agents:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -DryRun
```

### Custom Output Directory

Specify output location:

```powershell
.\cli\ccl.ps1 -Project "C:\myproject" -OutputDir "C:\reviews\myproject"
```

---

## Compliance Commands

### List Standards

Show all available compliance standards:

```powershell
.\cli\ccl.ps1 -Standards list
```

**Output**:
```
Available Compliance Standards
===============================

[cybersecurity]
  cmmc-l2 - CMMC Level 2

[medical]
  fda-820-qsr - FDA 21 CFR 820 QSR
  fda-21-cfr-11 - FDA 21 CFR Part 11
```

### Standard Info

Show details about a specific standard:

```powershell
.\cli\ccl.ps1 -Standards info -Standard cmmc-l2
```

**Output**:
```
CMMC Level 2
============

ID:      cmmc-l2
Domain:  cybersecurity
Version: 2.0

Controls:
  Total: 110
  Critical: 15

Agent Coverage:
  GUARDIAN    45 controls
  SENTINEL    12 controls
  ...
```

### Map Findings

Map existing findings to a compliance standard:

```powershell
.\cli\ccl.ps1 -Map "C:\myproject\.code-conclave" -Standard cmmc-l2
```

**Output**: Creates `COMPLIANCE-MAPPING-CMMC-L2.md` in the reviews directory.

---

## Report Commands

Reports are generated using the report subcommand:

```powershell
.\cli\commands\report.ps1 -ProjectPath <path> [options]
```

### Templates

| Template | Description |
|----------|-------------|
| `release-readiness` | Default. Overview with verdict and agent summary |
| `executive-summary` | One-page summary for stakeholders |
| `full-report` | Comprehensive report with all details |
| `gap-analysis` | Compliance gap analysis (requires `-Standard`) |
| `traceability-matrix` | Control-to-finding mapping (requires `-Standard`) |

### Release Readiness (Default)

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject"
```

### Executive Summary

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template executive-summary
```

### Full Report

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template full-report
```

### Gap Analysis

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template gap-analysis -Standard cmmc-l2
```

### Traceability Matrix

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Template traceability-matrix -Standard cmmc-l2
```

### Output Formats

| Format | Description |
|--------|-------------|
| `markdown` | Default. Markdown format |
| `json` | JSON for programmatic processing |
| `csv` | CSV for spreadsheet analysis |

```powershell
# JSON export
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Format json

# CSV export
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -Format csv
```

### Custom Output Path

```powershell
.\cli\commands\report.ps1 -ProjectPath "C:\myproject" -OutputPath "C:\reports\myreport.md"
```

---

## Parameters Reference

### Main CLI (ccl.ps1)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Project` | String | Path to project to review |
| `-Agent` | String | Single agent to run |
| `-Agents` | String | Comma-separated list of agents |
| `-StartFrom` | String | Resume from specific agent |
| `-Standard` | String | Compliance standard ID |
| `-Standards` | String | Standards subcommand (list, info) |
| `-Map` | String | Path to findings for compliance mapping |
| `-DryRun` | Switch | Preview without executing |
| `-OutputDir` | String | Custom output directory |
| `-Help` | Switch | Show help |

### Report Command

| Parameter | Type | Description |
|-----------|------|-------------|
| `-ProjectPath` | String | Path to project or .code-conclave directory |
| `-Template` | String | Report template name |
| `-Format` | String | Output format (markdown, json, csv) |
| `-Standard` | String | Compliance standard (for gap/traceability) |
| `-OutputPath` | String | Custom output file path |

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CCL_OUTPUT_DIR` | Default output directory | `.code-conclave` in project |
| `CCL_STANDARD` | Default compliance standard | None |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Project not found |
| 4 | Agent execution failed |

---

## Examples

### Basic Workflow

```powershell
# 1. Run full review
.\cli\ccl.ps1 -Project "C:\myapp"

# 2. Generate executive summary
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Template executive-summary

# 3. Map to compliance standard
.\cli\ccl.ps1 -Map "C:\myapp\.code-conclave" -Standard cmmc-l2

# 4. Generate gap analysis
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Template gap-analysis -Standard cmmc-l2
```

### Quick Security Check

```powershell
# Run only GUARDIAN (security)
.\cli\ccl.ps1 -Project "C:\myapp" -Agent guardian
```

### Pre-Release Review

```powershell
# Full review with CMMC compliance
.\cli\ccl.ps1 -Project "C:\myapp" -Standard cmmc-l2

# Generate all reports
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Template executive-summary
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Template full-report
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Template gap-analysis -Standard cmmc-l2
```

### CI/CD Integration

```powershell
# Run review and check for blockers
$result = .\cli\ccl.ps1 -Project "." 2>&1
$blockers = Select-String -Path ".\.code-conclave\reviews\*.md" -Pattern "\[BLOCKER\]"

if ($blockers) {
    Write-Error "Blockers found - failing build"
    exit 1
}
```

### Export for External Tools

```powershell
# Export findings as JSON
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Format json -OutputPath "findings.json"

# Export as CSV for spreadsheet
.\cli\commands\report.ps1 -ProjectPath "C:\myapp" -Format csv -OutputPath "findings.csv"
```

---

## Troubleshooting

### "Claude Code not found"

Ensure Claude Code CLI is installed and in PATH:

```powershell
claude --version
```

### "Reviews directory not found"

The `-ProjectPath` for reports should point to either:
- The project root (contains `.code-conclave/`)
- The `.code-conclave` directory directly
- The `reviews` directory directly

### "Standard not found"

List available standards:

```powershell
.\cli\ccl.ps1 -Standards list
```

### Partial Review

If a review is interrupted, resume from where you left off:

```powershell
.\cli\ccl.ps1 -Project "C:\myapp" -StartFrom architect
```

---

*Code Conclave v2.0*
