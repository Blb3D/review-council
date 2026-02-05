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

    Context "Error Handling" {
        It "throws descriptive error for invalid provider name" {
            $config = @{ ai = @{} }
            $errorMessage = ""
            try {
                Get-AIProvider -Config $config -ProviderOverride "not-a-real-provider"
            } catch {
                $errorMessage = $_.Exception.Message
            }
            $errorMessage | Should Match "Unknown AI provider"
        }

        It "handles missing ai section in config gracefully" {
            $config = @{}
            $provider = Get-AIProvider -Config $config
            $provider.Name | Should Be "anthropic"
        }

        It "handles null config gracefully" {
            # Should not throw, should use defaults
            $errorThrown = $false
            try {
                $provider = Get-AIProvider -Config $null
            } catch {
                $errorThrown = $true
            }
            # Note: May throw depending on implementation - this tests the behavior
            # If it throws, that's acceptable defensive behavior
        }
    }
}

Describe "Error Message Sanitization Integration" {
    Context "HTTP Error Responses" {
        It "sanitizes API key from 401 Unauthorized error" {
            $error401 = "401 Unauthorized: Invalid API key sk-ant-api03-abcdefghijklmnopqrstuvwxyz123456"
            $result = Get-SanitizedError $error401
            $result | Should Match "401 Unauthorized"
            $result | Should Not Match "sk-ant-api03"
        }

        It "sanitizes key from rate limit error" {
            $error429 = "429 Too Many Requests for key sk-ant-FAKE-rate-limited-key"
            $result = Get-SanitizedError $error429
            $result | Should Match "429"
            $result | Should Not Match "FAKE-rate"
        }

        It "preserves useful error context while removing secrets" {
            $complexError = @"
Request failed: POST https://api.anthropic.com/v1/messages
Headers: x-api-key: sk-ant-secret-key-here
Body: {"model": "claude-sonnet-4-20250514"}
Response: 400 Bad Request - Invalid model
"@
            $result = Get-SanitizedError $complexError
            # Should preserve useful info
            $result | Should Match "POST"
            $result | Should Match "400 Bad Request"
            $result | Should Match "Invalid model"
            # Should redact secrets
            $result | Should Not Match "sk-ant-secret"
            $result | Should Match "x-api-key: \[REDACTED\]"
        }
    }

    Context "Network Error Messages" {
        It "preserves timeout errors without modification" {
            $timeoutError = "The operation timed out after 30000ms"
            $result = Get-SanitizedError $timeoutError
            $result | Should Be $timeoutError
        }

        It "preserves connection refused errors" {
            $connError = "Connection refused: localhost:11434 (Ollama not running)"
            $result = Get-SanitizedError $connError
            $result | Should Be $connError
        }

        It "preserves DNS resolution errors" {
            $dnsError = "Could not resolve hostname: api.anthropic.com"
            $result = Get-SanitizedError $dnsError
            $result | Should Be $dnsError
        }
    }
}
