# CI/CD Integration Guide

Complete guide for integrating Code Conclave into your CI/CD pipelines.

---

## Table of Contents

- [Overview](#overview)
- [GitHub Actions](#github-actions)
- [Azure DevOps](#azure-devops)
- [GitLab CI](#gitlab-ci)
- [Jenkins](#jenkins)
- [Exit Codes](#exit-codes)
- [Output Formats](#output-formats)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Code Conclave is designed for CI/CD integration with:

- **Exit codes** that fail builds on findings
- **JUnit output** for test result reporting
- **JSON output** for custom tooling
- **No interactive prompts** in CI mode

### Quick Start

```yaml
# Any CI system with PowerShell
- name: Run Code Conclave
  shell: pwsh
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    ./code-conclave/cli/ccl.ps1 -Project . -CI -OutputFormat junit
```

---

## GitHub Actions

### Basic Workflow

Create `.github/workflows/code-conclave.yml`:

```yaml
name: Code Conclave Review

on:
  pull_request:
    branches: [main, develop]
  workflow_dispatch:

jobs:
  review:
    runs-on: ubuntu-latest
    timeout-minutes: 90
    
    steps:
    - name: Checkout Source
      uses: actions/checkout@v4
    
    - name: Checkout Code Conclave
      uses: actions/checkout@v4
      with:
        repository: Blb3D/review-council
        path: .code-conclave-tool
        # Pin to specific version for stability
        # ref: v1.0.0
    
    - name: Run Code Conclave
      shell: pwsh
      env:
        ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      run: |
        ./.code-conclave-tool/cli/ccl.ps1 `
          -Project ${{ github.workspace }} `
          -CI `
          -OutputFormat junit
    
    - name: Publish Test Results
      uses: EnricoMi/publish-unit-test-result-action@v2
      if: always()
      with:
        files: '**/.code-conclave/reviews/conclave-results.xml'
        check_name: 'Code Conclave Review'
    
    - name: Upload Reports
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: code-conclave-reports
        path: .code-conclave/reviews/
        retention-days: 30
```

### With Compliance Standards

```yaml
    - name: Run Code Conclave
      shell: pwsh
      env:
        ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      run: |
        ./.code-conclave-tool/cli/ccl.ps1 `
          -Project ${{ github.workspace }} `
          -AddStandards cmmc-l2,itar `
          -CI `
          -OutputFormat junit
```

### Conditional on File Changes

```yaml
name: Code Conclave Review

on:
  pull_request:
    branches: [main]
    paths:
      - 'backend/**'
      - 'frontend/**'
      - '!**.md'
```

### Matrix Strategy (Multiple Agents)

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        agent: [sentinel, guardian, architect]
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run ${{ matrix.agent }}
      shell: pwsh
      run: |
        ./code-conclave/cli/ccl.ps1 `
          -Project . `
          -Agent ${{ matrix.agent }} `
          -CI
```

### PR Comment with Results

```yaml
    - name: Comment on PR
      uses: actions/github-script@v7
      if: always() && github.event_name == 'pull_request'
      with:
        script: |
          const fs = require('fs');
          const report = fs.readFileSync('.code-conclave/reviews/RELEASE-READINESS-REPORT.md', 'utf8');
          
          github.rest.issues.createComment({
            owner: context.repo.owner,
            repo: context.repo.repo,
            issue_number: context.issue.number,
            body: `## Code Conclave Review\n\n${report}`
          });
```

---

## Azure DevOps

### Basic Pipeline

Create `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - main
      - develop

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'windows-latest'

variables:
  - group: ai-credentials  # Variable group with AZURE_OPENAI_KEY

stages:
- stage: Review
  displayName: 'Code Conclave Review'
  jobs:
  - job: CodeConclave
    displayName: 'Run Code Conclave'
    timeoutInMinutes: 90
    
    steps:
    - checkout: self
    
    - checkout: git://CodeConclave/review-council@main
      path: code-conclave-tool
    
    - task: PowerShell@2
      displayName: 'Run Code Conclave'
      env:
        AZURE_OPENAI_KEY: $(AZURE_OPENAI_KEY)
      inputs:
        targetType: inline
        pwsh: true
        script: |
          $(Pipeline.Workspace)/code-conclave-tool/cli/ccl.ps1 `
            -Project $(Build.SourcesDirectory) `
            -CI `
            -OutputFormat junit
    
    - task: PublishTestResults@2
      displayName: 'Publish Results'
      condition: always()
      inputs:
        testResultsFormat: JUnit
        testResultsFiles: '**/.code-conclave/reviews/conclave-results.xml'
        testRunTitle: 'Code Conclave Review'
        mergeTestResults: true
    
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Reports'
      condition: always()
      inputs:
        pathToPublish: '$(Build.SourcesDirectory)/.code-conclave/reviews'
        artifactName: 'code-conclave-reports'
```

### Template for Reuse

Create `templates/code-conclave.yml`:

```yaml
parameters:
  - name: standards
    type: string
    default: ''
  - name: agents
    type: string
    default: ''
  - name: failOn
    type: string
    default: 'blocker'

steps:
- checkout: git://CodeConclave/review-council@main
  path: code-conclave-tool

- task: PowerShell@2
  displayName: 'Run Code Conclave'
  env:
    AZURE_OPENAI_KEY: $(AZURE_OPENAI_KEY)
  inputs:
    targetType: inline
    pwsh: true
    script: |
      $params = @{
        Project = "$(Build.SourcesDirectory)"
        CI = $true
        OutputFormat = "junit"
      }
      
      if ("${{ parameters.standards }}") {
        $params.AddStandards = "${{ parameters.standards }}".Split(",")
      }
      
      if ("${{ parameters.agents }}") {
        $params.Agents = "${{ parameters.agents }}".Split(",")
      }
      
      $(Pipeline.Workspace)/code-conclave-tool/cli/ccl.ps1 @params

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/.code-conclave/reviews/conclave-results.xml'
```

Use in pipeline:

```yaml
stages:
- stage: Review
  jobs:
  - job: CodeConclave
    steps:
    - template: templates/code-conclave.yml
      parameters:
        standards: 'cmmc-l2,itar'
        agents: 'sentinel,guardian'
```

### PR Standard Selection

Add dropdown in PR creation to select standards:

```yaml
# azure-pipelines.yml
parameters:
  - name: complianceStandards
    displayName: 'Compliance Standards'
    type: string
    default: 'default'
    values:
      - default
      - cmmc-l2
      - itar
      - medical
      - aerospace
```

---

## GitLab CI

Create `.gitlab-ci.yml`:

```yaml
stages:
  - review

code-conclave:
  stage: review
  image: mcr.microsoft.com/powershell:latest
  
  variables:
    ANTHROPIC_API_KEY: $ANTHROPIC_API_KEY
  
  before_script:
    - git clone https://github.com/Blb3D/review-council.git /opt/code-conclave
  
  script:
    - pwsh /opt/code-conclave/cli/ccl.ps1 -Project $CI_PROJECT_DIR -CI -OutputFormat junit
  
  artifacts:
    when: always
    reports:
      junit: .code-conclave/reviews/conclave-results.xml
    paths:
      - .code-conclave/reviews/
    expire_in: 30 days
  
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"
```

---

## Jenkins

### Pipeline Script

```groovy
pipeline {
    agent any
    
    environment {
        ANTHROPIC_API_KEY = credentials('anthropic-api-key')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                
                dir('code-conclave') {
                    git url: 'https://github.com/Blb3D/review-council.git',
                        branch: 'main'
                }
            }
        }
        
        stage('Code Conclave Review') {
            steps {
                pwsh '''
                    ./code-conclave/cli/ccl.ps1 `
                        -Project $env:WORKSPACE `
                        -CI `
                        -OutputFormat junit
                '''
            }
            post {
                always {
                    junit '.code-conclave/reviews/conclave-results.xml'
                    archiveArtifacts artifacts: '.code-conclave/reviews/**',
                                     allowEmptyArchive: true
                }
            }
        }
    }
}
```

---

## Exit Codes

| Code | Verdict | Description | Build Result |
|------|---------|-------------|--------------|
| 0 | SHIP | No issues or low severity only | Pass |
| 1 | HOLD | Blocker findings present | Fail |
| 2 | CONDITIONAL | High findings, no blockers | Pass* |
| 10 | - | Configuration error | Fail |
| 11 | - | AI provider error | Fail |
| 12 | - | Agent timeout | Fail |
| 13 | - | Invalid arguments | Fail |
| 14 | - | Project not found | Fail |

*Exit code 2 passes by default but can be configured to fail.

### Configuring Failure Threshold

In config:
```yaml
ci:
  fail_on: high  # blocker, high, medium, low
```

Or via CLI:
```powershell
# Fail on HIGH or above (not just BLOCKER)
ccl -Project . -CI -FailOn high
```

---

## Output Formats

### JUnit XML

Best for CI/CD test reporting.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Code Conclave" tests="6" failures="2">
  <testsuite name="SENTINEL" tests="1" failures="1" time="180">
    <testcase name="Quality Review" classname="sentinel">
      <failure message="2 HIGH findings">
        SEN-001: Missing unit tests (HIGH)
        SEN-002: Low coverage (HIGH)
      </failure>
    </testcase>
  </testsuite>
</testsuites>
```

### JSON

Best for custom tooling integration.

```json
{
  "timestamp": "2025-02-04T18:00:00Z",
  "project": "/path/to/project",
  "verdict": "CONDITIONAL",
  "agents": {
    "sentinel": {
      "blocker": 0,
      "high": 2,
      "medium": 3,
      "low": 1,
      "findings": [...]
    }
  },
  "totals": {
    "blocker": 0,
    "high": 5,
    "medium": 9,
    "low": 4
  }
}
```

### Markdown

Best for PR comments and human reading.

```markdown
# Code Conclave Results

**Verdict:** CONDITIONAL

| Agent | B | H | M | L |
|-------|---|---|---|---|
| SENTINEL | 0 | 2 | 3 | 1 |
| GUARDIAN | 0 | 1 | 1 | 0 |
...
```

---

## Cost Optimization in CI/CD

Code Conclave includes three cost optimization layers that activate automatically in CI/CD pipelines. No changes to existing pipeline configurations are required.

### Diff-Scoped Scanning (Automatic)

In CI/CD environments, Code Conclave detects the PR's target branch from environment variables and reviews only the changed files:

| CI System | Environment Variable | Detected Automatically |
|-----------|---------------------|----------------------|
| GitHub Actions | `GITHUB_BASE_REF` | Yes |
| Azure DevOps | `SYSTEM_PULLREQUEST_TARGETBRANCH` | Yes |
| GitLab CI | (use `-BaseBranch` parameter) | Manual |
| Jenkins | (use `-BaseBranch` parameter) | Manual |

For systems that do not set a recognized environment variable, add `-BaseBranch main` (or your target branch) to the CLI invocation:

```yaml
# GitLab CI example
script:
  - pwsh /opt/code-conclave/cli/ccl.ps1 -Project $CI_PROJECT_DIR -BaseBranch main -CI -OutputFormat junit
```

When diff-scoping is active, the review processes only the changed files (typically 5-10) instead of the full codebase (up to 50 files). This reduces token usage by roughly 80%.

### Prompt Caching (Automatic)

When multiple agents run in a single review, project context is built once and shared across all agents. AI providers cache this shared prefix and discount subsequent reads:

- **Anthropic**: 90% discount on cached input tokens
- **Azure OpenAI / OpenAI**: 50% discount on cached input tokens

No configuration is needed. Caching is handled internally by the AI engine.

### Model Tiering (Automatic)

Each agent has a default tier that determines which model it uses. Security, quality, and architecture agents use the full model. Documentation, UX, and operations agents use a smaller, cheaper model:

| Agent | Default Tier | Model (Anthropic) | Model (Azure/OpenAI) |
|-------|-------------|-------------------|---------------------|
| GUARDIAN | primary | Sonnet 4 | GPT-4o |
| SENTINEL | primary | Sonnet 4 | GPT-4o |
| ARCHITECT | primary | Sonnet 4 | GPT-4o |
| NAVIGATOR | lite | Haiku 4.5 | GPT-4o-mini |
| HERALD | lite | Haiku 4.5 | GPT-4o-mini |
| OPERATOR | lite | Haiku 4.5 | GPT-4o-mini |

For Azure OpenAI, the lite tier requires a separate deployment (`lite_deployment` in config). If not configured, lite-tier agents fall back to the primary deployment.

### Token Usage in CI Output

After all agents complete, the CI output includes a token usage summary:

```
  Tokens: 27126 input, 22400 output (19000 cached)
```

This line appears in the pipeline log and helps you verify that caching and diff-scoping are working. The `cached` count indicates how many input tokens were served from cache at a reduced rate.

For a detailed breakdown of costs and configuration options, see the [Cost Optimization Guide](COST-OPTIMIZATION.md).

---

## Best Practices

### 1. Pin to Specific Version

Don't use `main` branch in production pipelines:

```yaml
# Good
ref: v1.0.0

# Or specific commit
ref: abc123def456
```

### 2. Cache Code Conclave

Avoid re-cloning on every build:

```yaml
# GitHub Actions
- uses: actions/cache@v4
  with:
    path: .code-conclave-tool
    key: code-conclave-${{ hashFiles('.code-conclave/config.yaml') }}
```

### 3. Run in Parallel

Split agents across jobs for faster reviews:

```yaml
strategy:
  matrix:
    agent: [sentinel, guardian, architect, navigator, herald, operator]
```

### 4. Fail Fast on Security

Run GUARDIAN first and fail early:

```yaml
jobs:
  security:
    steps:
      - run: ccl -Project . -Agent guardian -CI
  
  review:
    needs: security
    steps:
      - run: ccl -Project . -SkipAgents guardian -CI
```

### 5. Cache AI Responses (Development)

For development/testing, enable response caching:

```yaml
ai:
  cache_responses: true  # Don't use in production
```

### 6. Set Appropriate Timeouts

Larger codebases need more time:

```yaml
timeout-minutes: 90  # 6 agents × 15 min each
```

### 7. Store Reports as Artifacts

Always save reports for debugging:

```yaml
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: code-conclave-reports
    path: .code-conclave/reviews/
```

---

## Troubleshooting

### "API key not found"

**Cause:** Secret not configured or not passed to step.

**Fix:**
```yaml
env:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### "Timeout waiting for agent"

**Cause:** Large codebase or slow AI provider.

**Fix:**
```powershell
ccl -Project . -Timeout 60 -CI
```

### "No test results to publish"

**Cause:** JUnit file not generated (review failed).

**Fix:** Check logs for errors. Add `continue-on-error: true` if needed.

### "Cannot connect to AI provider"

**Cause:** Network restrictions in CI environment.

**Fix:** Ensure outbound HTTPS to API endpoints is allowed.

### Exit Code 2 Failing Build

**Cause:** Pipeline treats non-zero as failure.

**Fix:**
```yaml
# GitHub Actions
continue-on-error: true

# Or check exit code manually
- run: |
    ccl -Project . -CI
    if [ $? -eq 2 ]; then
      echo "::warning::Conditional findings"
      exit 0
    fi
```

---

*Last updated: 2026-02-05*
