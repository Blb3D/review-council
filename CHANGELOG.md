# Changelog

All notable changes to Code Conclave will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Versioning Policy

- **Semantic Versioning**: MAJOR.MINOR.PATCH
- **Support**: Latest 2 minor versions receive security updates
- **Recommendation**: Pin to MAJOR.MINOR in production (e.g., `2.0.*`)

---

## [Unreleased] - Targeting 2.1.0

### Highlights
- Enhanced security hardening based on self-review findings
- Comprehensive operations documentation for production deployments
- Test infrastructure with 34 automated tests

### Added
- [Operations guide](docs/OPERATIONS.md) with production rollback procedures, health checks, and incident response
- Test infrastructure with 34 Pester tests for core modules (ai-engine, config-loader, junit-formatter)
- False positive prevention guidance in all agent skill files

### Security Fixes
- **Credential Protection**: API keys are now automatically hidden from error messages, preventing accidental exposure in logs
- **Dashboard Security**: Fixed a vulnerability that could allow unauthorized file access through path traversal
- **WebSocket Protection**: Added origin whitelisting to prevent unauthorized WebSocket connections from external sources
- **DoS Prevention**: Added 100KB request size limit to prevent dashboard crashes from oversized uploads
- **Input Validation**: All dashboard endpoints now validate user input to prevent injection attacks

### Changed
- Agent prompts refined to reduce false positives while maintaining thorough review standards
- Dashboard hardened for localhost-only operation with strict origin checking

### Deployment Notes
No breaking changes from 2.0.0. Upgrade by pulling latest and restarting.

---

## [2.0.0] - 2025-02-03

### Highlights
- **Choose Your AI Provider**: No longer locked into Claude CLI - use Anthropic, Azure OpenAI, OpenAI, or Ollama
- **Reduce Costs by 60-90%**: New diff-scoping and prompt caching features significantly lower API costs
- **CI/CD Integration**: JUnit XML output and exit codes for seamless GitHub Actions and Azure Pipelines integration

### ⚠️ Breaking Changes
- **Removed `claude` CLI dependency**: Code Conclave now communicates directly with AI provider APIs
  - **Action Required**: Configure your AI provider in `config.yaml` or via environment variables
  - Your existing `claude` CLI installation is no longer needed for Code Conclave

### Migration Guide (1.x → 2.0)
1. **Update configuration**: Add `ai:` section to your `.code-conclave/config.yaml`:
   ```yaml
   ai:
     provider: anthropic  # or azure-openai, openai, ollama
   ```
2. **Set API key**: Export your provider's API key:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   # or AZURE_OPENAI_KEY, OPENAI_API_KEY
   ```
3. **Verify**: Run `ccl.ps1 -Project . -DryRun` to confirm configuration
4. See [CONFIGURATION.md](docs/CONFIGURATION.md) for complete provider setup

### Added
- Multi-provider AI support (Anthropic, Azure OpenAI, OpenAI, Ollama)
- Cost optimization with diff-scoping, prompt caching, and model tiering
- JUnit XML output format for CI/CD integration (`-OutputFormat junit`)
- Exit codes for pipeline automation (0=SHIP, 1=HOLD, 2=CONDITIONAL)
- GitHub Actions workflow for automated PR reviews
- 3-layer configuration system (defaults → project config → CLI overrides)

### Changed
- Direct API communication replaces `claude` CLI dependency
- Restructured provider layer with pluggable architecture

### Deployment Checklist
- [ ] Backup current configuration
- [ ] Verify PowerShell 7.0+ installed
- [ ] Configure AI provider credentials
- [ ] Test with `ccl.ps1 -Project . -DryRun`
- [ ] Update CI/CD pipelines to use new exit codes

### Compatibility
- **PowerShell**: 7.0+ (cross-platform) or 5.1+ (Windows)
- **Git**: Required for diff-scoping features
- **Providers**: Anthropic Claude, Azure OpenAI, OpenAI, Ollama

---

## [1.0.0] - 2025-01-15

### Added
- Initial release with 6 specialized review agents:
  - **GUARDIAN**: Security vulnerabilities and credential exposure
  - **SENTINEL**: Test coverage and critical path analysis
  - **ARCHITECT**: Code structure and technical debt
  - **NAVIGATOR**: User experience and workflow analysis
  - **HERALD**: Documentation completeness
  - **OPERATOR**: Production readiness and deployment
- Compliance mapping for CMMC Level 2, FDA 21 CFR Part 820, FDA 21 CFR Part 11
- Markdown report generation with synthesis across all agents
- PowerShell CLI interface with flexible agent selection
