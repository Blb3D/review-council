<#
.SYNOPSIS
    Compliance mapping engine for Code Conclave.

.DESCRIPTION
    Maps code review findings to compliance standard controls.
    Supports wildcard pattern matching and generates coverage reports.
#>

# Ensure yaml-parser is loaded
$yamlParserPath = Join-Path $PSScriptRoot "yaml-parser.ps1"
if (Test-Path $yamlParserPath) {
    . $yamlParserPath
}

function ConvertTo-MarkdownSafe {
    <#
    .SYNOPSIS
        Escape special characters for use in markdown tables.
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    # Escape pipe characters which break markdown tables
    return $Text -replace '\|', '\|'
}

function Get-AvailableStandards {
    <#
    .SYNOPSIS
        Get list of all available compliance standards.
    #>
    param(
        [string]$StandardsDir
    )

    $standards = @()

    if (-not (Test-Path $StandardsDir)) {
        return $standards
    }

    $yamlFiles = Get-ChildItem -Path $StandardsDir -Recurse -Filter "*.yaml" -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -ne ".gitkeep" }

    foreach ($file in $yamlFiles) {
        try {
            $content = Get-YamlContent -Path $file.FullName
            if ($content -and $content.id) {
                $standards += @{
                    Id = $content.id
                    Name = $content.name
                    Domain = $content.domain
                    Version = $content.version
                    Description = $content.description
                    Path = $file.FullName
                }
            }
        }
        catch {
            Write-Warning "Failed to parse standard: $($file.FullName)"
        }
    }

    return $standards
}

function Get-StandardById {
    <#
    .SYNOPSIS
        Load a specific compliance standard by ID.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$StandardId,

        [Parameter(Mandatory)]
        [string]$StandardsDir
    )

    $standards = Get-AvailableStandards -StandardsDir $StandardsDir
    $match = $standards | Where-Object { $_.Id -eq $StandardId }

    if (-not $match) {
        return $null
    }

    return Get-YamlContent -Path $match.Path
}

function Get-AllControls {
    <#
    .SYNOPSIS
        Extract all controls from a compliance standard.
    .DESCRIPTION
        Handles both CMMC-style (domains) and FDA-style (subparts) structures.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Standard
    )

    $controls = @()

    # CMMC-style: domains -> controls
    if ($Standard.domains) {
        foreach ($domain in $Standard.domains) {
            if ($domain.controls) {
                foreach ($ctrl in $domain.controls) {
                    $controls += @{
                        Id = $ctrl.id
                        Title = $ctrl.title
                        DomainId = $domain.id
                        DomainName = $domain.name
                        Agents = $ctrl.agents
                        FindingPatterns = $ctrl.finding_patterns
                        Critical = $ctrl.critical -eq $true
                    }
                }
            }
        }
    }

    # FDA-style: subparts -> sections -> subsections
    if ($Standard.subparts) {
        foreach ($subpart in $Standard.subparts) {
            if ($subpart.sections) {
                foreach ($section in $subpart.sections) {
                    if ($section.subsections) {
                        foreach ($subsection in $section.subsections) {
                            $controls += @{
                                Id = $subsection.id
                                Title = $subsection.title
                                DomainId = $subpart.id
                                DomainName = $subpart.name
                                Agents = $subsection.agents
                                FindingPatterns = $subsection.finding_patterns
                                Critical = $subsection.critical -eq $true
                            }
                        }
                    }
                    else {
                        # Section without subsections is the control
                        $controls += @{
                            Id = $section.id
                            Title = $section.title
                            DomainId = $subpart.id
                            DomainName = $subpart.name
                            Agents = $section.agents
                            FindingPatterns = $section.finding_patterns
                            Critical = $section.critical -eq $true
                        }
                    }
                }
            }
        }
    }

    return $controls
}

function Test-FindingPattern {
    <#
    .SYNOPSIS
        Test if a finding ID matches a pattern.
    .DESCRIPTION
        Supports exact matches and wildcard patterns (e.g., GUARDIAN-*).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FindingId,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    # Handle wildcard patterns
    if ($Pattern -match '\*') {
        # Convert wildcard to regex: GUARDIAN-* -> ^GUARDIAN-.*$
        $regexPattern = "^" + [regex]::Escape($Pattern).Replace('\*', '.*') + "$"
        return $FindingId -match $regexPattern
    }

    # Exact match
    return $FindingId -eq $Pattern
}

