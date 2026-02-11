<#
.SYNOPSIS
    Findings parser and JSON archival for Code Conclave.

.DESCRIPTION
    Parses AI-generated markdown findings into structured JSON format.
    Provides archival and cleanup functions for run history management.
#>

function ConvertFrom-FindingsMarkdown {
    <#
    .SYNOPSIS
        Parse AI markdown output into structured findings data.

    .PARAMETER Content
        Raw markdown string from AI agent.

    .PARAMETER AgentKey
        Agent identifier (e.g., "guardian").

    .PARAMETER AgentName
        Display name (e.g., "GUARDIAN").

    .PARAMETER AgentRole
        Agent role description.

    .PARAMETER RunTimestamp
        ISO 8601 timestamp for this run.

    .PARAMETER ProjectName
        Project display name.

    .PARAMETER ProjectPath
        Full path to the project.

    .PARAMETER DurationSeconds
        How long this agent took.

    .PARAMETER TokensUsed
        Hashtable with Input, Output, CacheRead, CacheWrite.

    .PARAMETER Tier
        Agent tier (primary or lite).

    .PARAMETER DryRun
        Whether this was a dry run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$AgentKey,

        [string]$AgentName,
        [string]$AgentRole,
        [string]$RunTimestamp,
        [string]$ProjectName,
        [string]$ProjectPath,
        [double]$DurationSeconds = 0,
        [hashtable]$TokensUsed,
        [string]$Tier = "primary",
        [switch]$DryRun
    )

    if (-not $RunTimestamp) {
        $RunTimestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    }

    # Parse individual findings from markdown
    $findings = @()

    # Find all code block regions to exclude from matching
    $codeBlockRanges = @()
    $codeBlockPattern = '```[\s\S]*?```'
    $codeMatches = [regex]::Matches($Content, $codeBlockPattern)
    foreach ($cm in $codeMatches) {
        $codeBlockRanges += @{ Start = $cm.Index; End = $cm.Index + $cm.Length }
    }

    # Pattern: ### AGENT-001: Title [SEVERITY]
    $pattern = '###\s+([A-Z]+\-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]'
    $headerMatches = [regex]::Matches($Content, $pattern)

    foreach ($match in $headerMatches) {
        # Skip matches inside code blocks
        $isInCodeBlock = $false
        foreach ($range in $codeBlockRanges) {
            if ($match.Index -ge $range.Start -and $match.Index -lt $range.End) {
                $isInCodeBlock = $true
                break
            }
        }
        if ($isInCodeBlock) { continue }

        $findingId = $match.Groups[1].Value
        $title = $match.Groups[2].Value.Trim()
        $severity = $match.Groups[3].Value

        # Extract the content between this header and the next ### or end
        $startPos = $match.Index + $match.Length
        $endPos = $Content.IndexOf('###', $startPos)
        if ($endPos -lt 0) { $endPos = $Content.Length }
        $section = $Content.Substring($startPos, $endPos - $startPos)

        # Extract structured fields from the section
        $file = $null
        $line = $null
        $effort = $null
        $issue = $null
        $evidence = $null
        $recommendation = $null

        # Location/File extraction - handles **Location:** `path:line` and **File:** path
        $locationMatch = [regex]::Match($section, '(?:\*\*)?(?:Location|File)(?:\*\*)?:?\*?\*?\s*`?([^\s`\r\n*]+(?::[^\s`\r\n*]*)?)`?')
        if ($locationMatch.Success) {
            $loc = $locationMatch.Groups[1].Value
            # Check for path:line format
            if ($loc -match '^(.+):(\d+)$') {
                $file = $Matches[1]
                $line = [int]$Matches[2]
            } else {
                $file = $loc
            }
        }

        # Line extraction (separate field) - only if not already parsed from Location
        if (-not $line) {
            $lineMatch = [regex]::Match($section, '(?:\*\*)?Line(?:\*\*)?:?\*?\*?\s*(\d+)')
            if ($lineMatch.Success) {
                $line = [int]$lineMatch.Groups[1].Value
            }
        }

        # Effort extraction
        $effortMatch = [regex]::Match($section, '(?:\*\*)?Effort(?:\*\*)?:?\*?\*?\s*([SML])\b')
        if ($effortMatch.Success) {
            $effort = $effortMatch.Groups[1].Value
        }

        # Section-based extraction for Issue, Evidence, Recommendation
        $issue = Get-SectionText -Content $section -Header "Issue"
        $evidence = Get-SectionText -Content $section -Header "Evidence"
        $recommendation = Get-SectionText -Content $section -Header "(?:Recommendation|Remediation)"

        # If no explicit issue section, use the remaining text as description
        if (-not $issue) {
            # Grab text that isn't part of a labeled section
            $plainText = $section -replace '\*\*(?:Location|File|Line|Effort|Evidence|Recommendation|Remediation|Issue)(?:\*\*)?:?[^\r\n]*', ''
            $plainText = $plainText -replace '```[\s\S]*?```', ''
            $plainText = $plainText -replace '---', ''
            $plainText = $plainText.Trim()
            if ($plainText) { $issue = $plainText }
        }

        $finding = [ordered]@{
            id = $findingId
            title = $title
            severity = $severity
        }
        if ($file) { $finding.file = $file }
        if ($null -ne $line) { $finding.line = $line }
        if ($effort) { $finding.effort = $effort }
        if ($issue) { $finding.issue = $issue }
        if ($evidence) { $finding.evidence = $evidence }
        if ($recommendation) { $finding.recommendation = $recommendation }

        $findings += $finding
    }

    # Calculate summary from parsed findings
    $summary = [ordered]@{
        blockers = @($findings | Where-Object { $_.severity -eq "BLOCKER" }).Count
        high     = @($findings | Where-Object { $_.severity -eq "HIGH" }).Count
        medium   = @($findings | Where-Object { $_.severity -eq "MEDIUM" }).Count
        low      = @($findings | Where-Object { $_.severity -eq "LOW" }).Count
        total    = $findings.Count
    }

    # Build tokens object
    $tokens = $null
    if ($TokensUsed) {
        $tokens = [ordered]@{}
        if ($TokensUsed.Input) { $tokens.input = [int]$TokensUsed.Input }
        if ($TokensUsed.Output) { $tokens.output = [int]$TokensUsed.Output }
        if ($TokensUsed.CacheRead) { $tokens.cacheRead = [int]$TokensUsed.CacheRead }
        if ($TokensUsed.CacheWrite) { $tokens.cacheWrite = [int]$TokensUsed.CacheWrite }
    }

    # Build the result
    $result = [ordered]@{
        version = "1.0.0"
        agent = [ordered]@{
            id   = $AgentKey
            name = if ($AgentName) { $AgentName } else { $AgentKey.ToUpper() }
            role = if ($AgentRole) { $AgentRole } else { "" }
            tier = $Tier
        }
        run = [ordered]@{
            timestamp      = $RunTimestamp
            project        = if ($ProjectName) { [string]$ProjectName } else { "" }
            projectPath    = if ($ProjectPath) { [string]$ProjectPath } else { "" }
            durationSeconds = [math]::Round($DurationSeconds, 2)
            dryRun         = [bool]$DryRun
        }
        status   = "complete"
        summary  = $summary
        findings = $findings
        rawMarkdown = $Content
    }

    if ($tokens) { $result.tokens = $tokens }

    return $result
}

