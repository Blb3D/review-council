<#
.SYNOPSIS
    Pester tests for config-loader.ps1

.DESCRIPTION
    Tests for configuration loading and merging functionality.
#>

# Load dependencies
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here ".." "lib" "yaml-parser.ps1")
. (Join-Path $here ".." "lib" "config-loader.ps1")

Describe "Get-DefaultConfig" {
    It "returns a hashtable" {
        $config = Get-DefaultConfig
        $config | Should BeOfType [hashtable]
    }

    It "includes required top-level keys" {
        $config = Get-DefaultConfig
        ($config.Keys -contains "project") | Should Be $true
        ($config.Keys -contains "agents") | Should Be $true
        ($config.Keys -contains "ai") | Should Be $true
        ($config.Keys -contains "output") | Should Be $true
    }

    It "has all six agents defined" {
        $config = Get-DefaultConfig
        ($config.agents.Keys -contains "guardian") | Should Be $true
        ($config.agents.Keys -contains "sentinel") | Should Be $true
        ($config.agents.Keys -contains "architect") | Should Be $true
        ($config.agents.Keys -contains "navigator") | Should Be $true
        ($config.agents.Keys -contains "herald") | Should Be $true
        ($config.agents.Keys -contains "operator") | Should Be $true
    }

    It "has correct default AI provider" {
        $config = Get-DefaultConfig
        $config.ai.provider | Should Be "anthropic"
    }

    It "has tier assignments for agents" {
        $config = Get-DefaultConfig
        # Primary tier agents
        $config.agents.guardian.tier | Should Be "primary"
        $config.agents.sentinel.tier | Should Be "primary"
        $config.agents.architect.tier | Should Be "primary"
        # Lite tier agents
        $config.agents.navigator.tier | Should Be "lite"
        $config.agents.herald.tier | Should Be "lite"
        $config.agents.operator.tier | Should Be "lite"
    }
}

Describe "Merge-Configs" {
    Context "Basic Merging" {
        It "returns base config when override is null" {
            $base = @{ key = "value" }
            $result = Merge-Configs -Base $base -Override $null
            $result.key | Should Be "value"
        }

        It "overrides simple values" {
            $base = @{ key = "original" }
            $override = @{ key = "new" }
            $result = Merge-Configs -Base $base -Override $override
            $result.key | Should Be "new"
        }

        It "adds new keys from override" {
            $base = @{ existing = "value" }
            $override = @{ new_key = "new_value" }
            $result = Merge-Configs -Base $base -Override $override
            $result.existing | Should Be "value"
            $result.new_key | Should Be "new_value"
        }
    }

    Context "Deep Merging" {
        It "merges nested hashtables" {
            $base = @{
                ai = @{
                    provider = "anthropic"
                    temperature = 0.3
                }
            }
            $override = @{
                ai = @{
                    temperature = 0.5
                }
            }
            $result = Merge-Configs -Base $base -Override $override
            $result.ai.provider | Should Be "anthropic"
            $result.ai.temperature | Should Be 0.5
        }

        It "replaces arrays instead of merging them" {
            $base = @{ items = @(1, 2, 3) }
            $override = @{ items = @(4, 5) }
            $result = Merge-Configs -Base $base -Override $override
            $result.items.Count | Should Be 2
        }
    }
}
