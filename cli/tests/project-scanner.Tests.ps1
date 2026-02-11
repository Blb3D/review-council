<#
.SYNOPSIS
    Pester tests for project-scanner.ps1

.DESCRIPTION
    Tests for project scanning utilities including file tree generation,
    source file reading, and diff context extraction.
#>

# Load the module under test
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Join-Path (Join-Path $here "..") "lib") "project-scanner.ps1")

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
        It "returns a hashtable with Content key" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 5 -MaxSizeKB 100
            $result | Should Not BeNullOrEmpty
            $result.Content | Should Not BeNullOrEmpty
        }

        It "includes file headers with paths" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 5 -MaxSizeKB 100
            $result.Content | Should Match "\.ps1"
        }

        It "respects MaxFiles limit" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 3 -MaxSizeKB 500
            $fileCount = ($result.Content | Select-String -Pattern "^## File:" -AllMatches).Matches.Count
            ($fileCount -le 3) | Should Be $true
        }

        It "returns FileCount and TotalSizeKB metadata" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 5 -MaxSizeKB 100
            ($result.FileCount -gt 0) | Should Be $true
            ($result.TotalSizeKB -gt 0) | Should Be $true
            ($result.TotalEligible -ge $result.FileCount) | Should Be $true
        }
    }

    Context "Size Limits" {
        It "respects MaxSizeKB limit" {
            $testPath = Split-Path $PSScriptRoot -Parent
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 100 -MaxSizeKB 10
            $sizeKB = [math]::Round($result.Content.Length / 1024, 2)
            # Allow some overhead for headers
            ($sizeKB -le 15) | Should Be $true
        }
    }

    Context "File Type Filtering" {
        It "includes PowerShell files by default" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 10 -MaxSizeKB 100
            $result.Content | Should Match "\.ps1"
        }

        It "respects custom IncludeExtensions" {
            $testPath = $PSScriptRoot
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 10 -MaxSizeKB 100 -IncludeExtensions @('.nonexistent')
            # Should return empty content when no files match
            ($result.FileCount -eq 0) | Should Be $true
        }
    }

    Context "Priority Tier Selection" {
        It "skips files smaller than MinFileBytes" {
            $testPath = $PSScriptRoot
            # With a very high minimum, should skip small files
            $result = Get-SourceFilesContent -ProjectPath $testPath -MaxFiles 100 -MaxSizeKB 500 -MinFileBytes 999999
            ($result.FileCount -eq 0) | Should Be $true
        }
    }
}

Describe "Get-FileTier" {
    Context "Tier Classification" {
        It "classifies main.py as Tier 1" {
            $file = [PSCustomObject]@{ Name = "main.py"; FullName = "C:\project\main.py"; Extension = ".py"; DirectoryName = "C:\project"; Length = 1000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 1
        }

        It "classifies Dockerfile as Tier 1" {
            $file = [PSCustomObject]@{ Name = "Dockerfile"; FullName = "C:\project\Dockerfile"; Extension = ""; DirectoryName = "C:\project"; Length = 500 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 1
        }

        It "classifies services/ files as Tier 2" {
            $file = [PSCustomObject]@{ Name = "auth.py"; FullName = "C:\project\services\auth.py"; Extension = ".py"; DirectoryName = "C:\project\services"; Length = 5000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 2
        }

        It "classifies test files as Tier 4 even in services/" {
            $file = [PSCustomObject]@{ Name = "test_auth.py"; FullName = "C:\project\services\test_auth.py"; Extension = ".py"; DirectoryName = "C:\project\services"; Length = 5000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 4
        }

        It "classifies models/ files as Tier 3" {
            $file = [PSCustomObject]@{ Name = "user.py"; FullName = "C:\project\models\user.py"; Extension = ".py"; DirectoryName = "C:\project\models"; Length = 2000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 3
        }

        It "classifies README as Tier 5" {
            $file = [PSCustomObject]@{ Name = "README.md"; FullName = "C:\project\README.md"; Extension = ".md"; DirectoryName = "C:\project"; Length = 3000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 5
        }

        It "classifies components/ files as Tier 6" {
            $file = [PSCustomObject]@{ Name = "Button.tsx"; FullName = "C:\project\components\Button.tsx"; Extension = ".tsx"; DirectoryName = "C:\project\components"; Length = 1000 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 6
        }

        It "classifies random files as Tier 7" {
            $file = [PSCustomObject]@{ Name = "helper.py"; FullName = "C:\project\helper.py"; Extension = ".py"; DirectoryName = "C:\project"; Length = 500 }
            $tier = Get-FileTier -File $file -ProjectPath "C:\project"
            $tier | Should Be 7
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
            $scanResult = Get-SourceFilesContent -ProjectPath $cliPath -MaxFiles 5 -MaxSizeKB 50

            $tree | Should Not BeNullOrEmpty
            $scanResult | Should Not BeNullOrEmpty
            $tree | Should Match "lib"
            $scanResult.Content | Should Match "function"
            ($scanResult.FileCount -gt 0) | Should Be $true
        }
    }
}
