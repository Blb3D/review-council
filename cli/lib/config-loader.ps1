<#
.SYNOPSIS
    Configuration loader for Code Conclave with tiered standards support.

.DESCRIPTION
    Loads and merges configuration from:
    1. Default settings (built-in)
    2. Project config (.code-conclave/config.yaml)
    3. CLI parameters (override)
    
    Handles tiered standards:
    - required: Always applied (organization mandate)
    - default: Applied unless skipped
    - available: Can be added via CLI or PR selection
#>

# Ensure dependencies are loaded
$yamlParserPath = Join-Path $PSScriptRoot "yaml-parser.ps1"
if (Test-Path $yamlParserPath) {
    . $yamlParserPath
}

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Returns default configuration values.
    #>
    return @{
        project = @{
            name = ""
            version = "1.0.0"
            industry = "general"
        }
        standards = @{
            required = @()
            default = @()
            available = @()
            profiles = @{}
        }
        agents = @{
            timeout = 40
            parallel = $false
            sentinel = @{ enabled = $true; coverage_target = 80 }
            guardian = @{ enabled = $true; scan_dependencies = $true }
            architect = @{ enabled = $true }
            navigator = @{ enabled = $true }
            herald = @{ enabled = $true }
            operator = @{ enabled = $true }
        }
        output = @{
            format = "markdown"
            include_evidence = $true
            include_remediation = $true
        }
        ci = @{
            exit_codes = @{
                ship = 0
                conditional = 2
                hold = 1
            }
        }
        ai = @{
            provider = "anthropic"
            temperature = 0.3
            timeout_seconds = 300
            retry_attempts = 3
            retry_delay_seconds = 5
            anthropic = @{
                model = "claude-sonnet-4-20250514"
                api_key_env = "ANTHROPIC_API_KEY"
                max_tokens = 16000
            }
            "azure-openai" = @{
                endpoint = ""
                deployment = "gpt-4o"
                api_version = "2024-02-15-preview"
                api_key_env = "AZURE_OPENAI_KEY"
                max_tokens = 16000
            }
            openai = @{
                model = "gpt-4o"
                api_key_env = "OPENAI_API_KEY"
                max_tokens = 16000
            }
            ollama = @{
                endpoint = "http://localhost:11434"
                model = "llama3.1:70b"
                max_tokens = 8000
            }
        }
    }
}

function Get-ProjectConfig {
    <#
    .SYNOPSIS
        Load project configuration from .code-conclave/config.yaml
    .PARAMETER ProjectPath
        Path to the project root.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )
    
    $configPath = Join-Path $ProjectPath ".code-conclave" "config.yaml"
    
    if (-not (Test-Path $configPath)) {
        Write-Verbose "No project config found at: $configPath"
        return @{}
    }
    
    try {
        $config = Get-YamlContent -Path $configPath
        return $config
    }
    catch {
        Write-Warning "Failed to parse config: $configPath - $_"
        return @{}
    }
}

function Merge-Configs {
    <#
    .SYNOPSIS
        Deep merge two configuration hashtables.
    .DESCRIPTION
        Later values override earlier values. Arrays are replaced, not merged.
    #>
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )
    
    $result = @{}
    
    # Copy all keys from base
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }
    
    # Merge/override with values from override
    foreach ($key in $Override.Keys) {
        $baseValue = $Base[$key]
        $overrideValue = $Override[$key]
        
        if ($baseValue -is [hashtable] -and $overrideValue -is [hashtable]) {
            # Recursively merge hashtables
            $result[$key] = Merge-Configs -Base $baseValue -Override $overrideValue
        }
        else {
            # Replace value
            $result[$key] = $overrideValue
        }
    }
    
    return $result
}

function Get-EffectiveStandards {
    <#
    .SYNOPSIS
        Calculate the effective list of standards to apply.
    .PARAMETER Config
        The merged configuration.
    .PARAMETER Profile
        Optional profile name to use.
    .PARAMETER AddStandards
        Standards to add (comma-separated or array).
    .PARAMETER SkipStandards
        Standards to skip (comma-separated or array).
    #>
    param(
        [hashtable]$Config,
        [string]$Profile,
        [string[]]$AddStandards,
        [string[]]$SkipStandards
    )
    
    $standardsConfig = $Config.standards
    if (-not $standardsConfig) {
        $standardsConfig = @{ required = @(); default = @(); available = @() }
    }
    
    # Start with required standards (always included)
    $effectiveStandards = @()
    if ($standardsConfig.required) {
        $effectiveStandards += $standardsConfig.required
    }
    
    # If using a profile, add profile standards
    if ($Profile -and $Profile -ne 'default' -and $standardsConfig.profiles) {
        $profileConfig = $standardsConfig.profiles[$Profile]
        if ($profileConfig -and $profileConfig.standards) {
            $effectiveStandards += $profileConfig.standards
        }
        else {
            Write-Warning "Profile not found: $Profile"
        }
    }
    else {
        # Add default standards (unless skipped)
        if ($standardsConfig.default) {
            foreach ($std in $standardsConfig.default) {
                if ($std -notin $SkipStandards) {
                    $effectiveStandards += $std
                }
            }
        }
    }
    
    # Add explicitly requested standards
    if ($AddStandards) {
        foreach ($std in $AddStandards) {
            if ($std -and $std -notin $effectiveStandards) {
                $effectiveStandards += $std
            }
        }
    }
    
    # Remove duplicates while preserving order
    $seen = @{}
    $result = @()
    foreach ($std in $effectiveStandards) {
        if ($std -and -not $seen.ContainsKey($std)) {
            $seen[$std] = $true
            $result += $std
        }
    }
    
    return $result
}

