<#
.SYNOPSIS
    JUnit XML formatter for Code Conclave findings.

.DESCRIPTION
    Converts Code Conclave findings to JUnit XML format compatible with
    Azure DevOps, Jenkins, and other CI systems.
#>

function Export-JUnitResults {
    <#
    .SYNOPSIS
        Export findings as JUnit XML.

    .PARAMETER AllFindings
        Hashtable of findings keyed by agent name.
        Each value is an array of finding objects with: Id, Title, Severity, File, Line, Description

    .PARAMETER OutputPath
        Path to write the XML file.

    .PARAMETER FailOn
        Array of severities that should be marked as failures. Default: @("BLOCKER", "HIGH")

    .PARAMETER ProjectName
        Name to use in the testsuites element.

    .PARAMETER Duration
        Total duration in seconds (optional).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$AllFindings,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string[]]$FailOn = @("BLOCKER", "HIGH"),

        [string]$ProjectName = "Code Conclave",

        [double]$Duration = 0
    )

    # Create XML document
    $xml = New-Object System.Xml.XmlDocument
    $declaration = $xml.CreateXmlDeclaration("1.0", "UTF-8", $null)
    [void]$xml.AppendChild($declaration)

    # Root element: <testsuites>
    $testsuites = $xml.CreateElement("testsuites")
    $testsuites.SetAttribute("name", $ProjectName)
    $testsuites.SetAttribute("timestamp", (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"))

    $totalTests = 0
    $totalFailures = 0
    $totalSkipped = 0

    # Process each agent as a testsuite
    foreach ($agentKey in $AllFindings.Keys) {
        $findings = $AllFindings[$agentKey]
        $agentName = $agentKey.ToUpper()

        # Skip empty findings arrays
        if ($null -eq $findings -or $findings.Count -eq 0) {
            continue
        }

        $testsuite = $xml.CreateElement("testsuite")
        $testsuite.SetAttribute("name", $agentName)
        $testsuite.SetAttribute("tests", $findings.Count)

        $suiteFailures = 0

        foreach ($finding in $findings) {
            $totalTests++

            # Create testcase
            $testcase = $xml.CreateElement("testcase")
            $testcase.SetAttribute("name", "$($finding.Id): $($finding.Title)")
            $testcase.SetAttribute("classname", $agentName)

            # Add file/line if available
            if ($finding.File) {
                $testcase.SetAttribute("file", $finding.File)
            }
            if ($finding.Line) {
                $testcase.SetAttribute("line", $finding.Line.ToString())
            }

            # Determine if this is a failure
            $isFailure = $FailOn -contains $finding.Severity

            if ($isFailure) {
                $totalFailures++
                $suiteFailures++

                $failure = $xml.CreateElement("failure")
                $failure.SetAttribute("message", "[$($finding.Severity)] $($finding.Title)")
                $failure.SetAttribute("type", $finding.Severity.ToLower())

                # Build failure content
                $failureText = @()
                $failureText += "Severity: $($finding.Severity)"
                if ($finding.File) { $failureText += "File: $($finding.File)" }
                if ($finding.Line) { $failureText += "Line: $($finding.Line)" }
                if ($finding.Description) { $failureText += "`nDescription:`n$($finding.Description)" }
                if ($finding.Remediation) { $failureText += "`nRemediation:`n$($finding.Remediation)" }

                $failure.InnerText = $failureText -join "`n"
                [void]$testcase.AppendChild($failure)
            }

            [void]$testsuite.AppendChild($testcase)
        }

        $testsuite.SetAttribute("failures", $suiteFailures)
        $testsuite.SetAttribute("errors", "0")
        $testsuite.SetAttribute("skipped", "0")

        [void]$testsuites.AppendChild($testsuite)
    }

    # Set totals on root element
    $testsuites.SetAttribute("tests", $totalTests)
    $testsuites.SetAttribute("failures", $totalFailures)
    $testsuites.SetAttribute("errors", "0")
    if ($Duration -gt 0) {
        $testsuites.SetAttribute("time", [math]::Round($Duration, 2).ToString())
    }

    [void]$xml.AppendChild($testsuites)

    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Save XML
    $xml.Save($OutputPath)

    return @{
        Path = $OutputPath
        TotalTests = $totalTests
        Failures = $totalFailures
        Passed = $totalTests - $totalFailures
    }
}

function Get-FindingsForJUnit {
    <#
    .SYNOPSIS
        Parse findings from markdown files for JUnit export.

    .PARAMETER ReviewsDir
        Path to the reviews directory containing agent findings files.

    .PARAMETER AgentDefs
        Hashtable of agent definitions.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ReviewsDir,

        [Parameter(Mandatory)]
        [hashtable]$AgentDefs
    )

    $junitFindings = @{}

    foreach ($agentKey in $AgentDefs.Keys) {
        $junitFindings[$agentKey] = @()
        $findingsFile = Join-Path $ReviewsDir "$agentKey-findings.md"

        if (Test-Path $findingsFile) {
            $content = Get-Content $findingsFile -Raw

            # Pattern: ### AGENT-001: Title [SEVERITY]
            # Also capture the content after each finding header for description
            $pattern = '###\s+([A-Z]+\-\d+):\s*(.+?)\s*\[(BLOCKER|HIGH|MEDIUM|LOW)\]'
            $matches = [regex]::Matches($content, $pattern)

            foreach ($match in $matches) {
                $findingId = $match.Groups[1].Value
                $title = $match.Groups[2].Value.Trim()
                $severity = $match.Groups[3].Value

                # Try to extract file and line from the content following the header
                $startPos = $match.Index + $match.Length
                $endPos = $content.IndexOf('###', $startPos)
                if ($endPos -lt 0) { $endPos = $content.Length }
                $findingContent = $content.Substring($startPos, $endPos - $startPos)

                # Look for file patterns like "File: src/config.js" or "**File:** `src/config.js`"
                # Handle markdown bold syntax (**File:**) and optional backticks
                $fileMatch = [regex]::Match($findingContent, '(?:\*\*)?(?:File|Location)(?:\*\*)?:?\*?\*?\s*`?([^\s`\r\n*]+)`?')
                $lineMatch = [regex]::Match($findingContent, '(?:\*\*)?(?:Line|line)(?:\*\*)?:?\*?\*?\s*(\d+)')

                $junitFindings[$agentKey] += @{
                    Id = $findingId
                    Title = $title
                    Severity = $severity
                    File = if ($fileMatch.Success) { $fileMatch.Groups[1].Value } else { $null }
                    Line = if ($lineMatch.Success) { [int]$lineMatch.Groups[1].Value } else { $null }
                    Description = $findingContent.Trim()
                }
            }
        }
    }

    return $junitFindings
}
