<#
.SYNOPSIS
    Pester tests for ai-engine.ps1

.DESCRIPTION
    Tests for AI provider abstraction layer, including error sanitization
    and provider selection.
#>

# Load the module under test
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here ".." "lib" "ai-engine.ps1")

Describe "Get-SanitizedError" {
    Context "API Key Redaction" {
        It "redacts Anthropic API keys (sk-ant-*)" {
            $input = "Error: Invalid API key sk-ant-FAKE-TEST-KEY-NOT-REAL-abcdef123456"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'sk-ant-'
            $result | Should Match '\[REDACTED_KEY\]'
        }

        It "redacts OpenAI API keys (sk-*)" {
            $input = "Error: sk-proj-abc123def456ghijklmnopqrstuvwxyz"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'sk-proj-'
            $result | Should Match '\[REDACTED_KEY\]'
        }

        It "redacts Bearer tokens" {
            $input = "Header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secret"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'eyJhbGc'
            $result | Should Match 'Bearer \[REDACTED\]'
        }

        It "redacts api-key headers" {
            $input = "Request failed: api-key: my-secret-azure-key-12345"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'my-secret-azure'
            $result | Should Match 'api-key: \[REDACTED\]'
        }

        It "redacts x-api-key headers" {
            $input = "Headers: x-api-key: anthropic-secret-key"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'anthropic-secret'
            $result | Should Match 'x-api-key: \[REDACTED\]'
        }

        It "redacts Authorization headers" {
            $input = "Authorization: Basic-Token-Value"
            $result = Get-SanitizedError $input
            $result | Should Match 'Authorization: \[REDACTED\]'
        }
    }

    Context "Edge Cases" {
        It "returns null for null input" {
            $result = Get-SanitizedError $null
            $result | Should BeNullOrEmpty
        }

        It "returns empty string for empty input" {
            $result = Get-SanitizedError ""
            $result | Should Be ""
        }

        It "preserves non-sensitive error messages" {
            $input = "Connection timeout after 30 seconds"
            $result = Get-SanitizedError $input
            $result | Should Be $input
        }

        It "handles multiple keys in one message" {
            $input = "Keys: sk-ant-FAKE-key1 and sk-FAKE-key2-abcdefghijklmnopqrstuvwxyz"
            $result = Get-SanitizedError $input
            $result | Should Not Match 'sk-ant-'
            $result | Should Not Match 'sk-FAKE-key2'
        }
    }
}

Describe "Get-AIProvider" {
    Context "Provider Selection" {
        It "defaults to anthropic when no provider specified" {
            $config = @{ ai = @{} }
            $provider = Get-AIProvider -Config $config
            $provider.Name | Should Be "anthropic"
        }

        It "respects provider in config" {
            $config = @{ ai = @{ provider = "openai" } }
            $provider = Get-AIProvider -Config $config
            $provider.Name | Should Be "openai"
        }

        It "respects provider override parameter" {
            $config = @{ ai = @{ provider = "anthropic" } }
            $provider = Get-AIProvider -Config $config -ProviderOverride "azure-openai"
            $provider.Name | Should Be "azure-openai"
        }

        It "throws for unknown provider" {
            $config = @{ ai = @{} }
            $errorThrown = $false
            try {
                Get-AIProvider -Config $config -ProviderOverride "unknown-provider"
            } catch {
                $errorThrown = $true
            }
            $errorThrown | Should Be $true
        }
    }

    Context "Provider Configuration" {
        It "returns provider-specific config" {
            $config = @{
                ai = @{
                    provider = "anthropic"
                    anthropic = @{
                        model = "claude-sonnet-4-20250514"
                        max_tokens = 8000
                    }
                }
            }
            $provider = Get-AIProvider -Config $config
            $provider.Config.model | Should Be "claude-sonnet-4-20250514"
            $provider.Config.max_tokens | Should Be 8000
        }

        It "applies model override" {
            $config = @{
                ai = @{
                    provider = "anthropic"
                    anthropic = @{ model = "claude-sonnet-4-20250514" }
                }
            }
            $provider = Get-AIProvider -Config $config -ModelOverride "claude-haiku-4-5-20251001"
            $provider.Config.model | Should Be "claude-haiku-4-5-20251001"
        }
    }
}
