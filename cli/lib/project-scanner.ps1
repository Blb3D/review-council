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
            $connector = if ($isLast) { "└── " } else { "├── " }
            $extension = if ($isLast) { "    " } else { "│   " }

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

function Get-SourceFilesContent {
    <#
    .SYNOPSIS
        Read source files for AI context, with size limits.
    .PARAMETER ProjectPath
        Root path of the project to scan.
    .PARAMETER MaxFiles
        Maximum number of files to include.
    .PARAMETER MaxSizeKB
        Maximum total size in kilobytes.
    .RETURNS
        String containing concatenated source file contents with headers.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [int]$MaxFiles = 50,

        [int]$MaxSizeKB = 500,

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
    $fileCount = 0

    # Get all matching files
    $files = Get-ChildItem -Path $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object {
                 $file = $_
                 $ext = $file.Extension.ToLower()
                 $dir = $file.DirectoryName

                 # Check extension
                 $extMatch = $ext -in $IncludeExtensions

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
             } |
             Sort-Object Length |
             Select-Object -First ($MaxFiles * 2)

    foreach ($file in $files) {
        if ($fileCount -ge $MaxFiles) { break }
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
        return "(No source files found matching criteria)"
    }

    [void]$sb.Insert(0, "# Source Files ($fileCount files, $([math]::Round($totalSize/1024, 1)) KB)`n`n")

    return $sb.ToString()
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
            $diffText += "`n`n[Diff truncated at ${MaxDiffKB}KB — some files omitted. Full file contents included above.]"
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
    Export-ModuleMember -Function Get-ProjectFileTree, Get-SourceFilesContent, Get-DiffContext
}
