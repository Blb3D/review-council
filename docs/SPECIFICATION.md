# Technical Specification

Complete technical reference for Code Conclave internals, interfaces, and architecture.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [AI Provider Interface](#ai-provider-interface)
- [Agent System](#agent-system)
- [Findings Schema](#findings-schema)
- [Standards Engine](#standards-engine)
- [Configuration System](#configuration-system)
- [CLI Reference](#cli-reference)
- [Exit Codes](#exit-codes)
- [Output Formats](#output-formats)
- [API Reference](#api-reference)

---

## Overview

### System Summary

| Attribute | Value |
|-----------|-------|
| **Name** | Code Conclave |
| **Type** | AI Code Review Orchestrator |
| **Language** | PowerShell 5.1+ |
| **License** | MIT |
| **Version** | 1.x |

### Design Principles

1. **AI-Agnostic** - Works with any AI provider via abstraction layer
2. **Declarative** - Configuration-driven behavior
3. **Portable** - Runs on Windows, macOS, Linux, CI/CD runners
4. **Extensible** - Custom agents, standards, and providers
5. **Standards-Based** - Built-in compliance mapping

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLI Layer                                │
│                        (ccl.ps1)                                 │
├─────────────────────────────────────────────────────────────────┤
│                      Orchestration Layer                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Config     │  │   Agent     │  │  Standards  │              │
│  │  Loader     │  │  Scheduler  │  │   Engine    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
├─────────────────────────────────────────────────────────────────┤
│                      AI Provider Layer                           │
│  ┌──────────┐ ┌───────────┐ ┌────────┐ ┌────────┐               │
│  │Anthropic │ │Azure OpenAI│ │ OpenAI │ │ Ollama │               │
│  └──────────┘ └───────────┘ └────────┘ └────────┘               │
├─────────────────────────────────────────────────────────────────┤
│                       Output Layer                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ Markdown │ │   JSON   │ │  JUnit   │ │Dashboard │            │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### Component Diagram

```
code-conclave/
├── cli/
│   ├── ccl.ps1                 # Main entry point
│   ├── ccl.bat                 # Windows batch wrapper
│   └── lib/
│       ├── ai-engine.ps1       # AI provider orchestrator
│       ├── config-loader.ps1   # Configuration loading & merging
│       ├── mapping-engine.ps1  # Standard-to-finding mapping
│       ├── yaml-parser.ps1     # YAML parsing (pure PowerShell)
│       └── providers/          # AI provider implementations
│           ├── anthropic.ps1
│           ├── azure-openai.ps1
│           ├── openai.ps1
│           └── ollama.ps1
├── core/
│   ├── agents/                 # Agent instruction files
│   │   ├── sentinel.md
│   │   ├── guardian.md
│   │   ├── architect.md
│   │   ├── navigator.md
│   │   ├── herald.md
│   │   └── operator.md
│   ├── standards/              # Compliance standards
│   │   ├── core/               # Base standards
│   │   └── regulated/          # Industry-specific
│   ├── schemas/                # JSON schemas
│   │   ├── findings.schema.json
│   │   ├── config.schema.json
│   │   └── standard.schema.json
│   ├── mappings/               # Standard-finding mappings
│   └── templates/              # Report templates
└── CONTRACTS.md                # Shared agent contracts
```

### Data Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Config  │────▶│  Agent   │────▶│    AI    │────▶│ Findings │
│  Files   │     │  Queue   │     │ Provider │     │  Parser  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                                                         │
┌──────────┐     ┌──────────┐     ┌──────────┐          │
│ Reports  │◀────│Synthesis │◀────│ Standard │◀─────────┘
│ (Output) │     │ Engine   │     │ Mapper   │
└──────────┘     └──────────┘     └──────────┘
```

---

## Core Components

### 1. CLI Entry Point (ccl.ps1)

**Purpose:** Main orchestrator, handles CLI arguments, coordinates all components.

**Responsibilities:**
- Parse command-line arguments
- Load and merge configuration
- Initialize AI provider
- Schedule agent execution
- Collect and synthesize findings
- Generate output reports

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `Main` | Entry point, orchestrates flow |
| `Invoke-ReviewAgent` | Execute single agent review |
| `Get-FindingsCounts` | Parse findings report for stats |
| `Write-SynthesisReport` | Generate final summary |
| `Initialize-Project` | Set up project config |

### 2. Config Loader (config-loader.ps1)

**Purpose:** Load, merge, and validate configuration from multiple sources.

**Configuration Precedence (highest to lowest):**
1. CLI parameters
2. Project config (`.code-conclave/config.yaml`)
3. User config (`~/.code-conclave/config.yaml`)
4. Default config (tool defaults)

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `Get-EffectiveConfig` | Merge all config sources |
| `Get-ProjectConfig` | Load project-level config |
| `Get-DefaultConfig` | Return tool defaults |
| `Merge-Config` | Deep merge two configs |

### 3. AI Engine (ai-engine.ps1)

**Purpose:** Abstract AI provider interaction, handle retries, manage tokens.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `Initialize-AIProvider` | Load and validate provider |
| `Invoke-AgentReview` | Execute review with retries |
| `Test-ProviderConnection` | Validate API connectivity |
| `Get-CurrentProvider` | Return provider info |

### 4. Mapping Engine (mapping-engine.ps1)

**Purpose:** Map findings to compliance standard controls.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `Get-ControlMappings` | Load mapping rules |
| `Map-FindingsToControls` | Apply mappings |
| `Get-ComplianceGaps` | Identify unmapped controls |

---

## AI Provider Interface

### Provider Contract

All providers must implement these functions:

```powershell
function Get-ProviderInfo {
    <#
    .OUTPUTS
        @{
            Name = [string]            # Display name
            Version = [string]         # Provider version
            SupportsStreaming = [bool] # Streaming support
            MaxContextTokens = [int]   # Context window size
        }
    #>
}

function Test-ProviderConnection {
    param([hashtable]$Config)
    <#
    .OUTPUTS
        @{
            Success = [bool]
            Error = [string]  # null if success
        }
    #>
}

function Invoke-AICompletion {
    param(
        [hashtable]$Config,
        [string]$SharedContext,    # Cacheable shared prefix (CONTRACTS + project context)
        [string]$SystemPrompt,    # Agent-specific instructions
        [string]$UserPrompt,
        [string]$Tier,            # "primary" or "lite" — resolved to model internally
        [int]$MaxTokens
    )
    <#
    .OUTPUTS
        @{
            Success = [bool]
            Content = [string]         # Response text
            TokensUsed = @{
                Input = [int]
                Output = [int]
                CacheRead = [int]      # Tokens served from cache (discounted)
                CacheWrite = [int]     # Tokens written to cache (first request)
            }
            Error = [string]           # null if success
        }
    #>
}
```

### SharedContext Parameter

The `SharedContext` parameter carries the cacheable project context that is identical across all agents in a single review run. It includes:

1. **CONTRACTS.md** -- Shared output format rules
2. **File tree** -- Project structure
3. **Source file contents** -- Either full scan or diff-scoped

The AI engine builds this context once and passes it to every agent. Provider implementations handle caching differently:

| Provider | SharedContext Handling |
|----------|-----------------------|
| Anthropic | Sent as separate system message block with `cache_control: { type: "ephemeral" }` |
| Azure OpenAI | Concatenated into system prompt; caching is automatic (prefix matching) |
| OpenAI | Concatenated into system prompt; caching is automatic (prefix matching) |
| Ollama | Concatenated into system prompt; no caching (local, free) |

### Tier Resolution

The `Tier` parameter determines which model is used for a given agent call. Resolution logic:

1. Read agent's `tier` from config (default: see agent defaults)
2. If `tier` is `"lite"`:
   - Anthropic: use `lite_model` if set, else fall back to `model`
   - Azure OpenAI: use `lite_deployment` if set, else fall back to `deployment`
   - OpenAI: use `lite_model` if set, else fall back to `model`
   - Ollama: ignore tier (local, free)
3. If `tier` is `"primary"`: use the standard model/deployment

### Provider Configurations

#### Anthropic

```yaml
anthropic:
  model: claude-sonnet-4-20250514
  lite_model: claude-haiku-4-5-20251001
  api_key_env: ANTHROPIC_API_KEY
  max_tokens: 16000
```

**API Endpoint:** `https://api.anthropic.com/v1/messages`

**Headers:**
- `x-api-key`: API key
- `anthropic-version`: `2023-06-01`
- `Content-Type`: `application/json`

**Caching:** Explicit `cache_control` on SharedContext block. Reports `cache_read_input_tokens` and `cache_creation_input_tokens` in response usage.

#### Azure OpenAI

```yaml
azure-openai:
  endpoint: https://your-resource.openai.azure.com/
  deployment: gpt-4o
  lite_deployment: gpt-4o-mini
  api_version: "2024-10-01-preview"
  api_key_env: AZURE_OPENAI_KEY
  max_tokens: 16000
```

**API Endpoint:** `{endpoint}/openai/deployments/{deployment}/chat/completions?api-version={version}`

**Headers:**
- `api-key`: API key
- `Content-Type`: `application/json`

**Caching:** Automatic prefix caching. API version `2024-10-01-preview` or later reports `prompt_tokens_details.cached_tokens` in response usage.

#### OpenAI

```yaml
openai:
  model: gpt-4o
  lite_model: gpt-4o-mini
  api_key_env: OPENAI_API_KEY
  max_tokens: 16000
```

**API Endpoint:** `https://api.openai.com/v1/chat/completions`

**Headers:**
- `Authorization`: `Bearer {key}`
- `Content-Type`: `application/json`

**Caching:** Automatic prefix caching. Reports `prompt_tokens_details.cached_tokens` in response usage.

#### Ollama

```yaml
ollama:
  endpoint: http://localhost:11434
  model: llama3.1:70b
  max_tokens: 8000
```

**API Endpoint:** `{endpoint}/api/chat`

**Headers:**
- `Content-Type`: `application/json`

**Caching:** N/A (local, free).

---

## Agent System

### Agent Definition Structure

Each agent is defined in a Markdown file:

```markdown
# AGENT_NAME - Role Description

## Identity
You are [NAME], the [role] agent in the Code Conclave system.

## Mission
[What this agent assesses]

## Focus Areas
1. [Area 1]
2. [Area 2]

## Review Process
1. [Step 1]
2. [Step 2]

## Output Format
[Structured output requirements]

## Severity Guidelines
- BLOCKER: [criteria]
- HIGH: [criteria]
- MEDIUM: [criteria]
- LOW: [criteria]
```

### Built-in Agents

| Agent | File | Focus | Default Tier |
|-------|------|-------|-------------|
| SENTINEL | `sentinel.md` | Test coverage, quality gates | primary |
| GUARDIAN | `guardian.md` | Security vulnerabilities | primary |
| ARCHITECT | `architect.md` | Code structure, patterns | primary |
| NAVIGATOR | `navigator.md` | User experience | lite |
| HERALD | `herald.md` | Documentation | lite |
| OPERATOR | `operator.md` | Operations, deployment | lite |

### Agent Execution Flow

```
1. Load agent instruction file
2. Load CONTRACTS.md (shared rules)
3. Build system prompt (instructions + contracts)
4. Build user prompt (project context + task)
5. Call AI provider
6. Parse response into findings
7. Save to {agent}-findings.md
```

### Custom Agents

Create custom agents by:

1. **Project-level override:** `.code-conclave/agents/{agent}.md`
2. **New agent:** Add to `core/agents/` with unique name

---

## Findings Schema

### Finding Structure

```json
{
  "id": "SEN-001",
  "agent": "sentinel",
  "severity": "HIGH",
  "title": "Missing unit tests for payment service",
  "file": "backend/services/payment_service.py",
  "line": 45,
  "evidence": "def process_payment(...):\n    # No test coverage",
  "remediation": "Add unit tests covering success/failure paths",
  "tags": ["testing", "coverage"],
  "standards": ["ISO-9001:8.5.1"]
}
```

### Severity Levels

| Level | Value | Description |
|-------|-------|-------------|
| BLOCKER | 4 | Cannot ship, must fix |
| HIGH | 3 | Significant risk |
| MEDIUM | 2 | Should address |
| LOW | 1 | Nice to have |

### Finding ID Format

```
{AGENT_PREFIX}-{SEQUENCE}

Examples:
- SEN-001 (Sentinel finding 1)
- GUA-003 (Guardian finding 3)
- ARC-012 (Architect finding 12)
```

### Verdict Calculation

```
IF any BLOCKER findings:
    verdict = "HOLD"
ELSE IF count(HIGH) > 3:
    verdict = "CONDITIONAL"
ELSE:
    verdict = "SHIP"
```

---

## Standards Engine

### Standard Definition Structure

```yaml
# standard-name.yaml
metadata:
  id: iso-9001-2015
  name: ISO 9001:2015
  version: "2015"
  category: quality-management
  description: Quality Management Systems

controls:
  - id: "4.1"
    title: Understanding the organization
    description: ...
    
  - id: "8.5.1"
    title: Control of production
    description: ...
    mappings:
      - agent: sentinel
        keywords: ["test", "coverage", "qa"]
```

### Available Standards

| ID | Name | Category |
|----|------|----------|
| `iso-9001-2015` | ISO 9001:2015 | Quality Management |
| `iso-13485-2016` | ISO 13485:2016 | Medical Device QMS |
| `fda-21-cfr-11` | FDA 21 CFR Part 11 | Electronic Records |
| `fda-820-qsr` | FDA 820 QSR | Quality System Regulation |
| `cmmc-l1` | CMMC Level 1 | Cybersecurity |
| `cmmc-l2` | CMMC Level 2 | Cybersecurity |
| `itar` | ITAR | Export Control |
| `as9100-rev-d` | AS9100 Rev D | Aerospace QMS |

### Standard Tiers

| Tier | Behavior | CLI Override |
|------|----------|--------------|
| **required** | Always applied | Cannot skip |
| **default** | Applied unless skipped | `-SkipStandards` |
| **available** | Not applied unless added | `-AddStandards` |

---

## Configuration System

### Configuration Schema

See [docs/config-schema.yaml](config-schema.yaml) for complete schema.

### Key Configuration Sections

```yaml
project:           # Project metadata
ai:                # AI provider settings
agents:            # Agent-specific settings
standards:         # Compliance standards
output:            # Report configuration
ci:                # CI/CD settings
```

### Configuration Resolution

```
1. CLI arguments (highest priority)
2. Environment variables
3. Project config (.code-conclave/config.yaml)
4. User config (~/.code-conclave/config.yaml)
5. Tool defaults (lowest priority)
```

---

## CLI Reference

### Syntax

```
ccl.ps1 [-Project] <path>
        [-Init]
        [-Agent <name>]
        [-Agents <name1,name2,...>]
        [-StartFrom <name>]
        [-Standard <name>]
        [-AddStandards <name1,name2,...>]
        [-SkipStandards <name1,name2,...>]
        [-Profile <name>]
        [-Timeout <minutes>]
        [-OutputFormat <markdown|json|junit>]
        [-BaseBranch <branch>]
        [-SkipSynthesis]
        [-DryRun]
        [-CI]
        [-Verbose]
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Project` | string | (required) | Path to project |
| `-Init` | switch | false | Initialize project config |
| `-Agent` | string | - | Run single agent |
| `-Agents` | string[] | all | Run specific agents |
| `-StartFrom` | string | - | Resume from agent |
| `-Standard` | string | - | Apply single standard |
| `-AddStandards` | string[] | - | Add standards |
| `-SkipStandards` | string[] | - | Skip default standards |
| `-Profile` | string | - | Use standard profile |
| `-Timeout` | int | 40 | Minutes per agent |
| `-OutputFormat` | string | markdown | Output format |
| `-BaseBranch` | string | (auto-detect) | Base branch for diff-scoped scanning |
| `-SkipSynthesis` | switch | false | Skip final report |
| `-DryRun` | switch | false | Preview only |
| `-CI` | switch | false | CI mode (exit codes) |

---

## Exit Codes

| Code | Meaning | CI Behavior |
|------|---------|-------------|
| 0 | SHIP - All clear | Pass |
| 1 | HOLD - Blockers found | Fail |
| 2 | CONDITIONAL - Warnings | Pass (configurable) |
| 10 | Configuration error | Fail |
| 11 | AI provider error | Fail |
| 12 | Agent timeout | Fail |
| 13 | Invalid arguments | Fail |
| 14 | Project not found | Fail |

---

## Output Formats

### Markdown (Default)

```markdown
# SENTINEL Findings Report

## Finding: SEN-001
**Severity:** [HIGH]
**Title:** Missing unit tests
**File:** `src/service.py`
**Line:** 45

### Evidence
```python
def process():
    pass
```

### Remediation
Add unit tests.
```

### JSON

```json
{
  "agent": "sentinel",
  "timestamp": "2025-02-04T18:00:00Z",
  "findings": [
    {
      "id": "SEN-001",
      "severity": "HIGH",
      "title": "Missing unit tests",
      "file": "src/service.py",
      "line": 45
    }
  ],
  "summary": {
    "blocker": 0,
    "high": 1,
    "medium": 2,
    "low": 0
  },
  "verdict": "CONDITIONAL"
}
```

### JUnit XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Code Conclave" tests="6" failures="1">
  <testsuite name="SENTINEL" tests="1" failures="0">
    <testcase name="SEN-001: Missing unit tests" classname="sentinel">
      <failure message="[HIGH] Missing unit tests in src/service.py:45"/>
    </testcase>
  </testsuite>
</testsuites>
```

---

## API Reference

### Internal Functions

#### Get-EffectiveConfig

```powershell
Get-EffectiveConfig -ProjectPath <string> [-Profile <string>] [-AddStandards <string[]>] [-SkipStandards <string[]>]
```

Returns merged configuration hashtable.

#### Initialize-AIProvider

```powershell
Initialize-AIProvider -Config <hashtable>
```

Loads and validates AI provider. Throws on error.

#### Invoke-AgentReview

```powershell
Invoke-AgentReview -AgentName <string> -SystemPrompt <string> -UserPrompt <string> -OutputPath <string>
```

Executes agent review with retries.

#### Get-FindingsCounts

```powershell
Get-FindingsCounts -FilePath <string>
```

Parses findings file, returns severity counts.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | TBD | Initial release with multi-provider support |
| 0.9.0 | 2025-02 | AI provider abstraction |
| 0.8.0 | 2025-02 | Tiered standards support |
| 0.7.0 | 2025-01 | ITAR compliance pack |

---

*Last updated: 2026-02-05*
