# Code Conclave: AI-Powered Code Review for CI/CD Pipelines

## Executive Summary

Code Conclave is an AI-powered code review orchestrator that integrates into CI/CD pipelines to automatically catch security vulnerabilities, quality issues, and compliance gaps before code reaches production. It runs as a pipeline step on every pull request, blocks merge when critical issues are found, and provides audit-ready compliance mapping.

---

## The Problem

| Challenge | Impact |
|-----------|--------|
| Manual code reviews miss security vulnerabilities | Average developer catches ~15% of defects in review |
| Reviews are inconsistent across team members | Quality varies by reviewer experience and workload |
| Compliance mapping is manual and audit-time-only | Gaps discovered late, expensive to remediate |
| No automated gate between "code written" and "code deployed" | Defects reach production |

---

## The Solution

Code Conclave deploys 6 specialized AI agents, each focused on a different domain:

| Agent | Focus | What It Catches |
|-------|-------|-----------------|
| **GUARDIAN** | Security | Hardcoded secrets, injection flaws, path traversal, dependency vulns |
| **SENTINEL** | Quality | Missing tests, low coverage, error handling gaps, code smells |
| **ARCHITECT** | Architecture | Scaling issues, pattern violations, coupling problems |
| **NAVIGATOR** | API/Integration | Broken contracts, missing validation, inconsistent interfaces |
| **HERALD** | Documentation | Missing docs, outdated comments, unclear APIs |
| **OPERATOR** | DevOps/Production | Deployment risks, missing monitoring, config issues |

---

## Live Proof: Code Conclave Reviewing Itself

We ran Code Conclave against its own codebase on a pull request. The results below are from a real GitHub Actions run, not a demo.

### Run #1: Initial Review

