# Code Conclave Documentation

Welcome to the Code Conclave documentation. This guide covers everything you need to know about using the AI-powered code review system.

## Quick Links

| Document | Description |
|----------|-------------|
| [CLI Reference](CLI.md) | Complete command-line interface guide |
| [Agents Guide](AGENTS.md) | Detailed documentation for all 6 review agents |
| [Compliance Standards](STANDARDS.md) | Guide to compliance packs and mapping |
| [Methodology](REVIEW-COUNCIL-METHODOLOGY.md) | Validation framework and evidence requirements |

---

## Getting Started

### Prerequisites

- PowerShell 5.1+ (Windows) or PowerShell Core 7+ (Mac/Linux)
- [Claude Code CLI](https://docs.anthropic.com/claude-code) installed and authenticated
- Git (for project analysis)

### Installation

```powershell
# Clone the repository
git clone https://github.com/yourusername/code-conclave.git
cd code-conclave

# Verify installation
.\cli\ccl.ps1 -Help
```

### Your First Review

```powershell
# Run a full review on any project
.\cli\ccl.ps1 -Project "C:\path\to\your\project"

# Or run a quick security check
.\cli\ccl.ps1 -Project "C:\path\to\your\project" -Agent guardian
```

---

## Core Concepts

### The Six Agents

Code Conclave deploys specialized AI agents, each focused on a specific review domain:

| Agent | Domain | Key Concerns |
|-------|--------|--------------|
| **SENTINEL** | Quality | Test coverage, regression risks, critical paths |
| **GUARDIAN** | Security | Vulnerabilities, auth issues, secrets exposure |
| **ARCHITECT** | Code Health | Tech debt, patterns, dependencies |
| **NAVIGATOR** | UX | User friction, accessibility, error handling |
| **HERALD** | Documentation | API docs, guides, onboarding |
| **OPERATOR** | Production | Deployment, logging, monitoring |

### Severity Levels

| Level | Impact | Action Required |
|-------|--------|-----------------|
| **BLOCKER** | Cannot ship | Must fix before release |
| **HIGH** | Significant | Should fix before release |
| **MEDIUM** | Notable | Consider fixing or document |
| **LOW** | Polish | Nice to have |

### Verdicts

| Verdict | Criteria | Recommendation |
|---------|----------|----------------|
| **SHIP** | 0 blockers, ≤3 high | Ready for release |
| **CONDITIONAL** | 0 blockers, >3 high | Review high issues |
| **HOLD** | Any blockers | Fix blockers first |

---

## Compliance Mode

Code Conclave supports mapping findings to compliance frameworks for regulated industries.

### Available Standards

| Standard | Domain | Controls |
|----------|--------|----------|
| CMMC Level 2 | Cybersecurity | 110 practices |
| FDA 21 CFR 820 QSR | Medical Devices | ~45 requirements |
| FDA 21 CFR Part 11 | Electronic Records | ~25 requirements |

### Running with Compliance

```powershell
# Review with CMMC compliance context
.\cli\ccl.ps1 -Project "C:\myproject" -Standard cmmc-l2

# Map existing findings to a standard
.\cli\ccl.ps1 -Map "C:\myproject\.code-conclave" -Standard cmmc-l2

# List available standards
.\cli\ccl.ps1 -Standards list
```

See [STANDARDS.md](STANDARDS.md) for detailed compliance documentation.

---

## Project Structure

```
code-conclave/
├── cli/                    # Command-line interface
│   ├── ccl.ps1             # Main entry point
│   ├── commands/           # Subcommands (report, map, standards)
│   ├── lib/                # Core libraries
│   └── config/             # Configuration examples
├── core/
│   ├── agents/             # Agent instruction files
│   ├── standards/          # Compliance packs (YAML)
│   ├── schemas/            # JSON schemas
│   └── templates/          # Report templates
├── dashboard/              # Live monitoring UI
├── docs/                   # Documentation (you are here)
└── examples/               # Sample output
```

---

## Output Structure

Reviews are saved to your project:

```
your-project/
└── .code-conclave/
    └── reviews/
        ├── sentinel-findings.md
        ├── guardian-findings.md
        ├── architect-findings.md
        ├── navigator-findings.md
        ├── herald-findings.md
        ├── operator-findings.md
        └── RELEASE-READINESS-REPORT.md
```

---

## Customization

### Custom Agents

Create a file in `core/agents/` following the agent template:

```markdown
# CUSTOM - Code Conclave

## Identity
You are CUSTOM, the [role] agent for Code Conclave.

## Mission
Assess [domain] for release readiness.

## Review Process
1. Step one...
2. Step two...

## Output Format
[Finding format specification]
```

### Project Overrides

Create `.code-conclave/agents/` in your project to override agent behavior:

```
your-project/
└── .code-conclave/
    └── agents/
        └── sentinel.md  # Project-specific SENTINEL instructions
```

---

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/code-conclave/issues)
- **Documentation**: This folder
- **Examples**: See `examples/` folder

---

*Code Conclave v2.0*
