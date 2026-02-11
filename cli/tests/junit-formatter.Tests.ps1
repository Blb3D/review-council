<#
.SYNOPSIS
    Pester tests for junit-formatter.ps1

.DESCRIPTION
    Tests for JUnit XML output generation.
#>

# Load the module under test
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Join-Path (Join-Path $here "..") "lib") "junit-formatter.ps1")

Describe "Export-JUnitResults" {
    $testOutputDir = Join-Path $env:TEMP "junit-test-output"

    # Setup test directory
    if (-not (Test-Path $testOutputDir)) {
        New-Item -ItemType Directory -Path $testOutputDir -Force | Out-Null
    }

    Context "XML Structure" {
        It "creates valid XML file" {
            $findings = @{
                guardian = @(
                    @{ Id = "GUARDIAN-001"; Title = "Test Finding"; Severity = "HIGH" }
                )
            }
            $outputPath = Join-Path $testOutputDir "test-results.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            Test-Path $outputPath | Should Be $true
            $xml = [xml](Get-Content $outputPath)
            $xml | Should Not BeNullOrEmpty
        }

        It "creates testsuites root element" {
            $findings = @{
                sentinel = @(
                    @{ Id = "SENTINEL-001"; Title = "Test"; Severity = "MEDIUM" }
                )
            }
            $outputPath = Join-Path $testOutputDir "structure-test.xml"

            Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $xml = [xml](Get-Content $outputPath)
            $xml.testsuites | Should Not BeNullOrEmpty
            $xml.testsuites.name | Should Be "Code Conclave"
        }

        It "creates testsuite per agent" {
            $findings = @{
                guardian = @(@{ Id = "G-001"; Title = "G Test"; Severity = "HIGH" })
                sentinel = @(@{ Id = "S-001"; Title = "S Test"; Severity = "MEDIUM" })
            }
            $outputPath = Join-Path $testOutputDir "multi-agent.xml"

            Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $xml = [xml](Get-Content $outputPath)
            $xml.testsuites.testsuite.Count | Should Be 2
        }
    }

    Context "Severity Handling" {
        It "marks BLOCKER as failure" {
            $findings = @{
                guardian = @(
                    @{ Id = "G-001"; Title = "Blocker Issue"; Severity = "BLOCKER" }
                )
            }
            $outputPath = Join-Path $testOutputDir "blocker-test.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $result.Failures | Should Be 1
            $xml = [xml](Get-Content $outputPath)
            $xml.testsuites.testsuite.testcase.failure | Should Not BeNullOrEmpty
        }

        It "marks HIGH as failure by default" {
            $findings = @{
                guardian = @(
                    @{ Id = "G-001"; Title = "High Issue"; Severity = "HIGH" }
                )
            }
            $outputPath = Join-Path $testOutputDir "high-test.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $result.Failures | Should Be 1
        }

        It "marks MEDIUM as passed by default" {
            $findings = @{
                guardian = @(
                    @{ Id = "G-001"; Title = "Medium Issue"; Severity = "MEDIUM" }
                )
            }
            $outputPath = Join-Path $testOutputDir "medium-test.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $result.Failures | Should Be 0
            $result.Passed | Should Be 1
        }

        It "marks LOW as passed" {
            $findings = @{
                guardian = @(
                    @{ Id = "G-001"; Title = "Low Issue"; Severity = "LOW" }
                )
            }
            $outputPath = Join-Path $testOutputDir "low-test.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $result.Failures | Should Be 0
        }
    }

    Context "Return Value" {
        It "returns correct statistics" {
            $findings = @{
                guardian = @(
                    @{ Id = "G-001"; Title = "Blocker"; Severity = "BLOCKER" }
                    @{ Id = "G-002"; Title = "High"; Severity = "HIGH" }
                    @{ Id = "G-003"; Title = "Medium"; Severity = "MEDIUM" }
                    @{ Id = "G-004"; Title = "Low"; Severity = "LOW" }
                )
            }
            $outputPath = Join-Path $testOutputDir "stats-test.xml"

            $result = Export-JUnitResults -AllFindings $findings -OutputPath $outputPath

            $result.TotalTests | Should Be 4
            $result.Failures | Should Be 2
            $result.Passed | Should Be 2
            $result.Path | Should Be $outputPath
        }
    }

    # Cleanup
    if (Test-Path $testOutputDir) {
        Remove-Item -Path $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
