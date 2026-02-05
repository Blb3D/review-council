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

# Export if running as module
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function Get-ProjectFileTree, Get-SourceFilesContent
}
