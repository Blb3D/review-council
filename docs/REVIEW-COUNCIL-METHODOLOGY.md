# Code Conclave: Methodology & Validation Framework

**Version:** 2.0
**Date:** February 2026
**Classification:** Internal

---

## Executive Summary

Code Conclave is an AI-powered code review system that performs systematic, evidence-based analysis across six specialized domains. Unlike general-purpose AI assistants that may generate vague or unsubstantiated feedback, Code Conclave operates with:

1. **Defined scope** - Each agent has explicit boundaries and review areas
2. **Industry-standard criteria** - Based on established frameworks (OWASP, ISO 25010, WCAG)
3. **Evidence requirements** - Every finding must include code references, commands, or artifacts
4. **Reproducible checks** - Findings can be verified by running the same commands/inspections
5. **Severity classification** - Consistent rubrics aligned with risk assessment standards

This document provides transparency into how Code Conclave operates and why its findings should be trusted.

---

## The Six Agents

### 1. SENTINEL — Quality & Compliance

**Domain:** Test coverage, critical path validation, quality assurance

**Standards Referenced:**
- ISO 25010 (Software Quality Model)
- Code coverage best practices (>80% for critical paths)
- Unit/Integration testing patterns

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| Overall test coverage | `pytest --cov` / `npm test --coverage` | Coverage report percentages |
| Critical path coverage | Trace auth, payment, data mutation paths | File/function coverage stats |
| Test quality | Manual review of assertions | Code snippets showing weak tests |
| Edge case coverage | Review for null/empty/boundary tests | Missing test scenarios |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| <30% overall coverage | BLOCKER |
| 0% coverage on auth/payment/critical path | BLOCKER |
| <50% overall coverage | HIGH |
| <80% on business logic | MEDIUM |

**Why Trust It:**
SENTINEL runs actual coverage tools and reports real percentages. Findings include specific file paths and coverage numbers that can be independently verified by running `pytest --cov` or equivalent.

---

### 2. GUARDIAN — Security

**Domain:** Vulnerability detection, authentication review, secrets management

**Standards Referenced:**
- OWASP Top 10 (2021)
- CWE (Common Weakness Enumeration)
- NIST Secure Software Development Framework

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| SQL Injection | Pattern matching for string interpolation in queries | Code snippets with line numbers |
| Authentication | Review of password hashing, JWT implementation | Algorithm identification |
| Hardcoded secrets | `grep` for API keys, passwords, tokens | Matched patterns and locations |
| Dependency vulnerabilities | `pip-audit`, `npm audit`, `safety check` | CVE IDs and severity scores |
| Input validation | Review of request handlers | Missing validation points |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| SQL injection possible | BLOCKER |
| Hardcoded production secret | BLOCKER |
| Auth bypass possible | BLOCKER |
| Missing auth on admin endpoint | BLOCKER |
| Weak password hashing (MD5/SHA1) | HIGH |
| Critical CVE in dependency | HIGH |
| CORS allows all origins in production | MEDIUM |

**Why Trust It:**
GUARDIAN findings reference specific OWASP categories and CWE IDs. Vulnerability patterns are matched against known attack vectors. Dependency audits use industry-standard tools that check against the National Vulnerability Database (NVD).

---

### 3. ARCHITECT — Code Health

**Domain:** Technical debt, code structure, maintainability, performance

**Standards Referenced:**
- SOLID principles
- Clean Code (Robert Martin)
- Martin Fowler's Refactoring Patterns
- Database query optimization best practices

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| File size (God files) | `wc -l` on source files | Line counts per file |
| Circular dependencies | Import graph analysis | Dependency chains |
| Error handling | Pattern matching for bare `except:` | Code snippets |
| N+1 queries | Review of ORM usage patterns | Query patterns in loops |
| Technical debt markers | `grep` for TODO/FIXME/HACK | Count and locations |
| API consistency | Review of endpoint patterns | Inconsistency examples |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| Circular dependency causing failures | BLOCKER |
| No error handling on critical path | HIGH |
| N+1 queries in high-traffic endpoint | HIGH |
| 1000+ line file | HIGH |
| Duplicated business logic | MEDIUM |
| Bare except clauses | MEDIUM |

