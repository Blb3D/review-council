# Code Conclave Agents

This document provides detailed documentation for each of the six specialized review agents in Code Conclave.

---

## Overview

Each agent operates independently with:
- **Defined scope**: Explicit boundaries and review areas
- **Industry standards**: Based on established frameworks (OWASP, ISO 25010, WCAG)
- **Evidence requirements**: Every finding must include code references
- **Severity classification**: Consistent rubrics aligned with risk standards

---

## SENTINEL — Quality & Compliance

**Role**: Quality assurance and test coverage analysis

### Focus Areas

| Area | Description |
|------|-------------|
| Test Coverage | Overall coverage percentages and gaps |
| Critical Paths | Auth, payment, and data mutation testing |
| Test Quality | Assertion strength and edge cases |
| Regression Risk | Changes that may break existing functionality |

### Standards Referenced

- ISO 25010 (Software Quality Model)
- Code coverage best practices (>80% for critical paths)
- Unit/Integration testing patterns

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| <30% overall coverage | BLOCKER |
| 0% coverage on auth/payment paths | BLOCKER |
| <50% overall coverage | HIGH |
| <80% on business logic | MEDIUM |
| Missing edge case tests | LOW |

### Compliance Mappings

SENTINEL findings map to:
- **CMMC**: AU (Audit), CA (Security Assessment)
- **FDA 820**: 820.30 (Design Controls), 820.70 (Process Controls)
- **FDA Part 11**: 11.10 (Closed Systems)

---

## GUARDIAN — Security

**Role**: Security vulnerability assessment

### Focus Areas

| Area | Description |
|------|-------------|
| Authentication | Auth bypass, session management, credential storage |
| Authorization | Access control, privilege escalation |
| Input Validation | Injection attacks (SQL, XSS, command) |
| Data Protection | Encryption, secrets exposure, data leakage |
| Dependencies | Vulnerable packages, supply chain risks |

### Standards Referenced

- OWASP Top 10
- OWASP ASVS (Application Security Verification Standard)
- CWE/SANS Top 25
- NIST Cybersecurity Framework

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| SQL injection, RCE possible | BLOCKER |
| Auth bypass vulnerability | BLOCKER |
| Hardcoded secrets in code | HIGH |
| Missing HTTPS enforcement | HIGH |
| Outdated dependencies with CVEs | MEDIUM-HIGH |
| Missing input sanitization | MEDIUM |
| Verbose error messages | LOW |

### Compliance Mappings

GUARDIAN findings map to:
- **CMMC**: AC (Access Control), IA (Identification/Auth), SC (System Protection)
- **FDA 820**: 820.30 (Design Controls)
- **FDA Part 11**: 11.10 (Controls), 11.300 (Electronic Signatures)

---

## ARCHITECT — Code Health

**Role**: Code quality and architectural analysis

### Focus Areas

| Area | Description |
|------|-------------|
| Technical Debt | Complexity, duplication, outdated patterns |
| Dependencies | Version currency, maintenance status |
| Architecture | Coupling, cohesion, separation of concerns |
| Performance | N+1 queries, memory leaks, inefficient algorithms |
| Maintainability | Code readability, documentation |

### Standards Referenced

- ISO 25010 (Maintainability characteristics)
- SOLID principles
- Clean Architecture patterns
- Language-specific style guides

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| Critical dependency EOL/unmaintained | HIGH |
| Circular dependencies blocking deployment | HIGH |
| >50% code duplication | MEDIUM |
| High cyclomatic complexity (>20) | MEDIUM |
| Missing error handling | MEDIUM |
| Minor style inconsistencies | LOW |

### Compliance Mappings

ARCHITECT findings map to:
- **CMMC**: CM (Configuration Management), MA (Maintenance)
- **FDA 820**: 820.30 (Design Controls), 820.70 (Process Controls)

---

## NAVIGATOR — UX Review

**Role**: User experience and accessibility analysis

### Focus Areas

| Area | Description |
|------|-------------|
| User Flows | Task completion paths, friction points |
| Error Handling | User-facing error messages, recovery paths |
| Accessibility | WCAG compliance, screen reader support |
| Responsiveness | Mobile support, viewport handling |
| Performance | Perceived performance, loading states |

