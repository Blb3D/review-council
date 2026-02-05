# Changelog

All notable changes to Code Conclave will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- Comprehensive operations guide with production rollback procedures (`docs/OPERATIONS.md`)
- Test infrastructure with 34 Pester tests for core modules
- API key sanitization to prevent credential leakage in error messages
- False positive prevention guidance in all agent skill files

### Fixed
- **GUARDIAN-004**: API key patterns now redacted from error messages
- **GUARDIAN-001**: Path traversal vulnerability in dashboard file serving
- **GUARDIAN-002**: WebSocket authentication with origin whitelist
- **GUARDIAN-005**: JSON body size limit (100KB) to prevent DoS
- **GUARDIAN-006**: Input validation on all dashboard API endpoints

### Changed
- Agent prompts updated to reduce false positives while maintaining standards
- Dashboard security hardened for localhost-only operation

---

## [2.0.0] - 2026-02-03

### Added
- Multi-provider AI support (Anthropic, Azure OpenAI, OpenAI, Ollama)
- Cost optimization with diff-scoping, prompt caching, and model tiering
- JUnit XML output format for CI/CD integration
- Exit codes for pipeline automation
- GitHub Actions workflow for automated reviews
- 3-layer configuration system (defaults, project, CLI overrides)

### Changed
- Removed dependency on `claude` CLI - now uses direct API calls
- Restructured provider layer with pluggable architecture

---

## [1.0.0] - 2026-01-15

### Added
- Initial release with 6 review agents (Guardian, Sentinel, Architect, Navigator, Herald, Operator)
- Compliance mapping for CMMC, FDA 820, FDA Part 11
- Markdown report generation
- Basic CLI interface
