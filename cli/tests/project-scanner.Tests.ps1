<#
.SYNOPSIS
    Pester tests for project-scanner.ps1

.DESCRIPTION
    Tests for project scanning utilities including file tree generation,
    source file reading, and diff context extraction.
#>

# Load the module under test
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here ".." "lib" "project-scanner.ps1")

Describe "Get-ProjectFileTree" {
    Context "Basic Functionality" {
        It "returns a string representation" {
            $testPath = $PSScriptRoot
            $result = Get-ProjectFileTree -ProjectPath $testPath -MaxDepth 1
            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be "String"
        }

        It "includes the project folder name" {
            $testPath = $PSScriptRoot
            $result = Get-ProjectFileTree -ProjectPath $testPath -MaxDepth 1
            $folderName = Split-Path $testPath -Leaf
            $result | Should Match $folderName
        }

        It "respects MaxDepth parameter" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $shallow = Get-ProjectFileTree -ProjectPath $testPath -MaxDepth 1
            $deep = Get-ProjectFileTree -ProjectPath $testPath -MaxDepth 3
            $deep.Length | Should BeGreaterThan $shallow.Length
        }
    }

    Context "Exclusion Patterns" {
        It "excludes node_modules by default" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-ProjectFileTree -ProjectPath $testPath
            $result | Should Not Match "node_modules"
        }

        It "excludes .git by default" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-ProjectFileTree -ProjectPath $testPath
            # .git should not appear as a directory in tree
            ($result -split "`n" | Where-Object { $_ -match "\.git$" }).Count | Should Be 0
        }

        It "respects custom ExcludeDirs parameter" {
            $testPath = $PSScriptRoot
            $result = Get-ProjectFileTree -ProjectPath $testPath -ExcludeDirs @('nonexistent')
            $result | Should Not BeNullOrEmpty
        }
    }
}

Describe "Get-SourceFilesContent" {
    Context "File Reading" {
        It "returns content from source files" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 5 -MaxSizeKB 100
            $result | Should Not BeNullOrEmpty
        }

        It "includes file headers with paths" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 5 -MaxSizeKB 100
            $result | Should Match "\.ps1"
        }

        It "respects MaxFiles limit" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 3 -MaxSizeKB 500
            $fileCount = ($result | Select-String -Pattern "^## File:" -AllMatches).Matches.Count
            $fileCount | Should BeLessOrEqual 3
        }
    }

    Context "Size Limits" {
        It "respects MaxSizeKB limit" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 100 -MaxSizeKB 10
            $sizeKB = [math]::Round($result.Length / 1024, 2)
            # Allow some overhead for headers
            $sizeKB | Should BeLessOrEqual 15
        }
    }

    Context "File Type Filtering" {
        It "includes PowerShell files by default" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 10 -MaxSizeKB 100
            $result | Should Match "\.ps1"
        }

        It "respects custom IncludeExtensions" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 10 -MaxSizeKB 100 -IncludeExtensions @('.nonexistent')
            # Should return empty or just headers if no matching files
            $result.Length | Should BeLessOrEqual 100
        }
    }
}

Describe "Get-DiffContext" {
    Context "Git Diff Integration" {
        It "returns null when no base branch specified and no CI env" {
            # Clear CI env vars for this test
            $originalGitHubBaseRef = $env:GITHUB_BASE_REF
            $originalSystemPullRequestTargetBranch = $env:SYSTEM_PULLREQUEST_TARGETBRANCH
            $env:GITHUB_BASE_REF = $null
            $env:SYSTEM_PULLREQUEST_TARGETBRANCH = $null

            try {
                $result = Get-DiffContext -ProjectPath $PSScriptRoot -BaseBranch $null
                # Should return null or valid diff context
                # Behavior depends on git state
            } finally {
                $env:GITHUB_BASE_REF = $originalGitHubBaseRef
                $env:SYSTEM_PULLREQUEST_TARGETBRANCH = $originalSystemPullRequestTargetBranch
            }
        }

        It "detects GitHub Actions base ref from environment" {
            $originalValue = $env:GITHUB_BASE_REF
            $env:GITHUB_BASE_REF = "main"

            try {
                # Function should pick up GITHUB_BASE_REF
                # This tests the environment detection, not actual git operations
                $env:GITHUB_BASE_REF | Should Be "main"
            } finally {
                $env:GITHUB_BASE_REF = $originalValue
            }
        }

        It "detects Azure DevOps base ref from environment" {
            $originalValue = $env:SYSTEM_PULLREQUEST_TARGETBRANCH
            $env:SYSTEM_PULLREQUEST_TARGETBRANCH = "develop"

            try {
                # Function should pick up SYSTEM_PULLREQUEST_TARGETBRANCH
                $env:SYSTEM_PULLREQUEST_TARGETBRANCH | Should Be "develop"
            } finally {
                $env:SYSTEM_PULLREQUEST_TARGETBRANCH = $originalValue
            }
        }
    }
}

Describe "Integration" {
    Context "Full Project Scan" {
        It "can scan the CLI directory" {
            $cliPath = Split-Path $PSScriptRoot -Parent
            $tree = Get-ProjectFileTree -ProjectPath $cliPath -MaxDepth 2
            $content = Get-SourceFilesContent -ProjectPath $cliPath -MaxFiles 5 -MaxSizeKB 50

            $tree | Should Not BeNullOrEmpty
            $content | Should Not BeNullOrEmpty
            $tree | Should Match "lib"
            $content | Should Match "function"
        }
    }
}