### Standards Referenced

- WCAG 2.1 (Web Content Accessibility Guidelines)
- Nielsen's Usability Heuristics
- ISO 9241 (Ergonomics of human-system interaction)

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| Complete workflow broken | BLOCKER |
| WCAG Level A violations | HIGH |
| Critical feature unusable on mobile | HIGH |
| Confusing error messages | MEDIUM |
| Missing loading indicators | MEDIUM |
| Minor layout issues | LOW |

### Compliance Mappings

NAVIGATOR findings map to:
- **FDA 820**: 820.30 (Design Controls - user needs)
- **FDA Part 11**: 11.10 (Display of records)

---

## HERALD — Documentation

**Role**: Documentation completeness and accuracy

### Focus Areas

| Area | Description |
|------|-------------|
| API Documentation | Endpoint docs, request/response examples |
| Setup Guides | Installation, configuration, prerequisites |
| Architecture Docs | System design, data flow, integrations |
| Code Comments | Inline documentation, JSDoc/docstrings |
| User Documentation | How-to guides, tutorials, FAQs |

### Standards Referenced

- Documentation best practices
- API documentation standards (OpenAPI/Swagger)
- README conventions

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| No setup instructions | HIGH |
| API endpoints undocumented | HIGH |
| Outdated/incorrect docs | MEDIUM |
| Missing code comments on complex logic | MEDIUM |
| Typos in documentation | LOW |

### Compliance Mappings

HERALD findings map to:
- **CMMC**: AT (Awareness/Training), PS (Personnel Security)
- **FDA 820**: 820.40 (Document Controls), 820.180 (Records)
- **FDA Part 11**: 11.10 (Documentation requirements)

---

## OPERATOR — Production Readiness

**Role**: Deployment and operational readiness

### Focus Areas

| Area | Description |
|------|-------------|
| CI/CD | Build pipelines, deployment automation |
| Logging | Application logs, audit trails |
| Monitoring | Health checks, alerting, metrics |
| Configuration | Environment management, secrets handling |
| Disaster Recovery | Backup, rollback procedures |

### Standards Referenced

- 12-Factor App methodology
- SRE best practices
- DevOps maturity models

### Severity Rubric

| Condition | Severity |
|-----------|----------|
| No deployment automation | HIGH |
| Missing health checks | HIGH |
| No logging infrastructure | HIGH |
| Secrets in environment files committed | HIGH |
| Missing rollback procedures | MEDIUM |
| Insufficient monitoring | MEDIUM |
| Manual deployment steps | LOW |

### Compliance Mappings

OPERATOR findings map to:
- **CMMC**: AU (Audit), IR (Incident Response), CP (Contingency Planning)
- **FDA 820**: 820.75 (Process Validation), 820.90 (Nonconforming Product)
- **FDA Part 11**: 11.10 (Audit trails), 11.30 (Open Systems)

---

## Running Individual Agents

```powershell
# Run a single agent
.\cli\ccl.ps1 -Project "C:\myproject" -Agent sentinel
.\cli\ccl.ps1 -Project "C:\myproject" -Agent guardian

# Run multiple specific agents
.\cli\ccl.ps1 -Project "C:\myproject" -Agents sentinel,guardian,architect

# Resume from a specific agent
.\cli\ccl.ps1 -Project "C:\myproject" -StartFrom architect
```

---

## Customizing Agents

### Override for a Project

Create `.code-conclave/agents/<agent>.md` in your project:

```
my-project/
└── .code-conclave/
    └── agents/
        └── guardian.md  # Custom GUARDIAN instructions
```

### Create a New Agent

Add a file to `core/agents/`:

```markdown
# MYAGENT - Code Conclave

## Identity
You are MYAGENT, the [role] agent for Code Conclave.

## Mission
[What this agent reviews]

## Review Process
1. [Step 1]
2. [Step 2]

## Output Format
[Finding format]
```

Run with: `.\cli\ccl.ps1 -Project "..." -Agent myagent`

---

*Code Conclave v2.0*
