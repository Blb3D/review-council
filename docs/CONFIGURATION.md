# Configuration Reference

Complete reference for all Code Conclave configuration options.

---

## Table of Contents

- [Configuration Files](#configuration-files)
- [Configuration Precedence](#configuration-precedence)
- [Project Section](#project-section)
- [AI Section](#ai-section)
- [Agents Section](#agents-section)
- [Standards Section](#standards-section)
- [Output Section](#output-section)
- [CI Section](#ci-section)
- [Full Example](#full-example)
- [Environment Variables](#environment-variables)

---

## Configuration Files

### Locations

| File | Purpose | Scope |
|------|---------|-------|
| `.code-conclave/config.yaml` | Project configuration | This project only |
| `~/.code-conclave/config.yaml` | User defaults | All projects |
| `core/config/defaults.yaml` | Tool defaults | Fallback |

### Creating Configuration

```powershell
# Initialize project with default config
ccl -Init -Project .
```

This creates `.code-conclave/config.yaml` with sensible defaults.

---

## Configuration Precedence

From highest to lowest priority:

1. **CLI parameters** (e.g., `-Timeout 60`)
2. **Environment variables** (e.g., `$env:ANTHROPIC_API_KEY`)
3. **Project config** (`.code-conclave/config.yaml`)
4. **User config** (`~/.code-conclave/config.yaml`)
5. **Tool defaults**

---

## Project Section

Basic project identification and metadata.

```yaml
project:
  # Project name (auto-detected from folder if not specified)
  name: "my-app"
  
  # Project version (informational)
  version: "1.0.0"
  
  # Description (informational)
  description: "My application"
  
  # Industry classification (helps select default standards)
  # Options: software, manufacturing, medical, aerospace, defense, automotive
  industry: "software"
  
  # Regulatory context (informational, shown in reports)
  regulatory_context:
    - "FDA registered facility"
    - "ITAR controlled"
```

### Industry Presets

| Industry | Default Standards |
|----------|------------------|
| `software` | (none) |
| `manufacturing` | ISO 9001 |
| `medical` | ISO 13485, FDA 21 CFR 11 |
| `aerospace` | AS9100 |
| `defense` | CMMC L2, ITAR |
| `automotive` | IATF 16949 |

---

## AI Section

Configure which AI provider to use and how.

```yaml
ai:
  # Which provider to use
  # Options: anthropic, azure-openai, openai, ollama
  provider: anthropic
  
  # Common settings (apply to all providers)
  timeout_seconds: 300      # Request timeout (default: 300)
  retry_attempts: 3         # Retry failed requests (default: 3)
  retry_delay_seconds: 5    # Wait between retries (default: 5)
  
  # Provider-specific settings (see below)
  anthropic:
    ...
  azure-openai:
    ...
  openai:
    ...
  ollama:
    ...
```

### Anthropic Configuration

```yaml
ai:
  provider: anthropic
  anthropic:
    # Model to use (primary tier)
    # Options: claude-sonnet-4-20250514, claude-opus-4-20250514
    model: claude-sonnet-4-20250514

    # Model for lite-tier agents (optional, falls back to primary if not set)
    lite_model: claude-3-5-haiku-20241022

    # Environment variable containing API key
    api_key_env: ANTHROPIC_API_KEY

    # Maximum tokens in response
    max_tokens: 16000
```

### Azure OpenAI Configuration

```yaml
ai:
  provider: azure-openai
  azure-openai:
    # Your Azure OpenAI resource endpoint
    endpoint: https://your-resource.openai.azure.com/

    # Deployment name (from Azure portal) — used for primary-tier agents
    deployment: gpt-4o

    # Deployment for lite-tier agents (optional, falls back to primary if not set)
    # Requires a separate Azure deployment (e.g., gpt-4o-mini)
    lite_deployment: gpt-4o-mini

    # API version (2024-10-01-preview or later enables cached token reporting)
    api_version: "2024-10-01-preview"

    # Environment variable containing API key
    api_key_env: AZURE_OPENAI_KEY

    # Maximum tokens in response
    max_tokens: 16000
```

### OpenAI Configuration

```yaml
ai:
  provider: openai
  openai:
    # Model to use (primary tier)
    model: gpt-4o

    # Model for lite-tier agents (optional, falls back to primary if not set)
    lite_model: gpt-4o-mini

    # Environment variable containing API key
    api_key_env: OPENAI_API_KEY

    # Maximum tokens in response
    max_tokens: 16000
```

### Ollama Configuration

```yaml
ai:
  provider: ollama
  ollama:
    # Ollama server endpoint
    endpoint: http://localhost:11434
    
    # Model name (must be pulled first)
    model: llama3.1:70b
    
    # Maximum tokens in response
    max_tokens: 8000
```

---

## Agents Section

Configure agent behavior and thresholds.

```yaml
agents:
  # Global settings
  timeout: 40              # Minutes per agent (default: 40)
  parallel: false          # Run agents in parallel (experimental)

  # Enable/disable specific agents
  enabled:
    - sentinel
    - guardian
    - architect
    - navigator
    - herald
    - operator

  # Or disable specific agents
  disabled:
    - navigator  # Skip UX review

  # Per-agent configuration
  # Each agent supports a "tier" field: "primary" or "lite"
  # Primary agents use the full model; lite agents use a cheaper model
  # See Cost Optimization Guide for details
  sentinel:
    enabled: true
    tier: primary                 # Default: primary
    coverage_target: 80           # Minimum test coverage %
    complexity_threshold: 15      # Max cyclomatic complexity

  guardian:
    enabled: true
    tier: primary                 # Default: primary
    scan_dependencies: true       # Check for vulnerable deps
    check_secrets: true           # Scan for hardcoded secrets
    severity_threshold: high      # Minimum severity to report

  architect:
    enabled: true
    tier: primary                 # Default: primary
    max_file_size: 500            # Flag files over N lines
    check_circular_deps: true     # Detect circular dependencies

  navigator:
    enabled: true
    tier: lite                    # Default: lite
    accessibility_level: "AA"     # WCAG level: A, AA, AAA
    check_mobile: true            # Check mobile responsiveness

  herald:
    enabled: true
    tier: lite                    # Default: lite
    required_docs:
      - "README.md"
      - "CHANGELOG.md"
    api_docs_required: true       # Require API documentation

  operator:
    enabled: true
    tier: lite                    # Default: lite
    require_health_check: true    # Require /health endpoint
    require_logging: true         # Require structured logging
    require_metrics: true         # Require metrics endpoint
```

### Agent Selection Priority

1. CLI `-Agent` or `-Agents` parameter (highest)
2. `agents.enabled` list in config
3. `agents.disabled` list (removes from enabled)
4. All agents (default)

---

## Standards Section

Configure compliance standards to apply.

```yaml
standards:
  # TIER 1: Required (always applied, cannot skip)
  required:
    - iso-9001-2015
    
  # TIER 2: Default (applied unless skipped with -SkipStandards)
  default:
    - fda-21-cfr-11
    - iso-13485-2016
    
  # TIER 3: Available (add with -AddStandards)
  available:
    - cmmc-l2
    - itar
    - as9100-rev-d
    
  # Pre-defined bundles
  profiles:
    defense-medical:
      description: "Medical devices for DoD"
      standards:
        - cmmc-l2
        - itar
        - fda-21-cfr-11
        
    internal-tools:
      description: "Internal projects"
      standards: []  # Only required standards
```

### Available Standards

| ID | Name | Category |
|----|------|----------|
| `iso-9001-2015` | ISO 9001:2015 | Quality Management |
| `iso-13485-2016` | ISO 13485:2016 | Medical Device QMS |
| `iso-14971-2019` | ISO 14971:2019 | Risk Management |
| `fda-21-cfr-11` | FDA 21 CFR Part 11 | Electronic Records |
| `fda-820-qsr` | FDA 820 QSR | Quality System Regulation |
| `cmmc-l1` | CMMC Level 1 | Cybersecurity (Basic) |
| `cmmc-l2` | CMMC Level 2 | Cybersecurity (Advanced) |
| `nist-800-171` | NIST 800-171 | CUI Protection |
| `itar` | ITAR | Export Control |
| `as9100-rev-d` | AS9100 Rev D | Aerospace QMS |
| `iatf-16949-2016` | IATF 16949:2016 | Automotive QMS |

### CLI Overrides

```powershell
# Add standards for this run
ccl -Project . -AddStandards cmmc-l2,itar

# Skip default standards for this run
ccl -Project . -SkipStandards fda-21-cfr-11

# Use a profile
ccl -Project . -Profile defense-medical
```

---

## Output Section

Configure report generation.

```yaml
output:
  # Output format: markdown, json, junit
  format: markdown
  
  # Where to save reports (relative to project)
  reports_dir: ".code-conclave/reviews"
  
  # What to include in findings
  include_evidence: true        # Code snippets
  include_remediation: true     # Fix suggestions
  include_line_numbers: true    # Exact locations
  
  # Synthesis report options
  synthesis:
    enabled: true               # Generate final summary
    include_summary_table: true # Severity matrix
    include_agent_links: true   # Links to agent reports
    include_standards_mapping: true  # Compliance mapping
```

### Output Formats

| Format | File | Use Case |
|--------|------|----------|
| `markdown` | `*.md` | Human reading, PR comments |
| `json` | `*.json` | API integration, tooling |
| `junit` | `*.xml` | CI/CD test reporting |

---

## CI Section

Configure behavior in CI/CD pipelines.

```yaml
ci:
  # Exit codes
  exit_codes:
    ship: 0           # All clear
    conditional: 2    # Warnings present
    hold: 1           # Blockers found
    
  # When to fail the build
  fail_on: blocker    # Options: blocker, high, medium, low
  
  # Branch-specific behavior
  branches:
    main:
      fail_on: high           # Stricter on main
      required_standards: true
    develop:
      fail_on: blocker        # More lenient
      required_standards: true
    "feature/*":
      fail_on: blocker
      required_standards: false  # Faster iteration
    "hotfix/*":
      fail_on: blocker
      skip_agents:
        - navigator
        - herald
```

### CI Mode

Enable CI mode with `-CI` flag:

```powershell
ccl -Project . -CI -OutputFormat junit
```

This enables:
- Exit codes based on findings
- JUnit output for test reporting
- Reduced console output
- No interactive prompts
- Automatic diff-scoped scanning (when base branch is detected)

### Diff-Scoped Scanning

Use `-BaseBranch` to explicitly set the base branch for diff-scoped scanning:

```powershell
# Explicit base branch
ccl -Project . -BaseBranch main -CI

# Auto-detect from CI environment (default)
ccl -Project . -CI
```

In CI/CD pipelines, the base branch is auto-detected from `GITHUB_BASE_REF` (GitHub Actions) or `SYSTEM_PULLREQUEST_TARGETBRANCH` (Azure DevOps). If no base branch is available, Code Conclave falls back to a full scan.

See [Cost Optimization Guide](COST-OPTIMIZATION.md) for details on cost savings.

---

## Full Example

Complete configuration file with all options:

```yaml
# .code-conclave/config.yaml
# Complete Code Conclave Configuration

project:
  name: "my-project"
  version: "1.0.0"
  description: "My Application"
  industry: "manufacturing"
  regulatory_context:
    - "FDA registered facility"
    - "DoD contractor"

ai:
  provider: anthropic
  timeout_seconds: 300
  retry_attempts: 3
  retry_delay_seconds: 5

  anthropic:
    model: claude-sonnet-4-20250514
    lite_model: claude-3-5-haiku-20241022
    api_key_env: ANTHROPIC_API_KEY
    max_tokens: 16000

  azure-openai:
    endpoint: https://mycompany.openai.azure.com/
    deployment: gpt-4o
    lite_deployment: gpt-4o-mini
    api_version: "2024-10-01-preview"
    api_key_env: AZURE_OPENAI_KEY
    max_tokens: 16000

agents:
  timeout: 40
  parallel: false

  sentinel:
    enabled: true
    tier: primary
    coverage_target: 80
    complexity_threshold: 15

  guardian:
    enabled: true
    tier: primary
    scan_dependencies: true
    check_secrets: true

  architect:
    enabled: true
    tier: primary
    max_file_size: 500

  navigator:
    enabled: true
    tier: lite
    accessibility_level: "AA"

  herald:
    enabled: true
    tier: lite
    required_docs:
      - "README.md"
      - "CHANGELOG.md"

  operator:
    enabled: true
    tier: lite
    require_health_check: true

standards:
  required:
    - iso-9001-2015
    
  default:
    - fda-21-cfr-11
    - iso-13485-2016
    
  available:
    - cmmc-l2
    - itar
    - as9100-rev-d
    
  profiles:
    defense-medical:
      description: "Medical devices for DoD"
      standards:
        - cmmc-l2
        - itar

output:
  format: markdown
  reports_dir: ".code-conclave/reviews"
  include_evidence: true
  include_remediation: true
  
  synthesis:
    enabled: true
    include_summary_table: true

ci:
  fail_on: blocker
  
  branches:
    main:
      fail_on: high
    develop:
      fail_on: blocker
```

---

## Environment Variables

| Variable | Purpose | Required For |
|----------|---------|--------------|
| `ANTHROPIC_API_KEY` | Anthropic API key | anthropic provider |
| `AZURE_OPENAI_KEY` | Azure OpenAI API key | azure-openai provider |
| `OPENAI_API_KEY` | OpenAI API key | openai provider |
| `CODE_CONCLAVE_CONFIG` | Override config path | Custom locations |

### Setting Environment Variables

**Windows (PowerShell):**
```powershell
# Session only
$env:ANTHROPIC_API_KEY = "sk-ant-..."

# Permanent
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-...", "User")
```

**macOS/Linux:**
```bash
# Session only
export ANTHROPIC_API_KEY="sk-ant-..."

# Permanent (add to ~/.bashrc)
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
```

---

## Validation

Validate your configuration:

```powershell
# Check config without running
ccl -Project . -DryRun -Verbose
```

Common issues:
- YAML syntax errors (check indentation)
- Missing required fields
- Invalid provider name
- API key not set

---

*Last updated: 2026-02-05*