function Match-FindingToControls {
    <#
    .SYNOPSIS
        Find all controls that a finding addresses.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Finding,

        [Parameter(Mandatory)]
        [array]$Controls
    )

    $matched = @()

    foreach ($control in $Controls) {
        if (-not $control.FindingPatterns) { continue }

        foreach ($pattern in $control.FindingPatterns) {
            if (Test-FindingPattern -FindingId $Finding.Id -Pattern $pattern) {
                $matched += $control
                break
            }
        }
    }

    return $matched
}

function Get-ComplianceMapping {
    <#
    .SYNOPSIS
        Generate a complete compliance mapping for findings against a standard.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Findings,

        [Parameter(Mandatory)]
        [hashtable]$Standard
    )

    $mapping = @{
        StandardId = $Standard.id
        StandardName = $Standard.name
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalControls = 0
        AddressedControls = 0
        GappedControls = 0
        CoveragePercent = 0
        ByDomain = @{}
        MappedFindings = @()
        Gaps = @()
        CriticalGaps = @()
    }

    # Get all controls
    $allControls = Get-AllControls -Standard $Standard
    $mapping.TotalControls = $allControls.Count

    # Track which controls are addressed
    $addressedControlIds = @{}

    # Match findings to controls
    foreach ($finding in $Findings) {
        $matchedControls = Match-FindingToControls -Finding $finding -Controls $allControls

        if ($matchedControls.Count -gt 0) {
            $mapping.MappedFindings += @{
                Finding = $finding
                Controls = $matchedControls
            }

            foreach ($ctrl in $matchedControls) {
                $addressedControlIds[$ctrl.Id] = $true
            }
        }
    }

    $mapping.AddressedControls = $addressedControlIds.Count
    $mapping.GappedControls = $mapping.TotalControls - $mapping.AddressedControls

    if ($mapping.TotalControls -gt 0) {
        $mapping.CoveragePercent = [math]::Round(
            ($mapping.AddressedControls / $mapping.TotalControls) * 100, 1
        )
    }

    # Identify gaps and critical gaps
    foreach ($control in $allControls) {
        if (-not $addressedControlIds.ContainsKey($control.Id)) {
            $mapping.Gaps += $control

            if ($control.Critical) {
                $mapping.CriticalGaps += $control
            }
        }
    }

    # Calculate domain coverage
    $domainGroups = $allControls | Group-Object -Property DomainId
    foreach ($group in $domainGroups) {
        $domainControls = $group.Group
        $domainAddressed = ($domainControls | Where-Object { $addressedControlIds.ContainsKey($_.Id) }).Count
        $domainTotal = $domainControls.Count

        $mapping.ByDomain[$group.Name] = @{
            Name = $domainControls[0].DomainName
            Total = $domainTotal
            Addressed = $domainAddressed
            Gaps = $domainTotal - $domainAddressed
            Coverage = if ($domainTotal -gt 0) { [math]::Round(($domainAddressed / $domainTotal) * 100, 1) } else { 0 }
        }
    }

    return $mapping
}

function Get-AgentControls {
    <#
    .SYNOPSIS
        Get controls relevant to a specific agent.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Standard,

        [Parameter(Mandatory)]
        [string]$AgentKey
    )

    $allControls = Get-AllControls -Standard $Standard
    $agentLower = $AgentKey.ToLower()

    return $allControls | Where-Object {
        $_.Agents -and ($_.Agents -contains $agentLower)
    }
}