function Get-SectionText {
    <#
    .SYNOPSIS
        Extract text content from a markdown section header within a finding.
    #>
    param(
        [string]$Content,
        [string]$Header
    )

    # Match **Header:** followed by content until the next **Header:** or end
    $sectionPattern = "(?:\*\*)?${Header}(?:\*\*)?:?\*?\*?\s*\r?\n([\s\S]*?)(?=\r?\n\*\*[A-Z]|\r?\n---|\Z)"
    $sectionMatch = [regex]::Match($Content, $sectionPattern)
    if ($sectionMatch.Success) {
        $text = $sectionMatch.Groups[1].Value.Trim()
        # Remove wrapping code blocks for cleaner text
        $text = $text -replace '^\s*```[a-z]*\s*\r?\n', ''
        $text = $text -replace '\r?\n\s*```\s*$', ''
        return $text.Trim()
    }
    return $null
}

function Export-FindingsJson {
    <#
    .SYNOPSIS
        Write findings data to a JSON file.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Findings,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $json = ConvertTo-Json -InputObject $Findings -Depth 20 -WarningAction SilentlyContinue
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    return $OutputPath
}

function Export-RunArchive {
    <#
    .SYNOPSIS
        Archive a completed run into a single timestamped JSON file.

    .PARAMETER ReviewsDir
        Path to the reviews directory.

    .PARAMETER AgentFindings
        Hashtable of parsed findings keyed by agent key. Each value is the
        output of ConvertFrom-FindingsMarkdown.

    .PARAMETER RunMetadata
        Hashtable with: Timestamp, Project, ProjectPath, Duration, DryRun,
        BaseBranch, Standard, Provider, AgentsRequested, Verdict, ExitCode.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ReviewsDir,

        [Parameter(Mandatory)]
        [hashtable]$AgentFindings,

        [Parameter(Mandatory)]
        [hashtable]$RunMetadata
    )

    $archiveDir = Join-Path $ReviewsDir "archive"
    if (-not (Test-Path $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }

    # Build timestamp-based filename
    $ts = if ($RunMetadata.Timestamp -is [datetime]) {
        $RunMetadata.Timestamp.ToString("yyyyMMddTHHmmss")
    } else {
        Get-Date -Format "yyyyMMddTHHmmss"
    }

    # Calculate aggregate summary
    $totalBlockers = 0; $totalHigh = 0; $totalMedium = 0; $totalLow = 0
    foreach ($af in $AgentFindings.Values) {
        if ($af -and $af.summary) {
            $totalBlockers += [int]$af.summary.blockers
            $totalHigh += [int]$af.summary.high
            $totalMedium += [int]$af.summary.medium
            $totalLow += [int]$af.summary.low
        }
    }

    # Build agents section (without rawMarkdown to keep archive smaller)
    $agentsData = [ordered]@{}
    foreach ($key in $AgentFindings.Keys) {
        $af = $AgentFindings[$key]
        if (-not $af) { continue }
        $agentsData[$key] = [ordered]@{
            name     = $af.agent.name
            role     = $af.agent.role
            tier     = $af.agent.tier
            status   = $af.status
            summary  = $af.summary
            findings = $af.findings
        }
        if ($af.tokens) { $agentsData[$key].tokens = $af.tokens }
        if ($af.run -and $af.run.durationSeconds) {
            $agentsData[$key].durationSeconds = $af.run.durationSeconds
        }
    }

    $durationVal = 0
    if ($RunMetadata.Duration -is [double] -or $RunMetadata.Duration -is [int]) {
        $durationVal = [math]::Round([double]$RunMetadata.Duration, 2)
    }

    $archive = [ordered]@{
        version = "1.0.0"
        run = [ordered]@{
            id              = $ts
            timestamp       = if ($RunMetadata.Timestamp -is [datetime]) { $RunMetadata.Timestamp.ToString("yyyy-MM-ddTHH:mm:ss") } else { Get-Date -Format "yyyy-MM-ddTHH:mm:ss" }
            project         = if ($RunMetadata.Project) { [string]$RunMetadata.Project } else { "" }
            projectPath     = if ($RunMetadata.ProjectPath) { [string]$RunMetadata.ProjectPath } else { "" }
            durationSeconds = $durationVal
            dryRun          = [bool]$RunMetadata.DryRun
            baseBranch      = if ($RunMetadata.BaseBranch) { [string]$RunMetadata.BaseBranch } else { $null }
            standard        = if ($RunMetadata.Standard) { [string]$RunMetadata.Standard } else { $null }
            provider        = if ($RunMetadata.Provider) { [string]$RunMetadata.Provider } else { "unknown" }
            agentsRequested = if ($RunMetadata.AgentsRequested) { @($RunMetadata.AgentsRequested) } else { @() }
        }
        verdict = if ($RunMetadata.Verdict) { $RunMetadata.Verdict } else { "UNKNOWN" }
        exitCode = if ($null -ne $RunMetadata.ExitCode) { [int]$RunMetadata.ExitCode } else { 0 }
        summary = [ordered]@{
            blockers = $totalBlockers
            high     = $totalHigh
            medium   = $totalMedium
            low      = $totalLow
            total    = $totalBlockers + $totalHigh + $totalMedium + $totalLow
        }
        agents = $agentsData
    }

    $archivePath = Join-Path $archiveDir "$ts.json"

    # Serialize sub-objects independently to avoid PowerShell ConvertTo-Json
    # stack overflow with deeply nested ordered hashtables
    $runJson = ConvertTo-Json -InputObject $archive.run -Depth 5 -Compress -WarningAction SilentlyContinue
    $summaryJson = ConvertTo-Json -InputObject $archive.summary -Depth 5 -Compress -WarningAction SilentlyContinue

    $agentParts = @()
    foreach ($akey in @($agentsData.Keys)) {
        $agentJson = ConvertTo-Json -InputObject $agentsData[$akey] -Depth 10 -WarningAction SilentlyContinue
        $agentParts += "    `"$akey`": $agentJson"
    }
    $agentsBlock = $agentParts -join ",`n"

    $json = @"
{
  "version": "$($archive.version)",
  "run": $runJson,
  "verdict": "$($archive.verdict)",
  "exitCode": $($archive.exitCode),
  "summary": $summaryJson,
  "agents": {
$agentsBlock
  }
}
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($archivePath, $json, $utf8NoBom)

    return $archivePath
}

function Remove-WorkingFindings {
    <#
    .SYNOPSIS
        Clean up working findings files from the reviews directory after archival.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ReviewsDir
    )

    # Remove per-agent JSON and markdown findings files
    $patterns = @("*-findings.json", "*-findings.md")
    foreach ($pat in $patterns) {
        $files = Get-ChildItem -Path $ReviewsDir -Filter $pat -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # Also remove synthesis report (it's regenerated each run)
    $synthesisPath = Join-Path $ReviewsDir "RELEASE-READINESS-REPORT.md"
    if (Test-Path $synthesisPath) {
        Remove-Item $synthesisPath -Force -ErrorAction SilentlyContinue
    }

    # Also remove JUnit XML (regenerated each run)
    $junitPath = Join-Path $ReviewsDir "conclave-results.xml"
    if (Test-Path $junitPath) {
        Remove-Item $junitPath -Force -ErrorAction SilentlyContinue
    }
}

# Note: Functions are exported via dot-sourcing, no Export-ModuleMember needed
