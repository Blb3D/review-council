# Code Conclave

> AI-powered code review for any project. Six perspectives. One command.

```
   ██████╗ ██████╗ ██████╗ ███████╗
  ██╔════╝██╔═══██╗██╔══██╗██╔════╝
  ██║     ██║   ██║██║  ██║█████╗
  ██║     ██║   ██║██║  ██║██╔══╝
  ╚██████╗╚██████╔╝██████╔╝███████╗
   ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝
   ██████╗ ██████╗ ███╗   ██╗ ██████╗██╗      █████╗ ██╗   ██╗███████╗
  ██╔════╝██╔═══██╗████╗  ██║██╔════╝██║     ██╔══██╗██║   ██║██╔════╝
  ██║     ██║   ██║██╔██╗ ██║██║     ██║     ███████║██║   ██║█████╗
  ██║     ██║   ██║██║╚██╗██║██║     ██║     ██╔══██║╚██╗ ██╔╝██╔══╝
  ╚██████╗╚██████╔╝██║ ╚████║╚██████╗███████╗██║  ██║ ╚████╔╝ ███████╗
   ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝  ╚═══╝ ╚══════╝
```

## What It Does

Deploys 6 specialized AI agents to review your codebase from different perspectives:

| Agent | Focus | Finds |
|-------|-------|-------|
| **SENTINEL** | Quality | Test gaps, regression risks, coverage holes |
| **GUARDIAN** | Security | Vulnerabilities, auth issues, exposed secrets |
| **ARCHITECT** | Code Health | Tech debt, patterns, dependencies |
| **NAVIGATOR** | UX | User friction, error messages, accessibility |
| **HERALD** | Documentation | Missing docs, outdated guides, setup gaps |
| **OPERATOR** | Production | Deployment risks, logging, CI/CD issues |

For detailed agent documentation, see [AGENTS.md](docs/AGENTS.md).

## Quick Start

```powershell
# Clone Code Conclave
git clone https://github.com/Blb3D/review-council.git code-conclave
cd code-conclave

# Set your AI provider API key
$env:ANTHROPIC_API_KEY = "sk-ant-..."
# Or use: AZURE_OPENAI_KEY, OPENAI_API_KEY

# Review any project
.\cli\ccl.ps1 -Project "C:\path\to\your\project"
```

For detailed setup, see [Installation Guide](docs/INSTALLATION.md).

## Requirements

- PowerShell 7.0+ (cross-platform) or 5.1+ (Windows)
- Git (for diff-scoping features)
- API key for one of: Anthropic, Azure OpenAI, OpenAI, or Ollama (local, free)

## Usage

### Full Review (All 6 Agents)

```powershell
.\cli\ccl.ps1 -Project "C:\repos\my-app"
```

### Single Agent

```powershell
.\cli\ccl.ps1 -Project "C:\repos\my-app" -Agent sentinel
.\cli\ccl.ps1 -Project "C:\repos\my-app" -Agent guardian
```

### Multiple Specific Agents

```powershell
.\cli\ccl.ps1 -Project "C:\repos\my-app" -Agents sentinel,guardian,architect
```

### Resume From Agent

```powershell
.\cli\ccl.ps1 -Project "C:\repos\my-app" -StartFrom architect
```

### Dry Run

```powershell
.\cli\ccl.ps1 -Project "C:\repos\my-app" -DryRun
```

## Output

Results are saved to your project:

```
your-project/
└── .code-conclave/
    ├── sentinel-findings.md
    ├── guardian-findings.md
    ├── architect-findings.md
    ├── navigator-findings.md
    ├── herald-findings.md
    ├── operator-findings.md
    └── RELEASE-READINESS-REPORT.md
```

### Sample Report

```
╔══════════════════════════════════════╗
║     VERDICT: CONDITIONAL             ║
╚══════════════════════════════════════╝

| Agent | B | H | M | L |
|-------|---|---|---|---|
| SENTINEL | 0 | 2 | 3 | 1 |
| GUARDIAN | 0 | 0 | 1 | 0 |
| ARCHITECT | 0 | 1 | 2 | 4 |
| NAVIGATOR | 0 | 0 | 2 | 3 |
| HERALD | 0 | 1 | 1 | 0 |
| OPERATOR | 0 | 0 | 0 | 1 |
```

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **BLOCKER** | Cannot ship | Must fix before release |
| **HIGH** | Significant impact | Should fix before release |
| **MEDIUM** | Notable issue | Consider fixing, or document |
| **LOW** | Polish item | Nice to have |

## Verdicts

| Verdict | Meaning |
|---------|---------|
| **SHIP** | No blockers, ≤3 high issues |
| **CONDITIONAL** | No blockers, >3 high issues |
| **HOLD** | Blockers present |

## Project Structure

```
code-conclave/
├── core/
│   ├── agents/          # Agent instruction files
│   ├── standards/       # Compliance packs (CMMC, ISO, FDA)
│   ├── schemas/         # JSON schemas for findings & standards
│   ├── mappings/        # Finding-to-control mappings
│   └── templates/       # Report templates
├── cli/
│   ├── ccl.ps1          # Main CLI entry point
│   ├── ccl.bat          # Windows batch wrapper
│   ├── commands/        # CLI subcommands
│   └── config/          # Example configuration
├── dashboard/           # Live monitoring dashboard
├── docs/                # Documentation
├── shared/              # Shared utilities
└── examples/            # Sample output
```

## Customization

### Add Custom Agents

Create a new file in `core/agents/`:

```markdown
# CUSTOM - Your Agent

## Identity
You are CUSTOM, the [role] agent...

## Mission
Assess [what] for release readiness.

## Review Process
1. ...
2. ...

## Output Format
...
```

Then run:

```powershell
.\cli\ccl.ps1 -Project "..." -Agent custom
```

### Override Agent Behavior

Copy an agent file to your project:

```
your-project/.code-conclave/agents/sentinel.md
```

Project-specific overrides take precedence.

## Tips

1. **Start with SENTINEL + GUARDIAN** for quick security/quality check
2. **Run full conclave before releases** for comprehensive review
3. **Add .code-conclave/reviews/ to .gitignore**

## CI/CD Integration

Code Conclave integrates with your pipelines:

```yaml
# GitHub Actions
- name: Run Code Conclave
  run: |
    pwsh ./cli/ccl.ps1 -Project . -OutputFormat junit -CI
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

- name: Publish Results
  uses: EnricoMi/publish-unit-test-result-action@v2
  with:
    files: .code-conclave/reviews/conclave-results.xml
```

Exit codes: `0` = SHIP, `1` = HOLD (blockers), `2` = CONDITIONAL

See [CI/CD Guide](docs/CI-CD.md) for Azure DevOps, Jenkins, and more.

## Documentation

| Guide | Description |
|-------|-------------|
| [Installation](docs/INSTALLATION.md) | Setup for all platforms and providers |
| [Configuration](docs/CONFIGURATION.md) | 3-layer config system, all options |
| [Agents](docs/AGENTS.md) | What each agent reviews and how to customize |
| [CI/CD](docs/CI-CD.md) | Pipeline integration for GitHub, Azure DevOps |
| [Operations](docs/OPERATIONS.md) | Production deployment, rollback, monitoring |

## License

MIT

---

Built with AI by humans who got tired of missing things in code reviews.
