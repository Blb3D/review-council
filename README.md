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

## Quick Start

```powershell
# Clone Code Conclave
git clone https://github.com/yourusername/code-conclave.git
cd code-conclave

# Review any project
.\cli\ccl.ps1 -Project "C:\path\to\your\project"
```

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell Core (Mac/Linux)
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed and authenticated

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

## License

MIT

---

Built with AI by humans who got tired of missing things in code reviews.
