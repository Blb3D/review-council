# Azure DevOps Pipeline Installation Guide

Step-by-step instructions for installing Code Conclave in Azure DevOps pipelines.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Import the Repository](#step-1-import-the-repository)
- [Step 2: Configure Secrets](#step-2-configure-secrets)
- [Step 3: Create the Pipeline](#step-3-create-the-pipeline)
- [Step 4: Configure Branch Policies](#step-4-configure-branch-policies)
- [Step 5: Verify](#step-5-verify)
- [Pipeline Options](#pipeline-options)
- [AI Provider Configuration](#ai-provider-configuration)
- [Compliance Standards in Pipelines](#compliance-standards-in-pipelines)
- [Cost Estimates](#cost-estimates)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Azure DevOps** | Project with Repos and Pipelines enabled |
| **PowerShell 7** | Built into `windows-latest` and `ubuntu-latest` agents |
| **AI Provider** | API key for Anthropic, Azure OpenAI, or OpenAI |
| **Permissions** | Project Administrator or Build Administrator role |

---

## Step 1: Import the Repository

Code Conclave needs to be available in your ADO environment. Choose one option:

### Option A: Import into ADO Repos (Recommended)

1. Go to **Repos** > **Import repository**
2. Set source URL: `https://github.com/Blb3D/review-council.git`
3. Name it `code-conclave`
4. Click **Import**

This gives you a local copy you control. To update later:

```bash
git remote add upstream https://github.com/Blb3D/review-council.git
git fetch upstream
git merge upstream/main
```

### Option B: Clone at Build Time

No import needed. The pipeline clones Code Conclave during each run. Slightly slower but always gets the latest version. See the pipeline YAML in Step 3 for this approach.

---

## Step 2: Configure Secrets

### For Anthropic (Recommended)

1. Go to **Pipelines** > **Library**
2. Click **+ Variable group**
3. Name it `code-conclave-secrets`
4. Add variable: `ANTHROPIC_API_KEY`
   - Value: your API key (e.g., `sk-ant-api03-...`)
   - Click the lock icon to mark as **secret**
5. Click **Save**

### For Azure OpenAI

Same steps, but add:

| Variable | Value | Secret? |
|----------|-------|---------|
| `AZURE_OPENAI_KEY` | Your Azure OpenAI key | Yes |
| `AZURE_OPENAI_ENDPOINT` | `https://your-resource.openai.azure.com/` | No |
| `AZURE_OPENAI_DEPLOYMENT` | Your deployment name (e.g., `gpt-4o`) | No |

### For OpenAI

Add variable: `OPENAI_API_KEY` (marked as secret).

---

## Step 3: Create the Pipeline

### Option A: Code Conclave in ADO Repos

If you imported the repo (Step 1 Option A), create `azure-pipelines-conclave.yml` in your project repository:

```yaml
# Code Conclave - AI Code Review Pipeline
# Runs on PRs to main/develop and blocks merge on BLOCKER findings.

trigger: none   # Only run on PR, not on push

pr:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'windows-latest'

variables:
  - group: code-conclave-secrets

resources:
  repositories:
    - repository: conclave
      type: git
      name: code-conclave   # Name from Step 1

steps:
- checkout: self
  fetchDepth: 0

- checkout: conclave
  path: code-conclave

- task: PowerShell@2
  displayName: 'Run Code Conclave Review'
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
  inputs:
    targetType: inline
    pwsh: true
    script: |
      $conclaveDir = "$(Pipeline.Workspace)/code-conclave"
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)/$(Build.Repository.Name)" `
        -OutputFormat junit `
        -CI
  continueOnError: true

- task: PublishTestResults@2
  displayName: 'Publish Code Conclave Results'
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/conclave-results.xml'
    searchFolder: '$(Build.SourcesDirectory)'
    testRunTitle: 'Code Conclave Review'
    mergeTestResults: true
    failTaskOnFailedTests: true

- task: PublishBuildArtifacts@1
  displayName: 'Publish Review Reports'
  condition: always()
  inputs:
    pathToPublish: '$(Build.SourcesDirectory)/$(Build.Repository.Name)/.code-conclave/reviews'
    artifactName: 'code-conclave-reports'
```

### Option B: Clone from GitHub at Build Time

If you did not import the repo, use this pipeline. It clones Code Conclave from GitHub during each run:

```yaml
# Code Conclave - AI Code Review Pipeline (GitHub source)

trigger: none

pr:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'windows-latest'

variables:
  - group: code-conclave-secrets

steps:
- checkout: self
  fetchDepth: 0

- task: PowerShell@2
  displayName: 'Download Code Conclave'
  inputs:
    targetType: inline
    pwsh: true
    script: |
      git clone https://github.com/Blb3D/review-council.git "$(Pipeline.Workspace)/code-conclave"

- task: PowerShell@2
  displayName: 'Run Code Conclave Review'
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
  inputs:
    targetType: inline
    pwsh: true
    script: |
      $conclaveDir = "$(Pipeline.Workspace)/code-conclave"
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -OutputFormat junit `
        -CI
  continueOnError: true

- task: PublishTestResults@2
  displayName: 'Publish Code Conclave Results'
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/conclave-results.xml'
    searchFolder: '$(Build.SourcesDirectory)'
    testRunTitle: 'Code Conclave Review'
    mergeTestResults: true
    failTaskOnFailedTests: true

- task: PublishBuildArtifacts@1
  displayName: 'Publish Review Reports'
  condition: always()
  inputs:
    pathToPublish: '$(Build.SourcesDirectory)/.code-conclave/reviews'
    artifactName: 'code-conclave-reports'
```

### Creating the Pipeline in ADO

1. Go to **Pipelines** > **New pipeline**
2. Select **Azure Repos Git** (or wherever your project repo lives)
3. Select your project repository
4. Choose **Existing Azure Pipelines YAML file**
5. Select the path to the YAML file you created above
6. Click **Save** (not "Run" yet)
7. Rename the pipeline to `Code Conclave Review`

---

## Step 4: Configure Branch Policies

This is the critical step that **blocks merge when Code Conclave finds blockers**.

1. Go to **Repos** > **Branches**
2. Click the `...` menu next to `main` > **Branch policies**
3. Under **Build Validation**, click **+ Add build policy**
4. Configure:

| Setting | Value |
|---------|-------|
| **Build pipeline** | Code Conclave Review |
| **Trigger** | Automatic |
| **Policy requirement** | Required |
| **Build expiration** | Immediately when main is updated |
| **Display name** | Code Conclave Review |

5. Click **Save**

Now every PR to `main` will:
- Automatically trigger Code Conclave
- Show pass/fail status on the PR
- **Block merge if BLOCKER findings are found** (exit code 1 = failed build)
- Allow merge if only MEDIUM/LOW findings (exit code 0 = SHIP)

### Optional: Require Reviewers to See Results

Under **Branch policies**, you can also require:
- Minimum number of reviewers
- Specific reviewers who check the Code Conclave report artifact

---

## Step 5: Verify

### Test with a PR

1. Create a feature branch
2. Make a code change
3. Open a PR to `main`
4. Watch the **Checks** tab for "Code Conclave Review"
5. When complete, click the check to see:
   - **Test Results**: Findings as pass/fail test cases
   - **Artifacts**: Full markdown reports

### Test with Manual Run

1. Go to **Pipelines** > **Code Conclave Review**
2. Click **Run pipeline**
3. Select your branch
4. Click **Run**

### Expected Results in ADO

The Published Test Results appear in the **Tests** tab:

```
Test Run: Code Conclave Review
  GUARDIAN
    GUARDIAN-001: Hardcoded API Key [BLOCKER]     FAILED
    GUARDIAN-002: HTTPS Not Enforced [MEDIUM]     PASSED
  SENTINEL
    SENTINEL-001: Missing Unit Tests [HIGH]       FAILED
    SENTINEL-002: Low Code Coverage [MEDIUM]      PASSED
```

BLOCKER and HIGH findings appear as **failed tests**. MEDIUM and LOW appear as **passed tests** (issues noted but not blocking).

---

## Pipeline Options

### Select Specific Agents

Run only security and quality agents for faster PR checks:

```yaml
- task: PowerShell@2
  inputs:
    script: |
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -Agents guardian,sentinel `
        -OutputFormat junit `
        -CI
```

### Available Agents

| Agent | Purpose | Typical Time |
|-------|---------|-------------|
| `guardian` | Security vulnerabilities, secrets, dependencies | 1-2 min |
| `sentinel` | Code quality, testing, maintainability | 1-2 min |
| `architect` | Architecture, patterns, scalability | 1-2 min |
| `navigator` | API design, integration, contracts | 1-2 min |
| `herald` | Documentation, comments, readability | 1-2 min |
| `operator` | DevOps, deployment, infrastructure | 1-2 min |

For PR validation, `guardian,sentinel` provides the most value in the least time.

### Add Compliance Standards

```yaml
- task: PowerShell@2
  inputs:
    script: |
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -AddStandards cmmc-l2,itar `
        -OutputFormat junit `
        -CI
```

### Pipeline Parameters for Standard Selection

Allow teams to select standards when running manually:

```yaml
parameters:
  - name: complianceStandard
    displayName: 'Compliance Standard'
    type: string
    default: 'none'
    values:
      - none
      - cmmc-l2
      - itar
      - fda-21-cfr-11
      - iso-9001-2015

steps:
- task: PowerShell@2
  inputs:
    script: |
      $params = @{
        Project      = "$(Build.SourcesDirectory)"
        OutputFormat = "junit"
        CI           = $true
      }

      if ("${{ parameters.complianceStandard }}" -ne "none") {
        $params.AddStandards = @("${{ parameters.complianceStandard }}")
      }

      & "$conclaveDir/cli/ccl.ps1" @params
```

---

## AI Provider Configuration

### Using Azure OpenAI (Enterprise)

For organizations that require data to stay within Azure:

```yaml
variables:
  - group: code-conclave-secrets

steps:
- task: PowerShell@2
  env:
    AZURE_OPENAI_KEY: $(AZURE_OPENAI_KEY)
  inputs:
    script: |
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -AIProvider azure-openai `
        -AIModel gpt-4o `
        -AIEndpoint "$(AZURE_OPENAI_ENDPOINT)" `
        -OutputFormat junit `
        -CI
```

### Using Anthropic (Best Quality)

```yaml
- task: PowerShell@2
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
  inputs:
    script: |
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -AIProvider anthropic `
        -OutputFormat junit `
        -CI
```

### Provider Comparison

| Provider | Quality | Cost per Review | Data Residency | Setup |
|----------|---------|-----------------|----------------|-------|
| Anthropic Claude | Highest | ~$0.50 (6 agents) | US/EU | API key only |
| Azure OpenAI | High | Varies by tier | Your Azure region | Azure subscription |
| OpenAI | High | ~$0.40 (6 agents) | US | API key only |
| Ollama | Good | Free | On-premise | Self-hosted GPU |

---

## Cost Estimates

Based on real-world testing with a medium-sized TypeScript project (~50 source files):

### Per Review Run

| Configuration | Tokens | Time | Cost (Anthropic) |
|--------------|--------|------|-------------------|
| 2 agents (guardian + sentinel) | ~30K in / ~4K out | ~2 min | ~$0.12 |
| 6 agents (full suite) | ~100K in / ~14K out | ~5 min | ~$0.51 |

### Monthly Estimates (20 PRs/week)

| Configuration | Monthly Cost | Findings/Month |
|--------------|-------------|----------------|
| 2 agents per PR | ~$10 | ~200 issues caught |
| 6 agents per PR | ~$41 | ~500+ issues caught |

These costs are approximate and vary with codebase size and AI provider pricing.

---

## Troubleshooting

### "No test results found"

**Cause:** The review step failed before generating JUnit XML.

**Fix:** Check the review step logs. Common causes:
- API key not available (check variable group linking)
- Incorrect project path

### "Build fails but no findings shown"

**Cause:** The review process itself errored (exit code 10+).

**Fix:**
1. Check the PowerShell step output for error messages
2. Ensure the API key environment variable is correctly mapped
3. Test with `-DryRun` to verify the pipeline works without an API key

### "Variable group not accessible"

**Cause:** Pipeline doesn't have permission to the variable group.

**Fix:**
1. Go to **Pipelines** > **Library** > your variable group
2. Click **Pipeline permissions**
3. Add your pipeline

### "Branch policy not triggering"

**Cause:** Policy configuration issue.

**Fix:**
1. Verify the pipeline name in branch policies matches exactly
2. Check that the PR targets the branch with the policy (e.g., `main`)
3. Ensure the pipeline YAML has `pr:` trigger configured

### "Timeout during review"

**Cause:** Large codebase or slow AI provider.

**Fix:** Add timeout to the pipeline:
```yaml
- task: PowerShell@2
  timeoutInMinutes: 30
  inputs:
    script: |
      & "$conclaveDir/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -Agents guardian,sentinel `
        -Timeout 20 `
        -OutputFormat junit `
        -CI
```

---

## Quick Reference

### Exit Codes

| Code | Verdict | Build Result | PR Impact |
|------|---------|-------------|-----------|
| 0 | SHIP | Pass | Merge allowed |
| 1 | HOLD | Fail | **Merge blocked** |
| 2 | CONDITIONAL | Pass | Merge allowed (with warnings) |
| 10+ | Error | Fail | Merge blocked |

### Minimum Pipeline (Copy-Paste)

```yaml
trigger: none
pr:
  branches:
    include: [main]
pool:
  vmImage: 'windows-latest'
variables:
  - group: code-conclave-secrets
steps:
- checkout: self
  fetchDepth: 0
- pwsh: git clone https://github.com/Blb3D/review-council.git "$(Pipeline.Workspace)/cc"
  displayName: 'Get Code Conclave'
- task: PowerShell@2
  displayName: 'Review'
  env:
    ANTHROPIC_API_KEY: $(ANTHROPIC_API_KEY)
  inputs:
    targetType: inline
    pwsh: true
    script: |
      & "$(Pipeline.Workspace)/cc/cli/ccl.ps1" `
        -Project "$(Build.SourcesDirectory)" `
        -Agents guardian,sentinel `
        -OutputFormat junit -CI
  continueOnError: true
- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/conclave-results.xml'
    testRunTitle: 'Code Conclave Review'
    failTaskOnFailedTests: true
```

---

*Last updated: 2026-02-04*