**GitHub Actions Run:** [#21713673929](https://github.com/Blb3D/review-council/actions/runs/21713673929)
**PR:** [#14](https://github.com/Blb3D/review-council/pull/14)

| Metric | Value |
|--------|-------|
| **Agents Run** | GUARDIAN, SENTINEL |
| **Duration** | 1 min 50 sec |
| **Input Tokens** | 123,948 |
| **Output Tokens** | 2,071 |
| **Estimated Cost** | ~$0.12 |
| **Findings** | 11 total |
| **Result** | **HOLD** (merge blocked) |

#### Findings Breakdown

| Severity | Count | Pipeline Effect |
|----------|-------|-----------------|
| BLOCKER | 2 | Build FAILED, merge blocked |
| HIGH | 4 | Build FAILED, merge blocked |
| MEDIUM | 3 | Noted (did not block merge) |
| LOW | 2 | Noted (did not block merge) |

#### Real Vulnerabilities Found

| ID | Issue | Severity | File |
|----|-------|----------|------|
| GUARDIAN-002 | Path traversal in dashboard API - `agentId` param allowed directory escape | BLOCKER | `dashboard/server.js:45` |
| GUARDIAN-006 | No input validation on POST endpoints - unsanitized JSON accepted | HIGH | `dashboard/server.js:95` |
| GUARDIAN-004 | WebSocket server bound to all interfaces with no auth | HIGH | `dashboard/server.js:180` |
| GUARDIAN-008 | Error messages could leak API keys in logs | MEDIUM | `cli/lib/ai-engine.ps1:125` |

These were legitimate security issues in a public repository. The AI identified them with file and line references.

### Run #2: After Fixes Applied

All BLOCKER and HIGH findings from Run #1 were fixed:
- Path traversal: `agentId` now validated against known agent whitelist
- Input validation: Type whitelisting, message length limits, progress bounds checking
- WebSocket: Server bound to `127.0.0.1` (localhost only)
- Error messages: API keys redacted from all error output

The re-review validates that fixes resolved the original findings.

---

## How It Works in CI/CD

### Pipeline Flow

```
Developer opens PR
        |
        v
Pipeline triggers automatically
        |
        v
Code Conclave reviews code (2-5 min)
        |
        v
Results published as test results
        |
    +---+---+
    |       |
  SHIP    HOLD
    |       |
  Merge   Merge
  allowed BLOCKED
```

### What Teams See

**In the PR:**
- Pass/fail check status directly on the pull request
- Comment with findings summary
- Downloadable full report as pipeline artifact

**In pipeline test results:**
- Each finding appears as a test case
- BLOCKER/HIGH = failed test (blocks merge)
- MEDIUM/LOW = passed test (noted but doesn't block)

---

## Cost Analysis

Based on real-world testing with a medium TypeScript project (~50 source files):

### Per PR Review

| Configuration | Time | Cost (Anthropic Claude) |
|--------------|------|--------------------------|
| 2 agents (security + quality) | ~2 min | ~$0.12 |
| 6 agents (full suite) | ~5 min | ~$0.51 |

### Monthly Estimates

| Scenario | PRs/Week | Config | Monthly Cost |
|----------|----------|--------|-------------|
| Small team (5 devs) | 20 | 2 agents | **$10** |
| Small team (5 devs) | 20 | 6 agents | **$41** |
| Medium team (15 devs) | 60 | 2 agents | **$31** |
| Medium team (15 devs) | 60 | 6 agents | **$122** |

### ROI Context

| Factor | Value |
|--------|-------|
| Average cost of a production bug | $5,000 - $25,000 (depending on severity) |
| Average findings per full review | 10-15 issues per PR |
| Code Conclave monthly cost (medium team) | $31 - $122 |
| Break-even | Preventing **1 production bug per quarter** pays for the tool |

---

## Compliance Integration

Code Conclave maps findings to regulatory controls automatically.

### Supported Standards

| Standard | Controls | Industry |
|----------|----------|----------|
| CMMC Level 2 | 110 | Defense / DoD |
| ITAR | 45 | Export Control |
| FDA 21 CFR Part 11 | ~30 | Pharma / Medical |
| FDA 820 QSR | ~40 | Medical Devices |
| ISO 13485 | ~50 | Medical Device QMS |
| ISO 9001 | ~50 | General QMS |
| AS9100 Rev D | ~60 | Aerospace |
| IATF 16949 | ~50 | Automotive |

### How Standards Apply to PRs

Standards are configured per-project in a YAML file:

```yaml
standards:
  required:     # Always checked on every PR
    - cmmc-l2
  default:      # Checked unless explicitly skipped
    - iso-9001-2015
  available:    # Checked when explicitly requested
    - itar
    - fda-21-cfr-11
```

When findings map to compliance controls, the report shows which regulations are impacted - providing continuous compliance evidence during development rather than at audit time.

---

## Installation

### GitHub Actions (5 minutes)

1. Add API key as repository secret (`ANTHROPIC_API_KEY`)
2. Copy workflow YAML into `.github/workflows/`
3. Set branch protection to require the check
4. Done - every PR is now reviewed

### Azure DevOps (15 minutes)

1. Import Code Conclave repo (or clone at build time)
2. Create variable group with API key
3. Add pipeline YAML to your project
4. Configure branch policy to require the build
5. Done - every PR is now reviewed

Full step-by-step guide: [ADO-INSTALLATION.md](ADO-INSTALLATION.md)

---

## AI Provider Options

| Provider | Quality | Data Residency | Best For |
|----------|---------|----------------|----------|
| **Anthropic Claude** | Highest | US/EU | Best review quality |
| **Azure OpenAI** | High | Your Azure region | Enterprise data requirements |
| **OpenAI** | High | US | Alternative cloud option |
| **Ollama** | Good | On-premise | Air-gapped / classified environments |

For environments where data cannot leave the network, Ollama runs entirely on-premise with no external API calls.

---

## Key Differentiators

| Feature | Code Conclave | Traditional SAST | Manual Review |
|---------|--------------|-------------------|---------------|
| Understands business logic | Yes | No | Yes |
| Consistent across reviewers | Yes | Yes | No |
| Compliance mapping | Built-in | Add-on | Manual |
| Setup time | 15 min | Days-weeks | N/A |
| Cost per review | $0.12-0.51 | License-based | Developer time |
| Finds architectural issues | Yes | No | Sometimes |
| Catches documentation gaps | Yes | No | Sometimes |

---

## Next Steps

1. **Demo access**: The tool is running on [github.com/Blb3D/review-council](https://github.com/Blb3D/review-council) with real PR reviews
2. **Pilot**: Pick one team's repo, add the workflow, run for 2 weeks
3. **Measure**: Track findings caught, time saved, bugs prevented
4. **Scale**: Roll out to remaining teams via ADO pipeline template

---

*Generated from live Code Conclave data - February 2026*
