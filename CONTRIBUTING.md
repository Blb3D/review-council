# Contributing to Code Conclave

Thank you for your interest in contributing to Code Conclave! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR-USERNAME/review-council.git`
3. Create a feature branch: `git checkout -b feat/your-feature`

### PowerShell CLI (existing)

```powershell
# Run tests
Invoke-Pester ./cli/tests

# Dry-run a review
./cli/ccl.ps1 -Project ./path/to/repo -DryRun -Agent guardian -CI
```

### Python Package (new)

```bash
# Install in development mode
pip install -e ".[dev]"

# Run tests
pytest tests/ -v

# Type checking
mypy src/conclave

# Linting
ruff check src/ tests/
```

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/Blb3D/review-council/issues)
- Include the output of `ccl.ps1 --version` or `ccl --version`
- For false positive reports, include the finding ID, the file it flagged, and why you believe it's incorrect

### Submitting Pull Requests

1. Keep PRs focused on a single change
2. Include tests for new functionality
3. Update documentation if behavior changes
4. Ensure all tests pass before submitting

### Areas Where Help is Welcome

- **Agent prompt improvements** — reducing false positives, improving evidence quality
- **New compliance standards** — adding YAML packs for additional frameworks (SOC 2, HIPAA, PCI DSS, etc.)
- **Provider integrations** — adding support for new AI providers
- **Bug fixes** — especially in the findings parser and scanner
- **Documentation** — examples, tutorials, translations

## Code Style

### PowerShell
- Follow standard PowerShell conventions (PascalCase for functions, camelCase for variables)
- Use `Write-Verbose` for debug output, never `Write-Host` for data
- Include comment-based help for public functions

### Python
- Python 3.10+ (use `X | Y` union syntax, not `Union[X, Y]`)
- Format with `ruff` (line length 100)
- Type hints on all public functions
- Docstrings on modules and public classes

## Architecture Notes

- Agent prompts live in `core/agents/` (PowerShell) and `src/conclave/data/agents/` (Python)
- The `CONTRACTS.md` file defines the output format all agents must follow
- Findings must include file:line evidence for BLOCKER/HIGH severity (see Evidence-Based Severity Rules)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
