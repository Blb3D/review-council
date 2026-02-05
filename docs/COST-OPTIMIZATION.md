# Cost Optimization Guide

Strategies and configuration for minimizing Code Conclave costs without sacrificing review quality.

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Real-World Test Results](#real-world-test-results)
- [Cost Projections](#cost-projections)
- [Diff-Scoped Scanning](#diff-scoped-scanning)
- [Prompt Caching](#prompt-caching)
- [Model Tiering](#model-tiering)
- [Configuration Reference](#configuration-reference)
- [Reading Token Usage Output](#reading-token-usage-output)
- [Provider Decision Guide](#provider-decision-guide)

---

## Executive Summary

Code Conclave includes three cost optimization layers that, when combined, reduce AI provider costs by up to 94%. All three are enabled by default and require no configuration changes to existing pipelines.

### The Three Layers

**Diff-Scoped Scanning** reviews only the files changed in a pull request instead of the entire codebase. In CI/CD pipelines, this happens automatically. A typical PR touches 5-10 files, not 50+, so the AI processes far less code.

**Prompt Caching** sends shared project context (contracts, file tree, source code) to the AI provider once and reuses it across all six agents. Providers discount cached input tokens between 50% and 90%, depending on the provider.

**Model Tiering** assigns each agent a "primary" or "lite" model. Security, quality, and architecture agents use the full model. Documentation, UX, and operations agents use a smaller, cheaper model that is still effective for their tasks.

### Before and After

| Metric | Before Optimization | After All Three Layers |
|--------|--------------------|-----------------------|
| **Per-PR cost (Anthropic)** | ~$2.50 | ~$0.15 - $0.61 |
| **Per-PR cost (Azure/OpenAI)** | ~$1.60 | ~$0.08 - $0.32 |
| **Monthly cost (65 devs, 3 PR/wk)** | ~$2,100 (Anthropic) | ~$125 - $515 (Anthropic) |
| **Monthly cost (65 devs, 3 PR/wk)** | ~$1,350 (Azure) | ~$68 - $270 (Azure) |

*Ranges reflect PR size: small PRs (2-3 files) at the low end, large PRs (15+ files) at the high end.*

---

## Real-World Test Results

The following data comes from actual API usage during development, measured via the Anthropic billing dashboard.

### Full 6-Agent Review (Large PR: 16 files, 147KB, 86K token context)

**Anthropic (Actual Costs):**

| Model | Input (no cache) | Cache Write | Cache Read | Output | Subtotal |
|-------|-----------------|-------------|------------|--------|----------|
| Sonnet 4 (3 agents) | $0.01 | $0.32 | $0.05 | $0.08 | **$0.46** |
| Haiku 4.5 (3 agents) | $0.00 | $0.09 | $0.01 | $0.05 | **$0.15** |
| **Total** | $0.01 | $0.41 | $0.06 | $0.13 | **$0.61** |

**Azure OpenAI (Equivalent Costs):**

| Model | Input (no cache) | Cache (50% off) | Output | Subtotal |
|-------|-----------------|-----------------|--------|----------|
| GPT-4o (3 agents) | $0.01 | $0.11 | $0.06 | **$0.18** |
| GPT-4o-mini (3 agents) | $0.00 | $0.01 | $0.01 | **$0.02** |
| **Total** | $0.01 | $0.12 | $0.07 | **$0.20** |

*Azure costs are ~67% lower due to cheaper caching (50% vs 75% write premium) and lower output rates.*

### Token Distribution (Observed)

| Token Type | Sonnet 4 | Haiku 4.5 | Total |
|------------|----------|-----------|-------|
| Input (non-cached) | 3,692 | 4,383 | 8,075 |
| Cache write | 86,198 | 86,198 | 172,396 |
| Cache read | 172,396 | 172,396 | 344,792 |
| Output | 5,509 | 12,152 | 17,661 |

The cache write happens once per model (first agent), then subsequent agents get cache reads at 90% discount (Anthropic) or 50% discount (Azure/OpenAI).

### Cost by PR Size (Anthropic)

| PR Size | Files Changed | Context Size | Cost/PR |
|---------|---------------|--------------|---------|
| Small | 2-3 files | ~10K tokens | ~$0.15 |
| Typical | 5-8 files | ~25K tokens | ~$0.25 |
| Large | 10-15 files | ~50K tokens | ~$0.45 |
| Very Large | 15+ files | ~86K tokens | ~$0.61 |

### Cost by PR Size (Azure OpenAI)

| PR Size | Files Changed | Context Size | Cost/PR |
|---------|---------------|--------------|---------|
| Small | 2-3 files | ~10K tokens | ~$0.08 |
| Typical | 5-8 files | ~25K tokens | ~$0.13 |
| Large | 10-15 files | ~50K tokens | ~$0.24 |
| Very Large | 15+ files | ~86K tokens | ~$0.32 |

### Without Optimization (Baseline)

Running the same 6-agent review without caching, tiering, or diff-scoping:

| | Anthropic | Azure OpenAI |
|---|-----------|--------------|
| All tokens at full price | ~$2.50 | ~$1.60 |
| All agents use primary model | (no Haiku savings) | (no mini savings) |
| **Optimized cost** | **$0.61** | **$0.32** |
| **Savings** | **76%** | **80%** |

*Savings improve significantly on typical/small PRs where cache write costs are proportionally lower.*

---

## Cost Projections

### By Team Size (Anthropic, 3 PRs/dev/week, typical PR size)

| Developers | PRs/Month | Monthly Cost | Per-PR Cost |
|-----------|----------|-------------|------------|
| 10 | 130 | ~$33 | ~$0.25 |
| 30 | 390 | ~$98 | ~$0.25 |
| 65 | 845 | ~$211 | ~$0.25 |
| 100 | 1,300 | ~$325 | ~$0.25 |

### By Team Size (Azure OpenAI, 3 PRs/dev/week, typical PR size)

| Developers | PRs/Month | Monthly Cost | Per-PR Cost |
|-----------|----------|-------------|------------|
| 10 | 130 | ~$17 | ~$0.13 |
| 30 | 390 | ~$51 | ~$0.13 |
| 65 | 845 | ~$110 | ~$0.13 |
| 100 | 1,300 | ~$169 | ~$0.13 |

### Optimization Layers (Cumulative Impact, Anthropic — Typical PR)

| Configuration | Per-PR Cost | Monthly (65 devs) | Savings |
|--------------|------------|-------------------|---------|
| Baseline (full scan, no cache, no tiering) | ~$2.50 | ~$2,100 | -- |
| + Diff-scoped scanning | ~$0.80 | ~$676 | 68% |
| + Prompt caching | ~$0.40 | ~$338 | 84% |
| + Model tiering | ~$0.25 | ~$211 | 90% |

### Optimization Layers (Cumulative Impact, Azure OpenAI — Typical PR)

| Configuration | Per-PR Cost | Monthly (65 devs) | Savings |
|--------------|------------|-------------------|---------|
| Baseline (full scan, no cache, no tiering) | ~$1.60 | ~$1,350 | -- |
| + Diff-scoped scanning | ~$0.40 | ~$338 | 75% |
| + Prompt caching | ~$0.22 | ~$186 | 86% |
| + Model tiering | ~$0.13 | ~$110 | 92% |

---

## Diff-Scoped Scanning

### How It Works

In CI/CD pipelines, Code Conclave detects the pull request's target branch and uses `git diff` to identify only the changed files. The AI receives the changed file contents and the unified diff instead of the entire repository.

| Mode | Trigger | Files Scanned | Typical Size |
|------|---------|---------------|-------------|
| Full scan | No base branch detected, local dev | Up to 50 files, 500KB max | ~200-500KB |
| Diff-scoped | CI environment with base branch | Changed files only, 200KB max | ~10-50KB |

### Automatic Detection

Code Conclave reads CI environment variables to find the base branch:

| CI System | Environment Variable | Example Value |
|-----------|---------------------|---------------|
| GitHub Actions | `GITHUB_BASE_REF` | `main` |
| Azure DevOps | `SYSTEM_PULLREQUEST_TARGETBRANCH` | `refs/heads/main` |

No configuration is needed. If you are running in one of these CI systems on a pull request, diff-scoping activates automatically.

### Manual Control

Use `-BaseBranch` to specify the base branch explicitly:

```powershell
# Force diff-scoped scan against develop
ccl -Project . -BaseBranch develop -CI

# Force diff-scoped scan locally
ccl -Project . -BaseBranch main
```

### Safeguards

Large diffs are handled gracefully to prevent excessive token usage:

| Limit | Default | Purpose |
|-------|---------|---------|
| Max diff size | 100 KB | Truncates unified diff beyond this |
| Max content size | 200 KB | Total size of changed file contents |
| Max file size | 50 KB | Skips individual files larger than this |

If no base branch is detected (for example, running locally without `-BaseBranch`), Code Conclave falls back to a full scan. The full-scan limits of 50 files and 500KB remain unchanged.

### Verifying Diff-Scoping

When diff-scoping is active, the console output shows:

```
  Diff-scoped: 7 changed files (42 KB) against origin/main
```

When falling back to full scan:

```
  Full scan: 34 files (285 KB)
```

---

## Prompt Caching

### How It Works

When Code Conclave runs multiple agents, all agents receive the same project context: the CONTRACTS document, the file tree, and the source file contents (or diff). Instead of sending this context separately with each agent request, Code Conclave builds it once and passes it as a shared prefix.

AI providers recognize repeated prefixes and cache them server-side. After the first agent pays the full input cost, subsequent agents read from the cache at a steep discount.

### Provider-Specific Behavior

| Provider | Mechanism | Cache Write Cost | Cache Read Discount | Setup Required |
|----------|-----------|-----------------|--------------------|----|
| Anthropic | Explicit `cache_control` on shared block | 25% premium on first write | 90% off on reads | None |
| Azure OpenAI | Automatic prefix caching | No extra charge | 50% off (Standard), up to 100% off (PTU) | None |
| OpenAI | Automatic prefix caching | No extra charge | 50% off | None |
| Ollama | N/A (local, free) | Free | Free | None |

**Anthropic:** The shared context block is sent with an explicit `cache_control: { type: "ephemeral" }` marker. The first agent incurs a 25% write premium, but subsequent agents read from cache at 90% off. With 6 agents, this is a significant net savings.

**Azure OpenAI and OpenAI:** Caching is fully automatic. The API version is set to `2024-10-01-preview` (Azure) to enable cached token reporting. The provider recognizes repeated prefixes and applies the discount without any code changes.

**Ollama:** Local and free. No caching mechanism is needed.

### Cache Effectiveness

Caching is most effective when running multiple agents in a single review. The more agents you run, the greater the savings:

| Agents | Cache Writes | Cache Reads | Effective Discount (Anthropic) |
|--------|-------------|-------------|-------------------------------|
| 1 | 1 | 0 | 0% (no benefit) |
| 2 | 1 | 1 | ~45% |
| 3 | 1 | 2 | ~60% |
| 6 | 1 | 5 | ~75% |

---

## Model Tiering

### How It Works

Each agent has a `tier` field that determines which AI model it uses. Agents whose work requires deep reasoning (security analysis, code quality, architecture) use the "primary" tier and the full model. Agents whose work is more pattern-based (documentation, UX, operations) use the "lite" tier and a smaller, cheaper model.

### Default Tiers

| Agent | Default Tier | Rationale |
|-------|-------------|-----------|
| GUARDIAN (Security) | primary | Security analysis requires deep reasoning |
| SENTINEL (Quality) | primary | Test coverage and risk assessment are critical |
| ARCHITECT (Code Health) | primary | Architecture decisions need thorough analysis |
| NAVIGATOR (UX) | lite | UI pattern detection is effective with smaller models |
| HERALD (Documentation) | lite | Documentation review is largely pattern-based |
| OPERATOR (Production) | lite | Ops checks follow established checklists |

### Tier-to-Model Mapping

| Provider | Primary Model | Lite Model |
|----------|--------------|------------|
| Anthropic | claude-sonnet-4-20250514 | claude-haiku-4-5-20251001 |
| Azure OpenAI | deployment (gpt-4o) | lite_deployment (gpt-4o-mini) |
| OpenAI | gpt-4o | gpt-4o-mini |
| Ollama | (configured model) | (same -- local, free) |

### Fallback Behavior

If a lite model or deployment is not configured, the agent falls back to the primary model silently. No error is raised. This means tiering is always safe to enable, even if you have not set up a lite deployment.

### Overriding Tiers

Override the default tier for any agent in your project config:

```yaml
# .code-conclave/config.yaml
agents:
  # Promote operator to primary for a safety-critical project
  operator:
    tier: primary

  # Demote architect to lite for a small internal tool
  architect:
    tier: lite
```

---

## Configuration Reference

### Anthropic

```yaml
ai:
  provider: anthropic
  anthropic:
    model: claude-sonnet-4-20250514           # Primary tier model
    lite_model: claude-haiku-4-5-20251001     # Lite tier model
    api_key_env: ANTHROPIC_API_KEY
    max_tokens: 16000
```

No additional setup is required. Caching and tiering work out of the box.

### Azure OpenAI

```yaml
ai:
  provider: azure-openai
  azure-openai:
    endpoint: https://your-resource.openai.azure.com/
    deployment: gpt-4o                   # Primary tier deployment
    lite_deployment: gpt-4o-mini         # Lite tier deployment (optional, empty by default)
    api_version: "2024-10-01-preview"    # Required for cached token reporting
    api_key_env: AZURE_OPENAI_KEY
    max_tokens: 16000
```

To use model tiering with Azure OpenAI, you need a second deployment in your Azure OpenAI resource (see [Installation Guide](INSTALLATION.md) for step-by-step instructions). If `lite_deployment` is left empty, lite-tier agents use the primary deployment instead.

### OpenAI

```yaml
ai:
  provider: openai
  openai:
    model: gpt-4o                # Primary tier model
    lite_model: gpt-4o-mini      # Lite tier model
    api_key_env: OPENAI_API_KEY
    max_tokens: 16000
```

No additional setup is required. Caching and tiering work out of the box.

### Ollama

```yaml
ai:
  provider: ollama
  ollama:
    endpoint: http://localhost:11434
    model: llama3.1:70b
    max_tokens: 8000
```

Ollama is local and free. Tiering and caching do not apply.

### Diff-Scoping (CLI)

```powershell
# Explicit base branch
ccl -Project . -BaseBranch main -CI

# Auto-detect (default in CI)
ccl -Project . -CI
```

### Agent Tiers (per-agent config)

```yaml
agents:
  guardian:
    tier: primary     # "primary" or "lite"
  sentinel:
    tier: primary
  architect:
    tier: primary
  navigator:
    tier: lite
  herald:
    tier: lite
  operator:
    tier: lite
```

---

## Reading Token Usage Output

### Per-Agent Output

After each agent completes, the console shows token usage:

```
  [OK] Completed in 1.2 minutes
  [INFO] Tokens: 4521 in / 3842 out (cache write: 3800)
```

The first agent typically shows a `cache write` indicating the shared context was cached. Subsequent agents show:

```
  [OK] Completed in 0.8 minutes
  [INFO] Tokens: 4521 in / 3100 out (cache read: 3800)
```

The `cache read` confirms the provider served the shared context from cache.

### Cumulative Summary

After all agents complete, a total is displayed:

```
  Tokens: 27126 input, 22400 output (19000 cached)
```

This summary shows:
- **input**: Total input tokens across all agents
- **output**: Total output tokens across all agents
- **cached**: How many input tokens were served from cache (lower cost)

### Interpreting Cost

To estimate cost from token output, use this reference:

| Provider | Model | Input | Cache Write | Cache Read | Output |
|----------|-------|-------|-------------|------------|--------|
| Anthropic | Sonnet 4 | $3.00/M | $3.75/M (+25%) | $0.30/M (90% off) | $15.00/M |
| Anthropic | Haiku 4.5 | $0.80/M | $1.00/M (+25%) | $0.08/M (90% off) | $4.00/M |
| Azure/OpenAI | GPT-4o | $2.50/M | $2.50/M (no premium) | $1.25/M (50% off) | $10.00/M |
| Azure/OpenAI | GPT-4o-mini | $0.15/M | $0.15/M (no premium) | $0.075/M (50% off) | $0.60/M |
| Ollama | Any | Free | Free | Free | Free |

*Anthropic charges a 25% premium for cache writes but gives 90% discount on reads. Azure/OpenAI has no write premium but only 50% read discount. Net effect: Anthropic is cheaper when you have many cache reads (multiple agents), Azure is cheaper for single-agent runs.*

---

## Provider Decision Guide

### When to Use Each Provider

| Consideration | Recommended Provider |
|---------------|---------------------|
| Best review quality | Anthropic |
| Lowest cloud cost (with tiering) | Azure OpenAI or OpenAI |
| Data must stay in your Azure tenant | Azure OpenAI |
| No cloud dependency | Ollama |
| Zero cost | Ollama |
| Enterprise compliance requirements | Azure OpenAI |

### Cost Comparison (Per PR, All Optimizations Enabled)

| Provider | Primary Model | Lite Model | Small PR | Typical PR | Large PR |
|----------|--------------|------------|----------|------------|----------|
| Anthropic | Sonnet 4 | Haiku 4.5 | ~$0.15 | ~$0.25 | ~$0.61 |
| Azure OpenAI | GPT-4o | GPT-4o-mini | ~$0.08 | ~$0.13 | ~$0.32 |
| OpenAI | GPT-4o | GPT-4o-mini | ~$0.08 | ~$0.13 | ~$0.32 |
| Ollama | Any local | Any local | Free | Free | Free |

*Small PR = 2-3 files, Typical PR = 5-8 files, Large PR = 15+ files*

### Decision Tree

1. **Do you need zero cost?** Use Ollama. Review quality depends on the local model, but there are no API charges.

2. **Does your data need to stay within your Azure subscription?** Use Azure OpenAI. Deploy GPT-4o and optionally GPT-4o-mini for tiering.

3. **Do you want the highest review quality?** Use Anthropic. Sonnet 4 provides the most thorough security and architecture analysis.

4. **Do you want the lowest cloud cost?** Use Azure OpenAI or OpenAI with GPT-4o-mini for lite-tier agents. At ~$0.13 per typical PR, the cost is negligible even at scale.

---

*Last updated: 2026-02-05 — Includes real-world test data from Anthropic API billing dashboard.*