function Get-EffectiveConfig {
    <#
    .SYNOPSIS
        Get the fully resolved configuration for a review.
    .PARAMETER ProjectPath
        Path to the project.
    .PARAMETER Profile
        Optional compliance profile name.
    .PARAMETER AddStandards
        Standards to add.
    .PARAMETER SkipStandards
        Standards to skip.
    .PARAMETER CLIOverrides
        Additional CLI parameter overrides.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        
        [string]$Profile,
        [string[]]$AddStandards,
        [string[]]$SkipStandards,
        [hashtable]$CLIOverrides = @{}
    )
    
    # Layer 1: Default config
    $config = Get-DefaultConfig
    
    # Layer 2: Project config
    $projectConfig = Get-ProjectConfig -ProjectPath $ProjectPath
    if ($projectConfig) {
        $config = Merge-Configs -Base $config -Override $projectConfig
    }
    
    # Layer 3: CLI overrides
    if ($CLIOverrides -and $CLIOverrides.Count -gt 0) {
        $config = Merge-Configs -Base $config -Override $CLIOverrides
    }
    
    # Calculate effective standards
    $config._effectiveStandards = Get-EffectiveStandards `
        -Config $config `
        -Profile $Profile `
        -AddStandards $AddStandards `
        -SkipStandards $SkipStandards
    
    # Add project path for reference
    $config._projectPath = $ProjectPath
    
    return $config
}

function Show-EffectiveStandards {
    <#
    .SYNOPSIS
        Display the effective standards configuration.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $standards = $Config._effectiveStandards
    $standardsConfig = $Config.standards
    
    Write-Host ""
    Write-Host "  Compliance Standards" -ForegroundColor Cyan
    Write-Host "  ====================" -ForegroundColor Cyan
    
    if ($standards.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor Gray
        return
    }
    
    foreach ($std in $standards) {
        $tier = if ($std -in $standardsConfig.required) { "[REQUIRED]" }
                elseif ($std -in $standardsConfig.default) { "[DEFAULT]" }
                else { "[ADDED]" }
        
        $color = switch ($tier) {
            "[REQUIRED]" { "Red" }
            "[DEFAULT]" { "Yellow" }
            "[ADDED]" { "Green" }
        }
        
        Write-Host "    " -NoNewline
        Write-Host $tier.PadRight(12) -NoNewline -ForegroundColor $color
        Write-Host $std -ForegroundColor White
    }
    
    Write-Host ""
}

function Test-StandardAvailable {
    <#
    .SYNOPSIS
        Check if a standard is available (defined in available list or already in required/default).
    #>
    param(
        [hashtable]$Config,
        [string]$StandardId
    )
    
    $standardsConfig = $Config.standards
    if (-not $standardsConfig) { return $true }  # No restrictions
    
    # Check all tiers
    if ($StandardId -in $standardsConfig.required) { return $true }
    if ($StandardId -in $standardsConfig.default) { return $true }
    if ($StandardId -in $standardsConfig.available) { return $true }
    
    # Check if it's in any profile
    if ($standardsConfig.profiles) {
        foreach ($profile in $standardsConfig.profiles.Values) {
            if ($StandardId -in $profile.standards) { return $true }
        }
    }
    
    return $false
}

function Get-StandardTier {
    <#
    .SYNOPSIS
        Get the tier of a standard (required, default, available, or unknown).
    #>
    param(
        [hashtable]$Config,
        [string]$StandardId
    )
    
    $standardsConfig = $Config.standards
    if (-not $standardsConfig) { return "unknown" }
    
    if ($StandardId -in $standardsConfig.required) { return "required" }
    if ($StandardId -in $standardsConfig.default) { return "default" }
    if ($StandardId -in $standardsConfig.available) { return "available" }
    
    return "unknown"
}

# Export if running as module
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Get-DefaultConfig, Get-ProjectConfig, Merge-Configs, 
        Get-EffectiveStandards, Get-EffectiveConfig, Show-EffectiveStandards,
        Test-StandardAvailable, Get-StandardTier
}
