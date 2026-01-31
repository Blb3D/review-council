# Review Council

> 🤖 AI-powered code review for any project. Six perspectives. One command.

```
  ██████╗ ███████╗██╗   ██╗██╗███████╗██╗    ██╗
  ██╔══██╗██╔════╝██║   ██║██║██╔════╝██║    ██║
  ██████╔╝█████╗  ██║   ██║██║█████╗  ██║ █╗ ██║
  ██╔══██╗██╔══╝  ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║
  ██║  ██║███████╗ ╚████╔╝ ██║███████╗╚███╔███╔╝
  ╚═╝  ╚═╝╚══════╝  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ 
   ██████╗ ██████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗██╗     
  ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔════╝██║██║     
  ██║     ██║   ██║██║   ██║██╔██╗ ██║██║     ██║██║     
  ╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║╚██████╗██║███████╗
   ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝╚══════╝
```

## What It Does

Deploys 6 specialized AI agents to review your codebase from different perspectives:

| Agent | Focus | Finds |
|-------|-------|-------|
| 🛡️ **SENTINEL** | Quality | Test gaps, regression risks, coverage holes |
| 🔒 **GUARDIAN** | Security | Vulnerabilities, auth issues, exposed secrets |
| 🏗️ **ARCHITECT** | Code Health | Tech debt, patterns, dependencies |
| 🧭 **NAVIGATOR** | UX | User friction, error messages, accessibility |
| 📜 **HERALD** | Documentation | Missing docs, outdated guides, setup gaps |
| ⚙️ **OPERATOR** | Production | Deployment risks, logging, CI/CD issues |

## Quick Start

```powershell
# Clone Review Council
git clone https://github.com/yourusername/review-council.git
cd review-council

# Review any project
.\review-council.ps1 -Project "C:\path\to\your\project"
```

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell Core (Mac/Linux)  
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed and authenticated

## Usage

### Full Review (All 6 Agents)

```powershell
.\review-council.ps1 -Project "C:\repos\my-app"
```

### Single Agent

```powershell
.\review-council.ps1 -Project "C:\repos\my-app" -Agent sentinel
.\review-council.ps1 -Project "C:\repos\my-app" -Agent guardian
```

### Multiple Specific Agents

```powershell
.\review-council.ps1 -Project "C:\repos\my-app" -Agents sentinel,guardian,architect
```

### Parallel Execution (Faster)

```powershell
.\review-council.ps1 -Project "C:\repos\my-app" -Parallel
```

### Resume From Agent

```powershell
.\review-council.ps1 -Project "C:\repos\my-app" -StartFrom architect
```

### Dry Run

```powershell
.\review-council.ps1 -Project "C:\repos\my-app" -DryRun
```

## Output

Results are saved to your project:

```
your-project/
└── .review-council/
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

## Customization

### Add Custom Agents

Create a new file in `agents/`:

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
.\review-council.ps1 -Project "..." -Agent custom
```

### Override Agent Behavior

Copy an agent file to your project:
```
your-project/.review-council/agents/sentinel.md
```

Project-specific overrides take precedence.

## Tips

1. **Start with SENTINEL + GUARDIAN** for quick security/quality check
2. **Run full council before releases** for comprehensive review
3. **Use -Parallel** when you don't need agent handoffs
4. **Add .review-council/reviews/ to .gitignore**

## License

MIT

---

Built with 🤖 by humans who got tired of missing things in code reviews.
