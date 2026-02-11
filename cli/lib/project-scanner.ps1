<#
.SYNOPSIS
    Project scanning utilities for Code Conclave.

.DESCRIPTION
    Functions to gather project context (file tree, source code) for AI analysis.
    Used by the AI provider abstraction to build prompts with project context.
#>

function Get-ProjectFileTree {
    <#
    .SYNOPSIS
        Generate a file tree representation of the project.
    .PARAMETER ProjectPath
        Root path of the project to scan.
    .PARAMETER MaxDepth
        Maximum directory depth to traverse.
    .PARAMETER ExcludeDirs
        Directory names to exclude from the tree.
    .RETURNS
        String containing a text-based tree representation.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [int]$MaxDepth = 4,

        [string[]]$ExcludeDirs = @(
            'node_modules', '.git', '__pycache__', '.venv', 'venv',
            'dist', 'build', '.next', '.nuxt', 'coverage', '.pytest_cache',
            '.code-conclave', '.review-council', '.claude', 'vendor',
            'bin', 'obj', '.vs', '.idea'
        )
    )

    $sb = [System.Text.StringBuilder]::new()

    function Add-TreeLevel {
        param($Path, $Prefix, $Depth)

        if ($Depth -gt $MaxDepth) { return }

        $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notin $ExcludeDirs } |
                 Sort-Object { -not $_.PSIsContainer }, Name

        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $isLast = ($i -eq $items.Count - 1)
            $connector = if ($isLast) { "+-- " } else { "|-- " }
            $extension = if ($isLast) { "    " } else { "|   " }

            [void]$sb.AppendLine("$Prefix$connector$($item.Name)")

            if ($item.PSIsContainer) {
                Add-TreeLevel -Path $item.FullName -Prefix "$Prefix$extension" -Depth ($Depth + 1)
            }
        }
    }

    [void]$sb.AppendLine((Split-Path $ProjectPath -Leaf))
    Add-TreeLevel -Path $ProjectPath -Prefix "" -Depth 1

    return $sb.ToString()
}

