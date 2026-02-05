# Operations Guide

Production deployment, monitoring, and operational procedures for Code Conclave.

---

## Table of Contents

- [Deployment](#deployment)
- [Rollback Procedures](#rollback-procedures)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## Deployment

### Prerequisites

- PowerShell 7.0+
- Git (for diff-scoping features)
- AI provider API key (Anthropic, Azure OpenAI, OpenAI, or Ollama)

### Installation

```bash
# Clone the repository
git clone https://github.com/Blb3D/review-council.git code-conclave
cd code-conclave

# Verify installation
pwsh ./cli/ccl.ps1 --help
```

### Version Pinning

For production pipelines, pin to a specific version:

```yaml
# GitHub Actions
- uses: actions/checkout@v4
  with:
    repository: Blb3D/review-council
    ref: v1.0.0  # Pin to specific version
```

---

## Rollback Procedures

### Scenario 1: Bad Review Output

If Code Conclave produces incorrect or misleading findings:

1. **Identify the issue**: Check the agent output in `.code-conclave/reviews/`
2. **Revert to previous version**:
   ```bash
   cd /path/to/code-conclave
   git checkout v0.9.0  # Previous known-good version
   ```
3. **Re-run the review**:
   ```powershell
   ./cli/ccl.ps1 -Project /path/to/your/project -CI
   ```

### Scenario 2: CI Pipeline Failure

If the Code Conclave step fails in CI:

1. **Check exit codes**:
   - `0`: SHIP (passed)
   - `1`: HOLD (blockers found - expected behavior)
   - `2`: CONDITIONAL (warnings only)
   - `10+`: Error conditions (see [Exit Codes](CI-CD.md#exit-codes))

2. **Temporary bypass** (use sparingly):
   ```yaml
   # GitHub Actions
   - name: Run Code Conclave
     continue-on-error: true  # Allow pipeline to continue
   ```

3. **Skip specific agents**:
   ```powershell
   ./cli/ccl.ps1 -Project . -Agents guardian,sentinel  # Run only critical agents
   ```

### Scenario 3: API Provider Issues

If the AI provider is unavailable or rate-limited:

1. **Check provider status**: Verify the API endpoint is reachable
2. **Switch providers** (if configured):
   ```yaml
   # In .code-conclave/config.yaml
   ai:
     provider: azure-openai  # Switch from anthropic
   ```
3. **Use DryRun mode** for pipeline validation:
   ```powershell
   ./cli/ccl.ps1 -Project . -DryRun -CI
   ```

### Scenario 4: Configuration Rollback

If a config change causes issues:

1. **Restore default config**:
   ```powershell
   # Delete project config to use defaults
   Remove-Item .code-conclave/config.yaml

   # Re-initialize with defaults
   ./cli/ccl.ps1 -Init -Project .
   ```

2. **Compare configs**:
   ```powershell
   # View effective config
   ./cli/ccl.ps1 -Project . -ShowConfig
   ```

---

## Production Rollback Procedures

### GitHub Actions Rollback

If Code Conclave causes issues in your GitHub Actions workflow:

**Step 1: Identify the problem commit**
```bash
# Find when the issue started
gh run list --workflow=code-review.yml --limit=10
gh run view <run-id> --log-failed
```

**Step 2: Rollback options**

Option A - Pin to previous working version:
```yaml
# .github/workflows/code-review.yml
- name: Checkout Code Conclave
  uses: actions/checkout@v4
  with:
    repository: Blb3D/review-council
    ref: v1.0.0  # Pin to last known good version
    path: .conclave
```

Option B - Disable temporarily:
```yaml
# Add condition to skip
- name: Run Code Conclave
  if: github.event.pull_request.draft == false && env.SKIP_CONCLAVE != 'true'
```

Option C - Revert workflow changes:
```bash
git revert <commit-that-broke-workflow>
git push origin main
```

**Step 3: Verify rollback**
```bash
# Trigger a test run
gh workflow run code-review.yml --ref main

# Check status
gh run list --workflow=code-review.yml --limit=1
```

**Step 4: Notify team**
```bash
# Post to PR if applicable
gh pr comment <pr-number> --body "Code Conclave temporarily disabled due to [issue]. Tracking in #<issue-number>"
```

### Azure DevOps Rollback

If Code Conclave causes issues in your Azure DevOps pipeline:

**Step 1: Identify the failing build**
```bash
# View recent builds
az pipelines runs list --pipeline-name "Code-Review" --top 10

# Get failure details
az pipelines runs show --id <run-id>
```

**Step 2: Rollback options**

Option A - Pin to previous version in pipeline YAML:
```yaml
# azure-pipelines.yml
variables:
  CONCLAVE_VERSION: 'v1.0.0'  # Pin to last working version

steps:
- checkout: git://YourProject/review-council@$(CONCLAVE_VERSION)
  path: conclave
```

Option B - Disable via pipeline variable:
```bash
# Set variable to skip Code Conclave
az pipelines variable create \
  --name SKIP_CONCLAVE \
  --value true \
  --pipeline-name "Code-Review"
```

Option C - Use previous pipeline definition:
```bash
# Revert pipeline changes in repo
git log --oneline azure-pipelines.yml
git checkout <previous-commit> -- azure-pipelines.yml
git commit -m "Revert: Rollback Code Conclave pipeline changes"
git push
```

**Step 3: Verify rollback**
```bash
# Queue a new build
az pipelines run --name "Code-Review" --branch main

# Check status
az pipelines runs list --pipeline-name "Code-Review" --top 1
```

**Step 4: Notify team**
- Update the PR with status
- Create a work item if needed:
```bash
az boards work-item create \
  --type Bug \
  --title "Code Conclave pipeline failure" \
  --description "Rolled back to version X. Root cause: ..."
```

### Post-Rollback Verification

After any rollback, verify the system is working:

1. **Run a test review**:
   ```powershell
   ./cli/ccl.ps1 -Project . -DryRun -CI
   # Should exit 0 with mock findings
   ```

2. **Verify API connectivity**:
   ```powershell
   ./cli/Test-Providers.ps1 -Provider anthropic
   # Should return "Provider test successful"
   ```

3. **Check JUnit output**:
   ```powershell
   [xml]$result = Get-Content .code-conclave/reviews/conclave-results.xml
   $result.testsuites.tests  # Should show finding count
   ```

4. **Verify CI integration**:
   - Trigger a test PR or build
   - Confirm results appear in test tab
   - Confirm exit codes are correct

### Communication Procedures

**Immediate (within 15 minutes)**:
- [ ] Post in team chat (Slack/Teams) about the issue
- [ ] Add comment to affected PRs explaining the situation
- [ ] Update pipeline status page if applicable

**Short-term (within 1 hour)**:
- [ ] Create tracking issue/work item with root cause analysis
- [ ] Identify scope of impact (which PRs/builds affected)
- [ ] Communicate timeline for fix

**Resolution**:
- [ ] Document what went wrong in the tracking issue
- [ ] Update runbook if new failure mode discovered
- [ ] Consider adding automated checks to prevent recurrence

### Emergency Contacts

For critical pipeline failures:

| Role | Contact |
|------|---------|
| Pipeline Owner | Check CODEOWNERS file |
| AI Provider Issues | Provider status page |
| Code Conclave Issues | GitHub Issues: Blb3D/review-council |

---

## Monitoring

### Token Usage

After each review, token usage is logged:

```
Tokens: 8056 input, 23224 output (375840 cached)
```

Monitor for:
- **High input tokens**: May indicate large PR or full-scan instead of diff-scope
- **Low cache hits**: Check if `-BaseBranch` is set correctly
- **Unusual patterns**: Spikes may indicate configuration issues

### Review Duration

Typical review times:
- Single agent: 30-90 seconds
- Full 6-agent review: 4-8 minutes
- Large codebase (50+ files): 10-15 minutes

If reviews take significantly longer, check:
- Network connectivity to AI provider
- Rate limiting (429 errors in logs)
- Large file sizes in project

### Log Locations

| Location | Contents |
|----------|----------|
| `.code-conclave/reviews/` | Agent findings (markdown) |
| `.code-conclave/reviews/conclave-results.xml` | JUnit XML for CI |
| `.code-conclave/reviews/RELEASE-READINESS-REPORT.md` | Summary report |
| CI pipeline logs | Token usage, timing, errors |

---

## Troubleshooting

### "API key not found"

```
Error: API key not found in environment variable: ANTHROPIC_API_KEY
```

**Solution**: Set the environment variable:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### "Rate limited"

```
WARNING: Rate limited (attempt 1/5): 429 Too Many Requests. Retrying in 30s...
```

**Solution**: This is handled automatically. The system retries with backoff. If persistent:
- Check your API quota
- Consider using a different provider
- Reduce the number of agents per review

### "No changed files detected"

```
Diff-scoped: 0 changed files (0 KB) against main
```

**Solution**: Ensure you're on a feature branch with changes:
```bash
git status  # Verify changes exist
git diff main --name-only  # Verify diff detection
```

### Tests fail locally but pass in CI

**Possible causes**:
- Different Pester versions (local vs CI)
- Path differences (Windows vs Linux)
- Missing dependencies

**Solution**:
```powershell
# Run tests with verbose output
Invoke-Pester ./cli/tests -PassThru
```

---

## Health Checks

### Quick Validation

```powershell
# Verify CLI loads
./cli/ccl.ps1 --help

# Verify provider connectivity (requires API key)
./cli/Test-Providers.ps1 -Provider anthropic

# Verify test suite
Invoke-Pester ./cli/tests
```

### Pre-deployment Checklist

- [ ] API key is configured and valid
- [ ] Network access to AI provider endpoint
- [ ] Git is available (for diff-scoping)
- [ ] Project is initialized (`-Init`)
- [ ] Tests pass locally

---

*Last updated: 2026-02-05*