function Export-ComplianceReport {
    <#
    .SYNOPSIS
        Generate a markdown compliance mapping report.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Mapping,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$ProjectName = "Project"
    )

    $sb = New-Object System.Text.StringBuilder

    # Header
    [void]$sb.AppendLine("# Compliance Mapping Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Standard:** $($Mapping.StandardName)")
    [void]$sb.AppendLine("**Project:** $ProjectName")
    [void]$sb.AppendLine("**Generated:** $($Mapping.Timestamp)")

    # Verdict
    $verdict = if ($Mapping.CriticalGaps.Count -gt 0) { "CRITICAL GAPS" }
               elseif ($Mapping.CoveragePercent -lt 50) { "LOW COVERAGE" }
               elseif ($Mapping.CoveragePercent -lt 80) { "PARTIAL COVERAGE" }
               else { "GOOD COVERAGE" }
    [void]$sb.AppendLine("**Verdict:** $verdict")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Executive Summary
    [void]$sb.AppendLine("## Executive Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Value |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Total Controls | $($Mapping.TotalControls) |")
    [void]$sb.AppendLine("| Controls Addressed | $($Mapping.AddressedControls) |")
    [void]$sb.AppendLine("| Gaps Identified | $($Mapping.GappedControls) |")
    [void]$sb.AppendLine("| Critical Gaps | $($Mapping.CriticalGaps.Count) |")
    [void]$sb.AppendLine("| Coverage | $($Mapping.CoveragePercent)% |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Coverage by Domain
    [void]$sb.AppendLine("## Coverage by Domain")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Domain | Controls | Addressed | Gaps | Coverage |")
    [void]$sb.AppendLine("|--------|----------|-----------|------|----------|")

    foreach ($domainId in ($Mapping.ByDomain.Keys | Sort-Object)) {
        $d = $Mapping.ByDomain[$domainId]
        $domainName = ConvertTo-MarkdownSafe -Text $d.Name
        [void]$sb.AppendLine("| $domainName ($domainId) | $($d.Total) | $($d.Addressed) | $($d.Gaps) | $($d.Coverage)% |")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Mapped Findings
    [void]$sb.AppendLine("## Mapped Findings")
    [void]$sb.AppendLine("")

    if ($Mapping.MappedFindings.Count -eq 0) {
        [void]$sb.AppendLine("*No findings were mapped to controls.*")
    }
    else {
        [void]$sb.AppendLine("| Finding | Severity | Controls Addressed |")
        [void]$sb.AppendLine("|---------|----------|-------------------|")

        foreach ($m in $Mapping.MappedFindings) {
            $controlIds = ($m.Controls | ForEach-Object { $_.Id }) -join ", "
            $findingTitle = ConvertTo-MarkdownSafe -Text $m.Finding.Title
            [void]$sb.AppendLine("| $($m.Finding.Id): $findingTitle | $($m.Finding.Severity) | $controlIds |")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Gap Analysis
    [void]$sb.AppendLine("## Gap Analysis")
    [void]$sb.AppendLine("")

    # Critical Gaps
    if ($Mapping.CriticalGaps.Count -gt 0) {
        [void]$sb.AppendLine("### Critical Gaps (Must Address)")
        [void]$sb.AppendLine("")

        foreach ($gap in $Mapping.CriticalGaps) {
            $agents = if ($gap.Agents) { ($gap.Agents -join ", ").ToUpper() } else { "N/A" }
            [void]$sb.AppendLine("- **$($gap.Id)** - $($gap.Title)")
            [void]$sb.AppendLine("  - Domain: $($gap.DomainName)")
            [void]$sb.AppendLine("  - Recommended agents: $agents")
            [void]$sb.AppendLine("")
        }
    }

    # All Gaps Summary
    if ($Mapping.Gaps.Count -gt 0) {
        [void]$sb.AppendLine("### All Gaps ($($Mapping.Gaps.Count) total)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("<details>")
        [void]$sb.AppendLine("<summary>View all gaps...</summary>")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Control | Title | Domain | Agents |")
        [void]$sb.AppendLine("|---------|-------|--------|--------|")

        foreach ($gap in $Mapping.Gaps) {
            $agents = if ($gap.Agents) { ($gap.Agents -join ", ").ToUpper() } else { "-" }
            $critical = if ($gap.Critical) { " **" } else { "" }
            $gapTitle = ConvertTo-MarkdownSafe -Text $gap.Title
            $gapDomain = ConvertTo-MarkdownSafe -Text $gap.DomainName
            [void]$sb.AppendLine("| $($gap.Id)$critical | $gapTitle | $gapDomain | $agents |")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("</details>")
    }
    else {
        [void]$sb.AppendLine("*No gaps identified - all controls are addressed!*")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Next Steps
    [void]$sb.AppendLine("## Next Steps")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("1. Address critical gaps first (if any)")
    [void]$sb.AppendLine("2. Run targeted agent reviews with ``-Standard $($Mapping.StandardId)`` flag")
    [void]$sb.AppendLine("3. Document gap remediation in your compliance documentation")
    [void]$sb.AppendLine("4. Re-run mapping to verify improved coverage")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Code Conclave Compliance Engine*")

    # Write to file
    $sb.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8

    return $OutputPath
}

# Export functions
Export-ModuleMember -Function Get-AvailableStandards, Get-StandardById, Get-AllControls,
                              Test-FindingPattern, Match-FindingToControls, Get-ComplianceMapping,
                              Get-AgentControls, Export-ComplianceReport -ErrorAction SilentlyContinue
