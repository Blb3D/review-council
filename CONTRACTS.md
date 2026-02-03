# Code Conclave Agent Contracts

This document defines the shared rules, severity definitions, and output formats that all agents must follow.

---

## Severity Definitions

All agents use these exact severity levels:

| Severity | Criteria | Action Required |
|----------|----------|-----------------|
| **BLOCKER** | Data loss, security breach, core workflow broken, crashes | Must fix before release |
| **HIGH** | Significant user impact, major feature broken, security weakness | Should fix before release |
| **MEDIUM** | Notable issue, degraded experience, workarounds exist | Fix soon after release |
| **LOW** | Minor polish, cosmetic, nice-to-have improvement | Backlog |

---

## Output Format

Every agent MUST output findings in this exact markdown format:

```markdown
# {AGENT_NAME} Review Findings

**Project:** {project_name}
**Date:** {YYYY-MM-DD}
**Agent:** {AGENT_NAME}
**Status:** COMPLETE | PARTIAL | ERROR

---

## Summary

- **BLOCKER:** {count}
- **HIGH:** {count}
- **MEDIUM:** {count}
- **LOW:** {count}

---

## Findings

### {AGENT}-001: {Brief Title} [SEVERITY]

**Location:** `path/to/file.py:123` or `General`
**Effort:** S (<1hr) | M (1-4hrs) | L (>4hrs)

**Issue:**
{Description of what's wrong}

**Evidence:**
{Code snippet, test output, or specific observation}

**Recommendation:**
{How to fix it}

---

### {AGENT}-002: {Next Finding} [SEVERITY]

...
```

---

## Agent Domains

Each agent owns specific concerns. Do not duplicate findings across agents.

| Agent | Primary Domain | Does NOT Cover |
|-------|---------------|----------------|
| SENTINEL | Test coverage, critical paths, edge cases | Security vulns, UX issues |
| GUARDIAN | Auth, injection, secrets, CVEs | Test coverage, code style |
| ARCHITECT | Code structure, patterns, tech debt | Security, documentation |
| NAVIGATOR | UI/UX, user workflows, accessibility | Backend logic, security |
| HERALD | README, guides, API docs, comments | Code quality, tests |
| OPERATOR | Deploy, migrations, logging, CI/CD | Feature logic, UX |

---

## Cross-Domain Issues

When an issue spans multiple domains:

1. The **primary** agent owns the finding
2. Add a note: `**Cross-ref:** May relate to {OTHER_AGENT} concerns`
3. Do NOT duplicate the finding in both reports

**Domain Priority** (for conflicts):
1. GUARDIAN (security) - always wins
2. SENTINEL (data integrity) - second priority
3. Others by relevance

---

## Review Scope

Agents should focus on:
- Source code in the repository
- Configuration files
- Documentation files
- Test files
- Build/deploy scripts

Agents should NOT:
- Make changes to the codebase
- Run destructive commands
- Access external systems
- Share sensitive information found during review

---

## Execution Rules

1. **Read First:** Always read this CONTRACTS.md before starting
2. **Stay in Lane:** Only report findings in your domain
3. **Be Specific:** Include file paths, line numbers, code snippets
4. **Be Actionable:** Every finding needs a clear recommendation
5. **Save Output:** Write findings to the specified output file
6. **Summary Line:** End with `COMPLETE: X BLOCKER, Y HIGH, Z MEDIUM, W LOW`

---

## Severity Guidelines by Agent

### SENTINEL (Quality)
- BLOCKER: Tests for payment/auth flows missing or failing
- HIGH: Coverage <60% on business logic
- MEDIUM: Coverage <80% on utilities
- LOW: Missing edge case tests

### GUARDIAN (Security)
- BLOCKER: SQL injection, auth bypass, exposed secrets
- HIGH: Missing input validation, weak auth
- MEDIUM: Outdated deps with known CVEs
- LOW: Security headers missing

### ARCHITECT (Code Health)
- BLOCKER: Circular dependencies breaking startup
- HIGH: No error handling on critical paths
- MEDIUM: Duplicated business logic
- LOW: Inconsistent naming conventions

### NAVIGATOR (UX)
- BLOCKER: Core user workflow completely broken
- HIGH: Confusing flow, no error feedback
- MEDIUM: Inconsistent UI patterns
- LOW: Minor visual polish

### HERALD (Documentation)
- BLOCKER: No installation instructions
- HIGH: API docs missing for public endpoints
- MEDIUM: Outdated screenshots/examples
- LOW: Typos, formatting issues

### OPERATOR (Production)
- BLOCKER: No rollback procedure documented
- HIGH: Missing health checks
- MEDIUM: Logs missing correlation IDs
- LOW: Docker image not optimized
