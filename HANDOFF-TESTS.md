# Handoff: Test Infrastructure Implementation

**Date:** 2026-02-05
**Status:** Ready to implement
**Priority:** HIGH (SENTINEL-001/002 blockers)

---

## Context

Code Conclave ran a self-review and found 33 issues. Security issues (GUARDIAN) have been fixed. The remaining blockers are about missing test coverage.

### Fixed This Session
- GUARDIAN-001: Path traversal in dashboard API
- GUARDIAN-002: WebSocket without authentication
- GUARDIAN-004: API key leakage in error messages
- GUARDIAN-005: Unvalidated JSON input
- GUARDIAN-006: Missing input validation

### Remaining Blockers
- **SENTINEL-001**: No test coverage infrastructure
- **SENTINEL-002**: Critical PowerShell CLI components untested

---

## Implementation Plan

### Phase 1: PowerShell Tests (Pester)

**Install Pester** (if not present):
```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

**Create test structure:**
```
cli/
├── tests/
│   ├── ai-engine.Tests.ps1
│   ├── config-loader.Tests.ps1
│   ├── project-scanner.Tests.ps1
│   ├── junit-formatter.Tests.ps1
│   └── ccl.Tests.ps1
```

**Priority test files:**

1. **config-loader.Tests.ps1** - Test config merging logic
   ```powershell
   Describe "Get-EffectiveConfig" {
       It "merges project config over defaults" { }
       It "handles missing project config gracefully" { }
       It "deep merges nested hashtables" { }
   }
   ```

2. **ai-engine.Tests.ps1** - Test error sanitization and provider selection
   ```powershell
   Describe "Get-SanitizedError" {
       It "redacts Anthropic API keys" {
           $result = Get-SanitizedError "Error: sk-ant-api03-abc123"
           $result | Should -Be "Error: [REDACTED_KEY]"
       }
       It "redacts OpenAI API keys" { }
       It "redacts Bearer tokens" { }
   }

   Describe "Get-AIProvider" {
       It "returns anthropic by default" { }
       It "respects provider override" { }
   }
   ```

3. **project-scanner.Tests.ps1** - Test diff detection
   ```powershell
   Describe "Get-DiffContext" {
       It "returns null when no base branch specified" { }
       It "detects changed files against base branch" { }
       It "respects file size limits" { }
   }
   ```

4. **junit-formatter.Tests.ps1** - Test XML output
   ```powershell
   Describe "Export-JUnitResults" {
       It "creates valid XML structure" { }
       It "marks BLOCKER/HIGH as failures" { }
       It "marks MEDIUM/LOW as passed" { }
   }
   ```

**Run tests:**
```powershell
Invoke-Pester ./cli/tests -Output Detailed
```

### Phase 2: Node.js Tests (Jest)

**Install Jest:**
```bash
cd dashboard
npm install --save-dev jest supertest
```

**Add to package.json:**
```json
{
  "scripts": {
    "test": "jest"
  }
}
```

**Create test file:**
```
dashboard/
├── __tests__/
│   └── server.test.js
```

**server.test.js:**
```javascript
const request = require('supertest');
// Would need to refactor server.js to export app for testing

describe('API Endpoints', () => {
    describe('POST /api/log', () => {
        it('rejects missing message', async () => {
            const res = await request(app).post('/api/log').send({});
            expect(res.status).toBe(400);
        });

        it('rejects message over 1000 chars', async () => {
            const res = await request(app).post('/api/log').send({
                message: 'x'.repeat(1001)
            });
            expect(res.status).toBe(400);
        });
    });

    describe('GET /api/findings/:agentId', () => {
        it('rejects invalid agent ID', async () => {
            const res = await request(app).get('/api/findings/invalid');
            expect(res.status).toBe(400);
        });

        it('blocks path traversal attempts', async () => {
            const res = await request(app).get('/api/findings/../../../etc/passwd');
            expect(res.status).toBe(400);
        });
    });
});
```

### Phase 3: CI Integration

**Add to `.github/workflows/code-conclave.yml`:**
```yaml
  test:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v4

    - name: Run PowerShell Tests
      shell: pwsh
      run: |
        Install-Module -Name Pester -Force -SkipPublisherCheck
        Invoke-Pester ./cli/tests -Output Detailed -CI

    - name: Run Node.js Tests
      working-directory: dashboard
      run: |
        npm install
        npm test
```

---

## Files to Create

| File | Purpose | Priority |
|------|---------|----------|
| `cli/tests/ai-engine.Tests.ps1` | Test error sanitization, provider selection | HIGH |
| `cli/tests/config-loader.Tests.ps1` | Test config merging | HIGH |
| `cli/tests/project-scanner.Tests.ps1` | Test diff detection | MEDIUM |
| `cli/tests/junit-formatter.Tests.ps1` | Test XML output | MEDIUM |
| `dashboard/__tests__/server.test.js` | Test API endpoints | MEDIUM |

---

## Acceptance Criteria

- [ ] `Invoke-Pester ./cli/tests` passes
- [ ] `npm test` in dashboard passes
- [ ] CI workflow runs tests on PR
- [ ] Coverage for critical paths: config loading, error sanitization, API validation

---

## Notes

- Dashboard server.js may need refactoring to export `app` for supertest
- Mock AI provider responses for ai-engine tests (don't call real APIs)
- Use temporary directories for project-scanner tests
- The CONTRACTS.md validation (SENTINEL-004) can be a separate follow-up

---

*Generated from Code Conclave self-review findings*