function Get-FileTier {
    <#
    .SYNOPSIS
        Classify a file into a priority tier for scanning.
    .PARAMETER File
        FileInfo object to classify.
    .PARAMETER ProjectPath
        Root path of the project (for relative path calculation).
    .RETURNS
        Integer tier (1=highest priority, 7=lowest).
    #>
    param(
        [Parameter(Mandatory)]
        $File,

        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $name = $File.Name.ToLower()
    $relativePath = $File.FullName.Replace($ProjectPath, '').TrimStart('\', '/').ToLower()
    $dirParts = $relativePath -split '[\\/]'

    # Tier 1: Entry points & config
    # Unambiguous entry points — always Tier 1 regardless of depth
    $tier1Always = @(
        'main.py', 'app.py', 'server.js', 'server.ts',
        'nginx.conf', 'dockerfile', 'manage.py', 'wsgi.py', 'asgi.py',
        '.env.example', 'requirements.txt', 'package.json', 'pyproject.toml',
        'setup.cfg', 'makefile', 'rakefile', 'gemfile',
        'go.mod', 'cargo.toml', 'pom.xml', 'build.gradle'
    )
    if ($name -in $tier1Always) { return 1 }
    if ($name -like 'docker-compose.*') { return 1 }
    # Ambiguous names (settings.py, config.*, setup.py) — only Tier 1 if NOT inside
    # an API/endpoint directory (prevents api/endpoints/settings.py from hogging Tier 1)
    $inApiDir = $false
    foreach ($part in $dirParts) {
        if ($part -in @('services', 'api', 'endpoints', 'controllers', 'handlers', 'routes')) {
            $inApiDir = $true; break
        }
    }
    if (-not $inApiDir) {
        if ($name -in @('settings.py', 'setup.py') -or $name -like 'config.*') { return 1 }
    }
    # index.js/ts only Tier 1 if near root (max 2 dirs deep, not barrel exports)
    if ($name -in @('index.js', 'index.ts') -and $dirParts.Count -le 3) { return 1 }

    # Tier 2: Core business logic (services, core, lib, utils, middleware, api, hooks)
    # Exclude test files and tiny __init__.py
    $tier2Dirs = @('services', 'core', 'lib', 'utils', 'middleware', 'api', 'hooks',
                   'controllers', 'handlers', 'routes', 'endpoints')
    $isInTier2Dir = $false
    foreach ($part in $dirParts) {
        if ($part -in $tier2Dirs) { $isInTier2Dir = $true; break }
    }
    if ($isInTier2Dir) {
        # Don't classify test files here (they go to Tier 4)
        $isTest = $name -like 'test_*' -or $name -like '*.test.*' -or $name -like '*.spec.*' -or $name -like '*.Tests.*'
        if (-not $isTest) { return 2 }
    }

    # Tier 3: Models & schemas
    $tier3Dirs = @('models', 'schemas', 'entities', 'types')
    foreach ($part in $dirParts) {
        if ($part -in $tier3Dirs) { return 3 }
    }

    # Tier 4: Tests
    $isTest = $name -like 'test_*' -or $name -like '*_test.*' -or $name -like '*.test.*' -or
              $name -like '*.Tests.*' -or $name -like '*.spec.*' -or $name -like 'conftest.py'
    $isInTestDir = $false
    foreach ($part in $dirParts) {
        if ($part -in @('tests', 'test', '__tests__', 'spec', 'specs')) { $isInTestDir = $true; break }
    }
    if ($isTest -or $isInTestDir) { return 4 }

    # Tier 5: Documentation
    $tier5Patterns = @('readme*', 'contributing*', 'changelog*', 'license*',
                       'rollback*', 'migration*', 'deployment*', 'backup*',
                       'operations*', 'runbook*', 'install*', 'architecture*')
    foreach ($pat in $tier5Patterns) {
        if ($name -like $pat) { return 5 }
    }
    $isInDocsDir = $false
    foreach ($part in $dirParts) {
        if ($part -in @('docs', 'documentation', 'doc')) { $isInDocsDir = $true; break }
    }
    if ($isInDocsDir -and $File.Extension.ToLower() -eq '.md') { return 5 }

    # Tier 6: Frontend components
    $tier6Dirs = @('components', 'pages', 'views', 'screens', 'layouts', 'templates')
    foreach ($part in $dirParts) {
        if ($part -in $tier6Dirs) { return 6 }
    }

    # Tier 7: Everything else
    return 7
}

function Get-SourceFilesContent {
    <#
    .SYNOPSIS
        Read source files for AI context using priority-based tier selection.
    .DESCRIPTION
        Classifies files into 7 priority tiers and fills a budget by selecting
        the most important files first. Skips empty boilerplate (<50 bytes)
        and oversized generated files (>50KB).
    .PARAMETER ProjectPath
        Root path of the project to scan.
    .PARAMETER MaxFiles
        Maximum number of files to include.
    .PARAMETER MaxSizeKB
        Maximum total size in kilobytes.
    .PARAMETER MinFileBytes
        Minimum file size to include (skip empty boilerplate). Default: 50 bytes.
    .PARAMETER MaxFileKB
        Maximum individual file size in KB. Default: 50KB.
    .RETURNS
        Hashtable with: Content (string), FileCount (int), TotalSizeKB (float), TotalEligible (int).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [int]$MaxFiles = 75,

        [int]$MaxSizeKB = 750,

        [int]$MinFileBytes = 50,

        [int]$MaxFileKB = 50,

        [string[]]$IncludeExtensions = @(
            '.ps1', '.py', '.js', '.ts', '.jsx', '.tsx', '.cs', '.java',
            '.go', '.rs', '.rb', '.php', '.swift', '.kt', '.scala',
            '.vue', '.svelte', '.html', '.css', '.scss', '.sql',
            '.yaml', '.yml', '.json', '.toml', '.md'
        ),

        [string[]]$ExcludeDirs = @(
            'node_modules', '.git', '__pycache__', '.venv', 'venv',
            'dist', 'build', '.next', '.nuxt', 'coverage', '.pytest_cache',
            '.code-conclave', '.review-council', '.claude', 'vendor',
            'bin', 'obj', '.vs', '.idea'
        ),

        [string[]]$ExcludePatterns = @(
            '*.min.js', '*.min.css', '*.map', '*.lock', 'package-lock.json',
            '*.generated.*', '*.g.cs', '*.designer.cs'
        )
    )

    $sb = [System.Text.StringBuilder]::new()
    $totalSize = 0
    $maxBytes = $MaxSizeKB * 1024
    $maxFileBytes = $MaxFileKB * 1024
    $fileCount = 0

    # Get all matching files with extension/dir/pattern filtering
    $allFiles = Get-ChildItem -Path $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object {
                 $file = $_
                 $ext = $file.Extension.ToLower()
                 $dir = $file.DirectoryName

                 # Check extension (or known entry-point names that bypass extension filter)
                 $tier1BypassNames = @(
                     'dockerfile', 'makefile', 'rakefile', 'gemfile', 'vagrantfile',
                     'nginx.conf', 'requirements.txt', '.env.example', '.gitignore',
                     'procfile', 'brewfile'
                 )
                 $extMatch = ($ext -in $IncludeExtensions) -or ($file.Name.ToLower() -in $tier1BypassNames)

                 # Check not in excluded directory
                 $dirExcluded = $false
                 foreach ($excludeDir in $ExcludeDirs) {
                     if ($dir -match "(\\|/)$([regex]::Escape($excludeDir))(\\|/|$)") {
                         $dirExcluded = $true
                         break
                     }
                 }

                 # Check not matching exclude patterns
                 $patternExcluded = $false
                 foreach ($pattern in $ExcludePatterns) {
                     if ($file.Name -like $pattern) {
                         $patternExcluded = $true
                         break
                     }
                 }

                 $extMatch -and -not $dirExcluded -and -not $patternExcluded
             }

    $totalEligible = @($allFiles).Count

    # Apply size filters: skip empty boilerplate and generated files
    $sizedFiles = @($allFiles | Where-Object {
        $_.Length -ge $MinFileBytes -and $_.Length -le $maxFileBytes
    })

    # Classify each file into tiers
    $tieredFiles = @($sizedFiles | ForEach-Object {
        $tier = Get-FileTier -File $_ -ProjectPath $ProjectPath
        [PSCustomObject]@{ File = $_; Tier = $tier }
    })

    # Group by tier, sort within each tier by size descending (prefer larger, more informative)
    $tierGroups = @{}
    foreach ($entry in $tieredFiles) {
        $t = $entry.Tier
        if (-not $tierGroups[$t]) { $tierGroups[$t] = @() }
        $tierGroups[$t] += $entry
    }
    foreach ($t in @($tierGroups.Keys)) {
        $tierGroups[$t] = @($tierGroups[$t] | Sort-Object { $_.File.Length } -Descending)
    }

    # Per-tier caps: file count AND size limit per tier (no single tier hogs budget)
    # Each tier limited to 30% of total budget, ensuring all tiers get representation
    $tierFileCaps = @{ 1 = 15; 2 = 15; 3 = 8; 4 = 10; 5 = 8; 6 = 10; 7 = 5 }
    $tierSizeCap = [math]::Floor($maxBytes * 0.30)  # 30% of total budget per tier

    # Pass 1: Select up to cap from each tier in priority order
    $selectedFiles = @()
    foreach ($t in (1..7)) {
        if (-not $tierGroups[$t]) { continue }
        $fileCap = $tierFileCaps[$t]
        $tierCount = 0
        $tierSize = 0
        foreach ($entry in $tierGroups[$t]) {
            if ($tierCount -ge $fileCap) { break }
            if ($fileCount + $selectedFiles.Count -ge $MaxFiles) { break }
            if ($totalSize + $entry.File.Length -gt $maxBytes) { continue }
            if ($tierSize + $entry.File.Length -gt $tierSizeCap) { continue }
            $selectedFiles += $entry
            $totalSize += $entry.File.Length
            $tierSize += $entry.File.Length
            $tierCount++
        }
    }

    # Pass 2: If budget remains, fill from unused files (by tier priority, largest first)
    if ($selectedFiles.Count -lt $MaxFiles -and $totalSize -lt $maxBytes) {
        $selectedPaths = @{}
        foreach ($s in $selectedFiles) { $selectedPaths[$s.File.FullName] = $true }
        $remaining = @($tieredFiles | Where-Object { -not $selectedPaths[$_.File.FullName] } |
                       Sort-Object { $_.Tier }, { $_.File.Length } -Descending)
        foreach ($entry in $remaining) {
            if ($fileCount + $selectedFiles.Count -ge $MaxFiles) { break }
            if ($totalSize + $entry.File.Length -gt $maxBytes) { continue }
            $selectedFiles += $entry
            $totalSize += $entry.File.Length
        }
    }

    # Reset totalSize for accurate counting during content reading
    $totalSize = 0

    # Build content from selected files (in tier order for readable output)
    $selectedFiles = @($selectedFiles | Sort-Object { $_.Tier }, { $_.File.Length } -Descending)

    foreach ($entry in $selectedFiles) {
        if ($fileCount -ge $MaxFiles) { break }
        $file = $entry.File

        if ($totalSize + $file.Length -gt $maxBytes) { continue }

        try {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not $content) { continue }

            $relativePath = $file.FullName.Replace($ProjectPath, '').TrimStart('\', '/')
            $langHint = $file.Extension.TrimStart('.')

            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("## File: $relativePath")
            [void]$sb.AppendLine('```' + $langHint)
            [void]$sb.AppendLine($content)
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine("")

            $totalSize += $file.Length
            $fileCount++
        }
        catch {
            continue
        }
    }

    if ($fileCount -eq 0) {
        return @{
            Content = "(No source files found matching criteria)"
            FileCount = 0
            TotalSizeKB = 0
            TotalEligible = $totalEligible
        }
    }

    [void]$sb.Insert(0, "# Source Files ($fileCount files, $([math]::Round($totalSize/1024, 1)) KB)`n`n")

    return @{
        Content = $sb.ToString()
        FileCount = $fileCount
        TotalSizeKB = [math]::Round($totalSize / 1024, 1)
        TotalEligible = $totalEligible
    }
}

function Get-DiffContext {
    <#
    .SYNOPSIS
        Get diff-scoped project context for PR/CI reviews.
    .DESCRIPTION
        Detects the base branch from CI environment variables or explicit parameter,
        then returns only changed files and their diff for targeted AI review.
    .PARAMETER ProjectPath
        Root path of the project (must be a git repo).
    .PARAMETER BaseBranch
        Explicit base branch to diff against. If not provided, auto-detects from
        CI environment: GITHUB_BASE_REF (GitHub Actions), SYSTEM_PULLREQUEST_TARGETBRANCH (ADO).
    .PARAMETER MaxDiffKB
        Maximum total diff size in KB before truncation.
    .PARAMETER MaxContentKB
        Maximum total changed files content in KB.
    .PARAMETER MaxFileKB
        Skip individual files larger than this.
    .RETURNS
        Hashtable with: ChangedFiles, FileContents, Diff, FileCount, TotalSizeKB.
        Returns $null if no base branch is available (triggers full scan fallback).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [string]$BaseBranch,

        [int]$MaxDiffKB = 100,

        [int]$MaxContentKB = 200,

        [int]$MaxFileKB = 50
    )

    # Auto-detect base branch from CI environment if not provided
    if (-not $BaseBranch) {
        $BaseBranch = if ($env:GITHUB_BASE_REF) { $env:GITHUB_BASE_REF }
                      elseif ($env:SYSTEM_PULLREQUEST_TARGETBRANCH) {
                          # ADO uses refs/heads/main format, strip prefix
                          $env:SYSTEM_PULLREQUEST_TARGETBRANCH -replace '^refs/heads/', ''
                      }
                      else { $null }
    }

    if (-not $BaseBranch) {
        return $null
    }

    # Verify we're in a git repo and the base branch exists
    try {
        $gitCheck = & git -C $ProjectPath rev-parse --is-inside-work-tree 2>&1
        if ($gitCheck -ne "true") { return $null }

        # Check if base branch exists (try with and without origin/)
        $baseRef = $null
        $candidates = @("origin/$BaseBranch", $BaseBranch)
        foreach ($ref in $candidates) {
            $check = & git -C $ProjectPath rev-parse --verify $ref 2>&1
            if ($LASTEXITCODE -eq 0) {
                $baseRef = $ref
                break
            }
        }
        if (-not $baseRef) { return $null }
    }
    catch {
        return $null
    }

    # Get list of changed files
    $changedFiles = & git -C $ProjectPath diff --name-only $baseRef 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $changedFiles) {
        return $null
    }
    $changedFiles = @($changedFiles | Where-Object { $_ -and $_ -notmatch '^fatal:' })
    if ($changedFiles.Count -eq 0) { return $null }

    # Get unified diff (with size limit)
    $diffContent = & git -C $ProjectPath diff $baseRef 2>&1
    if ($LASTEXITCODE -eq 0 -and $diffContent) {
        $diffText = ($diffContent | Out-String)
        $diffBytes = [System.Text.Encoding]::UTF8.GetByteCount($diffText)
        if ($diffBytes -gt ($MaxDiffKB * 1024)) {
            $truncateAt = $MaxDiffKB * 1024
            $diffText = $diffText.Substring(0, [math]::Min($truncateAt, $diffText.Length))
            $diffText += "`n`n[Diff truncated at ${MaxDiffKB}KB -- some files omitted. Full file contents included above.]"
        }
    } else {
        $diffText = "(diff unavailable)"
    }

    # Read full content of changed files (prioritize smallest first)
    $sb = [System.Text.StringBuilder]::new()
    $totalSize = 0
    $maxBytes = $MaxContentKB * 1024
    $maxFileBytes = $MaxFileKB * 1024
    $fileCount = 0

    $filesToRead = $changedFiles |
        ForEach-Object {
            $fullPath = Join-Path $ProjectPath $_
            if (Test-Path $fullPath -PathType Leaf) {
                $info = Get-Item $fullPath -ErrorAction SilentlyContinue
                if ($info -and $info.Length -le $maxFileBytes) {
                    [PSCustomObject]@{ RelPath = $_; FullPath = $fullPath; Size = $info.Length }
                }
            }
        } |
        Where-Object { $_ } |
        Sort-Object Size

    foreach ($file in $filesToRead) {
        if ($totalSize + $file.Size -gt $maxBytes) { continue }
        try {
            $content = Get-Content $file.FullPath -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not $content) { continue }
            $ext = [System.IO.Path]::GetExtension($file.RelPath).TrimStart('.')
            [void]$sb.AppendLine("---")
            [void]$sb.AppendLine("## File: $($file.RelPath)")
            [void]$sb.AppendLine('```' + $ext)
            [void]$sb.AppendLine($content)
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine("")
            $totalSize += $file.Size
            $fileCount++
        }
        catch { continue }
    }

    $fileContents = if ($fileCount -gt 0) {
        "# Changed Files ($fileCount files, $([math]::Round($totalSize/1024, 1)) KB)`n`n$($sb.ToString())"
    } else {
        "(No readable changed files found)"
    }

    return @{
        ChangedFiles = $changedFiles
        FileContents = $fileContents
        Diff         = $diffText
        FileCount    = $fileCount
        TotalSizeKB  = [math]::Round($totalSize / 1024, 1)
        BaseRef      = $baseRef
    }
}

# Export if running as module
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Get-ProjectFileTree, Get-FileTier, Get-SourceFilesContent, Get-DiffContext
}