**Why Trust It:**
ARCHITECT findings are based on measurable metrics (line counts, function counts, cyclomatic complexity) and established refactoring patterns. Each finding points to specific files and line numbers that can be manually inspected.

---

### 4. NAVIGATOR — UX Review

**Domain:** User experience, accessibility, error handling, UI consistency

**Standards Referenced:**
- WCAG 2.1 (Web Content Accessibility Guidelines)
- Nielsen Norman Group UX Heuristics
- Material Design / Human Interface Guidelines principles

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| Error message quality | Review of user-facing messages | Before/after examples |
| Loading states | Check for async feedback | Missing spinner/progress instances |
| Empty states | Review of zero-data scenarios | Components lacking empty handling |
| Form usability | Check labels, validation, tab order | Specific form issues |
| Accessibility | Check for alt text, ARIA, contrast | HTML snippets |
| Responsive design | Viewport and touch target review | CSS/layout issues |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| Core workflow broken | BLOCKER |
| User cannot complete critical action | BLOCKER |
| No error feedback on failures | HIGH |
| Confusing/misleading UI | HIGH |
| Missing loading indicators | MEDIUM |
| Minor accessibility gaps | MEDIUM |

**Why Trust It:**
NAVIGATOR findings reference specific components and user flows. Accessibility issues cite WCAG success criteria. Error handling issues include code showing the gap between failure and user feedback.

---

### 5. HERALD — Documentation

**Domain:** README, API docs, installation guides, code comments

**Standards Referenced:**
- README best practices (GitHub community standards)
- OpenAPI/Swagger for API documentation
- Google Developer Documentation Style Guide
- Diataxis documentation framework

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| README completeness | Checklist assessment | Missing sections listed |
| Installation docs | Step-by-step verification | Missing steps identified |
| API documentation | Endpoint coverage analysis | Undocumented endpoints |
| Code documentation | Docstring coverage | Functions lacking docs |
| Configuration docs | Env var documentation | Undocumented variables |
| Changelog | Format and recency check | Missing entries |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| No README | BLOCKER |
| No installation instructions | BLOCKER |
| API endpoints undocumented | HIGH |
| Outdated/wrong instructions | HIGH |
| Missing getting started guide | MEDIUM |
| No code comments on complex logic | MEDIUM |

**Why Trust It:**
HERALD uses objective checklists based on widely-adopted documentation standards. Findings identify specific missing sections or outdated content with clear remediation paths.

---

### 6. OPERATOR — Production Readiness

**Domain:** Deployment, monitoring, migrations, operational safety

**Standards Referenced:**
- 12-Factor App methodology
- Site Reliability Engineering (Google SRE book)
- AWS/Azure/GCP Well-Architected Frameworks
- Database migration best practices

**What It Checks:**

| Check | Method | Evidence Type |
|-------|--------|---------------|
| Deployment docs | Presence and completeness | Missing procedures |
| Migration safety | Review for destructive operations | Risky migration code |
| Health checks | Endpoint existence and depth | Missing or shallow checks |
| Logging quality | Pattern review for context/PII | Log statement examples |
| Rollback procedures | Documentation review | Missing rollback steps |
| Environment config | Env var audit | Undocumented variables |

**Severity Rubric:**

| Condition | Severity |
|-----------|----------|
| No rollback procedure | BLOCKER |
| Destructive migration without safety | BLOCKER |
| No health check endpoint | HIGH |
| Missing deployment docs | HIGH |
| No structured logging | MEDIUM |
| Version mismatch | MEDIUM |

