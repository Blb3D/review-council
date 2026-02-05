# Installation Guide

Complete setup instructions for Code Conclave on all supported platforms.

---

## Table of Contents

- [Requirements](#requirements)
- [Quick Install](#quick-install)
- [Detailed Installation](#detailed-installation)
  - [Windows](#windows)
  - [macOS](#macos)
  - [Linux](#linux)
- [AI Provider Setup](#ai-provider-setup)
  - [Anthropic Claude](#anthropic-claude)
  - [Azure OpenAI](#azure-openai)
  - [OpenAI](#openai)
  - [Ollama (Local)](#ollama-local)
- [Project Configuration](#project-configuration)
- [CI/CD Installation](#cicd-installation)
  - [GitHub Actions](#github-actions)
  - [Azure DevOps](#azure-devops)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Requirements

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **PowerShell** | 5.1 | 7.x (Core) |
| **Memory** | 4 GB | 8 GB |
| **Disk Space** | 100 MB | 500 MB (with reports) |
| **Network** | Required for cloud AI | N/A for Ollama |

### AI Provider Requirements

You need **ONE** of the following:

| Provider | Requirement |
|----------|-------------|
| Anthropic Claude | API key from [console.anthropic.com](https://console.anthropic.com) |
| Azure OpenAI | Azure subscription + deployed model |
| OpenAI | API key from [platform.openai.com](https://platform.openai.com) |
| Ollama | Local installation, ~4-8GB per model |

---

## Quick Install

### Windows (PowerShell)

```powershell
# Clone the repository
git clone https://github.com/Blb3D/review-council.git C:\tools\code-conclave

# Add to PATH (optional, run in elevated PowerShell)
[Environment]::SetEnvironmentVariable(
    "Path",
    $env:Path + ";C:\tools\code-conclave\cli",
    [EnvironmentVariableTarget]::User
)

# Set API key
$env:ANTHROPIC_API_KEY = "sk-ant-api03-..."

# Verify installation
C:\tools\code-conclave\cli\ccl.ps1 -DryRun -Project .
```

### macOS / Linux

```bash
# Clone the repository
git clone https://github.com/Blb3D/review-council.git ~/tools/code-conclave

# Make executable
chmod +x ~/tools/code-conclave/cli/ccl.ps1

# Add alias (add to ~/.bashrc or ~/.zshrc)
alias ccl='pwsh ~/tools/code-conclave/cli/ccl.ps1'

# Set API key
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Verify installation
ccl -DryRun -Project .
```

---

## Detailed Installation

### Windows

#### Step 1: Install PowerShell 7 (Recommended)

While Code Conclave works with PowerShell 5.1 (built into Windows), PowerShell 7 is recommended for best performance.

```powershell
# Install via winget
winget install Microsoft.PowerShell

# Or download from:
# https://github.com/PowerShell/PowerShell/releases
```

#### Step 2: Clone Code Conclave

```powershell
# Create tools directory
New-Item -ItemType Directory -Path C:\tools -Force

# Clone repository
git clone https://github.com/Blb3D/review-council.git C:\tools\code-conclave
```

#### Step 3: Add to PATH (Optional)

To run `ccl` from anywhere:

```powershell
# Run as Administrator
$currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
$newPath = "$currentPath;C:\tools\code-conclave\cli"
[Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)

# Restart terminal to apply
```

#### Step 4: Configure Execution Policy

If you see "script cannot be loaded" errors:

```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### macOS

#### Step 1: Install PowerShell Core

```bash
# Using Homebrew
brew install powershell/tap/powershell

# Verify
pwsh --version
```

#### Step 2: Clone Code Conclave

```bash
mkdir -p ~/tools
git clone https://github.com/Blb3D/review-council.git ~/tools/code-conclave
```

#### Step 3: Create Alias

Add to `~/.zshrc` or `~/.bashrc`:

```bash
alias ccl='pwsh ~/tools/code-conclave/cli/ccl.ps1'
```

Reload shell:

```bash
source ~/.zshrc  # or ~/.bashrc
```

### Linux

#### Step 1: Install PowerShell Core

**Ubuntu/Debian:**
```bash
# Add Microsoft repository
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
```

**RHEL/CentOS/Fedora:**
```bash
# Add Microsoft repository
sudo rpm -Uvh https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm
sudo yum install -y powershell
```

**Arch Linux:**
```bash
yay -S powershell-bin
```

#### Step 2: Clone and Configure

```bash
mkdir -p ~/tools
git clone https://github.com/Blb3D/review-council.git ~/tools/code-conclave

# Add alias
echo "alias ccl='pwsh ~/tools/code-conclave/cli/ccl.ps1'" >> ~/.bashrc
source ~/.bashrc
```

---

## AI Provider Setup

### Anthropic Claude

**Recommended provider** - Best quality reviews.

#### Step 1: Get API Key

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create account or sign in
3. Navigate to API Keys
4. Create new key, copy it

#### Step 2: Set Environment Variable

**Windows (PowerShell):**
```powershell
# Session only
$env:ANTHROPIC_API_KEY = "sk-ant-api03-..."

# Permanent (User level)
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-api03-...", "User")
```

**macOS/Linux:**
```bash
# Session only
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export ANTHROPIC_API_KEY="sk-ant-api03-..."' >> ~/.bashrc
```

#### Step 3: Configure (Optional)

Create `.code-conclave/config.yaml` in your project:

```yaml
ai:
  provider: anthropic
  anthropic:
    model: claude-sonnet-4-20250514    # or claude-opus-4-20250514
    api_key_env: ANTHROPIC_API_KEY
    max_tokens: 16000
```

### Azure OpenAI

**For enterprise environments** with Azure subscriptions.

#### Step 1: Deploy Model in Azure

1. Go to [Azure Portal](https://portal.azure.com)
2. Create Azure OpenAI resource
3. Deploy a model (GPT-4o recommended)
4. Note: endpoint URL, deployment name, API key

#### Step 2: Set Environment Variable

```powershell
$env:AZURE_OPENAI_KEY = "your-azure-key"
```

#### Step 3: Configure

```yaml
ai:
  provider: azure-openai
  azure-openai:
    endpoint: https://your-resource.openai.azure.com/
    deployment: gpt-4o                  # Your deployment name
    api_version: "2024-02-15-preview"
    api_key_env: AZURE_OPENAI_KEY
    max_tokens: 16000
```

### OpenAI

**Alternative cloud provider.**

#### Step 1: Get API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Create API key

#### Step 2: Set Environment Variable

```powershell
$env:OPENAI_API_KEY = "sk-..."
```

#### Step 3: Configure

```yaml
ai:
  provider: openai
  openai:
    model: gpt-4o
    api_key_env: OPENAI_API_KEY
    max_tokens: 16000
```

### Ollama (Local)

**Free, offline option** using local models.

#### Step 1: Install Ollama

**Windows:**
Download from [ollama.ai](https://ollama.ai)

**macOS:**
```bash
brew install ollama
```

**Linux:**
```bash
curl -fsSL https://ollama.ai/install.sh | sh
```

#### Step 2: Pull a Model

```bash
# Recommended for code review (requires ~8GB RAM)
ollama pull llama3.1:70b

# Smaller alternative (~4GB RAM)
ollama pull llama3.1:8b

# Code-specialized
ollama pull codellama:34b
```

#### Step 3: Start Ollama Server

```bash
ollama serve
# Runs on http://localhost:11434
```

#### Step 4: Configure

```yaml
ai:
  provider: ollama
  ollama:
    endpoint: http://localhost:11434
    model: llama3.1:70b
    max_tokens: 8000
```

---

## Cost Optimization Setup

Code Conclave includes cost optimization features (diff-scoped scanning, prompt caching, and model tiering) that work automatically for most providers. This section covers additional setup steps where needed.

### Anthropic

No extra setup required. Prompt caching and model tiering are configured by default:

- Primary model: `claude-sonnet-4-20250514`
- Lite model: `claude-haiku-4-5-20251001`

Both models are accessed through the same API key. Caching uses the `cache_control` API feature, which is generally available.

### Azure OpenAI

Prompt caching and diff-scoping work automatically. To enable **model tiering**, you need a second deployment for the lite model.

#### Step 1: Create Lite Deployment

1. Go to [Azure Portal](https://portal.azure.com) > your Azure OpenAI resource
2. Click **Model deployments** > **Manage Deployments**
3. Click **+ Create new deployment**
4. Configure:
   - **Model**: `gpt-4o-mini`
   - **Deployment name**: `gpt-4o-mini` (or your preferred name)
   - **Deployment type**: Standard
5. Click **Create**

#### Step 2: Update Configuration

Add the `lite_deployment` field to your config:

```yaml
ai:
  provider: azure-openai
  azure-openai:
    endpoint: https://your-resource.openai.azure.com/
    deployment: gpt-4o                   # Primary tier
    lite_deployment: gpt-4o-mini         # Lite tier (from Step 1)
    api_version: "2024-10-01-preview"    # Enables cached token reporting
    api_key_env: AZURE_OPENAI_KEY
    max_tokens: 16000
```

If you skip this step, lite-tier agents will use the primary deployment (GPT-4o) instead. There is no error -- tiering simply has no cost benefit until the lite deployment is configured.

### OpenAI

No extra setup required. Model tiering is configured by default:

- Primary model: `gpt-4o`
- Lite model: `gpt-4o-mini`

Both models are accessed through the same API key. Prompt caching is automatic.

### Ollama (Local)

No setup needed. Ollama is free and local. Tiering and caching do not apply.

For a detailed breakdown of cost savings and configuration options, see the [Cost Optimization Guide](COST-OPTIMIZATION.md).

---

## Project Configuration

### Initialize Project

Run in your project directory:

```powershell
ccl -Init -Project .
```

This creates:

```
your-project/
└── .code-conclave/
    ├── config.yaml          # Project configuration
    └── agents/              # Custom agent overrides (optional)
```

### Basic Configuration

Edit `.code-conclave/config.yaml`:

```yaml
project:
  name: "my-app"

ai:
  provider: anthropic
  anthropic:
    model: claude-sonnet-4-20250514
    api_key_env: ANTHROPIC_API_KEY

agents:
  timeout: 40              # Minutes per agent

standards:
  default:
    - iso-9001-2015        # Add your required standards
```

See [Configuration Reference](CONFIGURATION.md) for all options.

---

## CI/CD Installation

### GitHub Actions

#### Step 1: Add Secret

1. Go to repository Settings → Secrets and variables → Actions
2. Add `ANTHROPIC_API_KEY` (or your provider's key)

#### Step 2: Create Workflow

Create `.github/workflows/code-conclave.yml`:

```yaml
name: Code Conclave Review

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  review:
    runs-on: ubuntu-latest
    timeout-minutes: 90
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Checkout Code Conclave
      uses: actions/checkout@v4
      with:
        repository: Blb3D/review-council
        path: .code-conclave-tool
    
    - name: Run Code Conclave
      shell: pwsh
      env:
        ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      run: |
        ./.code-conclave-tool/cli/ccl.ps1 `
          -Project ${{ github.workspace }} `
          -OutputFormat junit `
          -CI
    
    - name: Publish Results
      uses: EnricoMi/publish-unit-test-result-action@v2
      if: always()
      with:
        files: '**/.code-conclave/reviews/conclave-results.xml'
```

### Azure DevOps

#### Step 1: Add Variable Group

1. Go to Pipelines → Library
2. Create variable group `ai-credentials`
3. Add `AZURE_OPENAI_KEY` (mark as secret)

#### Step 2: Create Pipeline

Create `azure-pipelines.yml`:

```yaml
trigger:
  - main

pr:
  - main

pool:
  vmImage: 'windows-latest'

variables:
  - group: ai-credentials

steps:
- checkout: self

- checkout: git://YourProject/review-council@main
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
        -OutputFormat junit `
        -CI

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/.code-conclave/reviews/conclave-results.xml'
```

---

## Verification

### Test Installation

```powershell
# Should show help
ccl -?

# Should run without errors (no API call)
ccl -DryRun -Project .

# Should connect to AI and run sentinel agent
ccl -Project . -Agent sentinel
```

### Expected Output

```
╔══════════════════════════════════════════════════════════════╗
║                       CODE CONCLAVE                           ║
╚══════════════════════════════════════════════════════════════╝

  AI Provider: Anthropic Claude (claude-sonnet-4-20250514)
  Project: C:\repos\my-app

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SENTINEL - Quality Assurance Agent
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [RUNNING] Deploying SENTINEL...
  [OK] Completed in 2.3 minutes
  [INFO] Tokens: 4521 in / 3842 out
  
  Findings: 0 BLOCKER | 2 HIGH | 3 MEDIUM | 1 LOW
```

---

## Troubleshooting

### Common Issues

#### "Script cannot be loaded"

**Cause:** PowerShell execution policy restriction

**Fix:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### "API key not found"

**Cause:** Environment variable not set

**Fix:** Verify the variable is set:
```powershell
$env:ANTHROPIC_API_KEY  # Should show your key
```

#### "Cannot connect to AI provider"

**Cause:** Network issue or incorrect configuration

**Fix:**
1. Check internet connectivity
2. Verify API key is valid
3. Check endpoint URL (Azure OpenAI)
4. Test with `-DryRun` first

#### "Timeout waiting for agent"

**Cause:** Agent taking too long (large codebase)

**Fix:** Increase timeout:
```powershell
ccl -Project . -Timeout 60  # 60 minutes
```

#### Ollama "Model not found"

**Cause:** Model not pulled or wrong name

**Fix:**
```bash
# List available models
ollama list

# Pull the model
ollama pull llama3.1:70b
```

### Getting Help

- Check [GitHub Issues](https://github.com/Blb3D/review-council/issues)
- Review [Discussions](https://github.com/Blb3D/review-council/discussions)
- Enable verbose output: `-Verbose`

---

## Updating

### Manual Update

```bash
cd /path/to/code-conclave
git pull origin main
```

### Pin to Version

For production, pin to a specific commit or tag:

```yaml
# GitHub Actions
- uses: actions/checkout@v4
  with:
    repository: Blb3D/review-council
    ref: v1.0.0  # or specific SHA
```

---

## Uninstallation

### Remove Code Conclave

```bash
rm -rf /path/to/code-conclave
```

### Remove from PATH

**Windows:**
```powershell
# Edit PATH manually in System Properties → Environment Variables
```

**macOS/Linux:**
Remove alias from `~/.bashrc` or `~/.zshrc`

### Remove Environment Variables

```powershell
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $null, "User")
```

---

*Last updated: 2026-02-05*