**Why Trust It:**
OPERATOR checks are based on industry-standard operational practices from Google SRE, AWS Well-Architected, and 12-Factor methodology. Findings identify concrete operational risks with specific remediation steps.

---

## Finding Format

Every finding follows a consistent structure:

```markdown
### [AGENT]-[NUMBER]: [Title] [SEVERITY]

**Location:** `path/to/file.py:line_number`
**Effort:** S (<1hr) | M (1-4hrs) | L (>4hrs)

**Issue:**
Clear description of the problem and why it matters.

**Evidence:**
Concrete proof - code snippets, command output, screenshots.

**Recommendation:**
Specific, actionable steps to resolve the issue.
```

This format ensures:
- **Traceability** - Every finding points to specific code
- **Verifiability** - Evidence can be independently confirmed
- **Actionability** - Clear effort estimate and remediation steps
- **Prioritization** - Severity guides triage decisions

---

## Verdict Calculation

After all agents complete, Code Conclave issues a verdict:

| Verdict | Condition | Meaning |
|---------|-----------|---------|
| **SHIP** | 0 blockers, ≤3 high | Safe to release |
| **CONDITIONAL** | 0 blockers, >3 high | Review HIGH items first |
| **HOLD** | ≥1 blocker | Do not release until resolved |

This provides a clear, defensible go/no-go decision based on aggregate findings.

---

## Validation & Quality Assurance

### How to Verify Findings

1. **Run the same commands** - Coverage tools, security scanners, grep patterns
2. **Inspect referenced files** - Line numbers and code snippets are exact
3. **Check against standards** - OWASP IDs, CWE numbers, WCAG criteria are real
4. **Test the fix** - Apply recommendations and re-run the review

### What Prevents Hallucination

| Safeguard | How It Works |
|-----------|--------------|
| Structured prompts | Agents have explicit checklists and review areas |
| Evidence requirements | Findings without code/output are invalid |
| Command-based checks | Many checks run actual tools (coverage, audit, grep) |
| Reproducibility | Anyone can run the same review and compare |
| Human review | Final verdict is a recommendation, not an autonomous action |

### Limitations

Code Conclave is a tool, not a replacement for human judgment:

- **Context gaps** - May not understand business-specific requirements
- **False positives** - Some findings may be intentional trade-offs
- **Evolving standards** - Security best practices change over time
- **Scope boundaries** - Only reviews what's in the codebase, not infrastructure

Human experts should review findings, prioritize based on business context, and make final decisions.

---

## Comparison to Traditional Code Review

| Aspect | Manual Review | Code Conclave |
|--------|---------------|---------------|
| Coverage | Depends on reviewer expertise | All six domains, every time |
| Consistency | Varies by reviewer, day, workload | Same criteria, same format |
| Speed | Hours to days | Minutes |
| Evidence | Often verbal/implicit | Always documented with code refs |
| Standards | Varies by team | Industry frameworks (OWASP, WCAG, etc.) |
| Scalability | Linear with team size | Parallelizable |

Code Conclave augments human review by ensuring baseline coverage across all domains, freeing human reviewers to focus on business logic, architecture decisions, and nuanced judgment calls.

---

## Appendix: Standards & Frameworks Referenced

| Standard | Domain | URL |
|----------|--------|-----|
| OWASP Top 10 | Security | https://owasp.org/Top10/ |
| CWE | Security | https://cwe.mitre.org/ |
| WCAG 2.1 | Accessibility | https://www.w3.org/WAI/WCAG21/quickref/ |
| ISO 25010 | Software Quality | https://iso25000.com/index.php/en/iso-25000-standards/iso-25010 |
| 12-Factor App | Operations | https://12factor.net/ |
| Google SRE | Operations | https://sre.google/sre-book/table-of-contents/ |
| NIST SSDF | Security | https://csrc.nist.gov/publications/detail/sp/800-218/final |

---

**Document Owner:** Quality Engineering
**Last Updated:** February 2026
**Review Cycle:** Quarterly
