<#
.SYNOPSIS
    Simple YAML parser for Code Conclave compliance standards.

.DESCRIPTION
    Parses YAML files into PowerShell hashtables. Supports the specific
    YAML structures used in compliance standard files. Falls back to
    ConvertFrom-Yaml if the powershell-yaml module is available.

.NOTES
    This parser handles:
    - Key-value pairs
    - Arrays (both inline [a, b] and block form with -)
    - Nested objects (indentation-based)
    - Multi-line strings (using |)
    - Comments (lines starting with #)
#>

function Get-YamlContent {
    <#
    .SYNOPSIS
        Load and parse a YAML file.
    .PARAMETER Path
        Path to the YAML file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "YAML file not found: $Path"
        return $null
    }

    # Try powershell-yaml module first if available
    if (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
        try {
            $content = Get-Content $Path -Raw -Encoding UTF8
            return $content | ConvertFrom-Yaml
        }
        catch {
            Write-Warning "ConvertFrom-Yaml failed, using built-in parser: $_"
        }
    }

    # Use built-in parser
    return ConvertFrom-SimpleYaml -Path $Path
}

function ConvertFrom-SimpleYaml {
    <#
    .SYNOPSIS
        Simple YAML parser for Code Conclave standard files.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $lines = Get-Content $Path -Encoding UTF8
    $result = @{}
    $lineIndex = 0

    $parsed = Parse-YamlObject -Lines $lines -Index ([ref]$lineIndex) -Indent 0
    return $parsed
}

function Parse-YamlObject {
    param(
        [string[]]$Lines,
        [ref]$Index,
        [int]$Indent
    )

    $result = @{}

    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]

        # Skip empty lines and comments
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            $Index.Value++
            continue
        }

        # Get current line's indentation
        $lineIndent = ($line -replace '^(\s*).*', '$1').Length

        # If we've dedented, return to parent
        if ($lineIndent -lt $Indent) {
            return $result
        }

        # Skip lines that are more indented than expected (handled by recursion)
        if ($lineIndent -gt $Indent -and $result.Count -gt 0) {
            return $result
        }

        # Array item
        if ($line -match "^(\s*)-\s*(.*)$") {
            # This is an array context - return to let caller handle
            return $result
        }

        # Key-value pair
        if ($line -match "^(\s*)([^:]+):\s*(.*)$") {
            $key = $Matches[2].Trim()
            $value = $Matches[3].Trim()

            $Index.Value++

            if ($value -eq '|') {
                # Multi-line string
                $result[$key] = Parse-MultilineString -Lines $Lines -Index $Index -Indent ($lineIndent + 2)
            }
            elseif ($value -eq '' -or $value -match '^#') {
                # Check if next line is array or nested object
                if ($Index.Value -lt $Lines.Count) {
                    $nextLine = $Lines[$Index.Value]
                    $nextIndent = ($nextLine -replace '^(\s*).*', '$1').Length

                    if ($nextLine -match '^\s*-\s') {
                        # Array
                        $result[$key] = Parse-YamlArray -Lines $Lines -Index $Index -Indent $nextIndent
                    }
                    elseif ($nextIndent -gt $lineIndent) {
                        # Nested object
                        $result[$key] = Parse-YamlObject -Lines $Lines -Index $Index -Indent $nextIndent
                    }
                    else {
                        $result[$key] = $null
                    }
                }
                else {
                    $result[$key] = $null
                }
            }
            elseif ($value -match '^\[.*\]$') {
                # Inline array
                $result[$key] = Parse-InlineArray -Value $value
            }
            elseif ($value -match '^\{.*\}$') {
                # Inline object
                $result[$key] = Parse-InlineObject -Value $value
            }
            elseif ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                # Quoted string
                $result[$key] = $Matches[1]
            }
            elseif ($value -match '^[+-]?\d+$') {
                # Integer (including optional sign)
                $parsedInt = 0
                if ([int]::TryParse($value, [ref]$parsedInt)) {
                    $result[$key] = $parsedInt
                }
                else {
                    $result[$key] = $value
                }
            }
            elseif ($value -match '^[+-]?(\d+\.?\d*|\d*\.?\d+)([eE][+-]?\d+)?$') {
                # Float (including optional sign and scientific notation)
                $parsedDouble = 0.0
                if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedDouble)) {
                    $result[$key] = $parsedDouble
                }
                else {
                    $result[$key] = $value
                }
            }
            elseif ($value -eq 'true') {
                $result[$key] = $true
            }
            elseif ($value -eq 'false') {
                $result[$key] = $false
            }
            elseif ($value -eq 'null' -or $value -eq '~') {
                $result[$key] = $null
            }
            else {
                # Plain string (remove inline comment if present)
                $result[$key] = ($value -replace '\s*#.*$', '').Trim()
            }
        }
        else {
            $Index.Value++
        }
    }

    return $result
}

function Parse-YamlArray {
    param(
        [string[]]$Lines,
        [ref]$Index,
        [int]$Indent
    )

    $result = @()

    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]

        # Skip empty lines and comments
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            $Index.Value++
            continue
        }

        $lineIndent = ($line -replace '^(\s*).*', '$1').Length

        # If we've dedented past array level, return
        if ($lineIndent -lt $Indent) {
            return $result
        }

        # Array item
        if ($line -match "^(\s*)-\s*(.*)$") {
            $itemIndent = $Matches[1].Length
            $itemValue = $Matches[2].Trim()

            # Check if this item is at our indent level
            if ($itemIndent -lt $Indent) {
                return $result
            }

            $Index.Value++

            if ($itemValue -match '^([^:]+):\s*(.*)$') {
                # Array of objects - first key-value pair
                $Index.Value--  # Back up to re-parse as object
                $objIndent = $itemIndent + 2

                # Parse the object starting with this item
                $obj = @{}
                $key = $Matches[1].Trim()
                $val = $Matches[2].Trim()

                $Index.Value++

                if ($val -eq '' -and $Index.Value -lt $Lines.Count) {
                    $nextLine = $Lines[$Index.Value]
                    $nextIndent = ($nextLine -replace '^(\s*).*', '$1').Length
                    if ($nextLine -match '^\s*-\s') {
                        $obj[$key] = Parse-YamlArray -Lines $Lines -Index $Index -Indent $nextIndent
                    }
                    elseif ($nextIndent -gt $itemIndent + 2) {
                        $obj[$key] = Parse-YamlObject -Lines $Lines -Index $Index -Indent $nextIndent
                    }
                    else {
                        $obj[$key] = $null
                    }
                }
                elseif ($val -match '^\[.*\]$') {
                    $obj[$key] = Parse-InlineArray -Value $val
                }
                else {
                    $obj[$key] = $val
                }

                # Continue parsing remaining keys at this object level
                while ($Index.Value -lt $Lines.Count) {
                    $nextLine = $Lines[$Index.Value]
                    if ($nextLine -match '^\s*$' -or $nextLine -match '^\s*#') {
                        $Index.Value++
                        continue
                    }

                    $nextIndent = ($nextLine -replace '^(\s*).*', '$1').Length

                    # Check if we've hit another array item or dedented
                    if ($nextLine -match '^\s*-\s' -or $nextIndent -le $itemIndent) {
                        break
                    }

                    # Parse as part of this object
                    if ($nextLine -match "^\s*([^:]+):\s*(.*)$") {
                        $k = $Matches[1].Trim()
                        $v = $Matches[2].Trim()
                        $Index.Value++

                        if ($v -match '^\[.*\]$') {
                            $obj[$k] = Parse-InlineArray -Value $v
                        }
                        elseif ($v -eq '' -and $Index.Value -lt $Lines.Count) {
                            $peekLine = $Lines[$Index.Value]
                            $peekIndent = ($peekLine -replace '^(\s*).*', '$1').Length
                            if ($peekLine -match '^\s*-\s') {
                                $obj[$k] = Parse-YamlArray -Lines $Lines -Index $Index -Indent $peekIndent
                            }
                            elseif ($peekIndent -gt $nextIndent) {
                                $obj[$k] = Parse-YamlObject -Lines $Lines -Index $Index -Indent $peekIndent
                            }
                            else {
                                $obj[$k] = $null
                            }
                        }
                        else {
                            $obj[$k] = $v
                        }
                    }
                    else {
                        $Index.Value++
                    }
                }

                $result += $obj
            }
            elseif ($itemValue -match '^\[.*\]$') {
                # Inline array as item
                $result += , (Parse-InlineArray -Value $itemValue)
            }
            elseif ($itemValue -ne '') {
                # Simple scalar value
                $result += $itemValue
            }
            else {
                # Check if next lines form a nested object
                if ($Index.Value -lt $Lines.Count) {
                    $nextLine = $Lines[$Index.Value]
                    $nextIndent = ($nextLine -replace '^(\s*).*', '$1').Length
                    if ($nextIndent -gt $itemIndent -and -not ($nextLine -match '^\s*-\s')) {
                        $result += Parse-YamlObject -Lines $Lines -Index $Index -Indent $nextIndent
                    }
                }
            }
        }
        else {
            # Not an array item - we're done with this array
            return $result
        }
    }

    return $result
}

function Parse-MultilineString {
    param(
        [string[]]$Lines,
        [ref]$Index,
        [int]$Indent
    )

    $sb = New-Object System.Text.StringBuilder

    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]

        # Empty line in multiline string
        if ($line -match '^\s*$') {
            [void]$sb.AppendLine()
            $Index.Value++
            continue
        }

        $lineIndent = ($line -replace '^(\s*).*', '$1').Length

        # If dedented, we're done with the multiline string
        if ($lineIndent -lt $Indent) {
            break
        }

        # Add line content (stripped of the base indentation)
        # If line is shorter than expected indent, add empty content
        if ($line.Length -lt $Indent) {
            [void]$sb.AppendLine("")
        }
        else {
            $content = $line.Substring($Indent)
            [void]$sb.AppendLine($content)
        }
        $Index.Value++
    }

    return $sb.ToString().TrimEnd()
}

function Parse-InlineArray {
    param([string]$Value)

    # Remove brackets
    $inner = $Value.Trim('[', ']').Trim()

    if ($inner -eq '') {
        return @()
    }

    # Split by comma, handling quoted strings
    $items = @()
    $current = ''
    $inQuote = $false
    $quoteChar = ''

    for ($i = 0; $i -lt $inner.Length; $i++) {
        $char = $inner[$i]

        if ($char -eq '"' -or $char -eq "'") {
            if (-not $inQuote) {
                $inQuote = $true
                $quoteChar = $char
                $current += $char
            }
            elseif ($char -eq $quoteChar) {
                # Check for escaped quote (preceded by odd number of backslashes)
                $backslashCount = 0
                for ($j = $i - 1; $j -ge 0 -and $inner[$j] -eq '\'; $j--) {
                    $backslashCount++
                }
                if (($backslashCount % 2) -eq 1) {
                    # Escaped quote - keep it
                    $current += $char
                }
                else {
                    # End of quoted section
                    $inQuote = $false
                    $current += $char
                }
            }
            else {
                # Different quote char inside quoted string
                $current += $char
            }
        }
        elseif ($char -eq ',' -and -not $inQuote) {
            $items += $current.Trim()
            $current = ''
        }
        else {
            $current += $char
        }
    }

    if ($current.Trim() -ne '') {
        $items += $current.Trim()
    }

    # Clean up quotes from items (ensure matching quote pairs)
    $items = $items | ForEach-Object {
        $item = $_.Trim()
        if ($item.Length -ge 2) {
            $firstChar = $item[0]
            $lastChar = $item[$item.Length - 1]
            if (($firstChar -eq $lastChar) -and ($firstChar -eq '"' -or $firstChar -eq "'")) {
                # Matching quote pair - remove them
                $item = $item.Substring(1, $item.Length - 2)
            }
        }
        $item
    }

    return $items
}

function Parse-InlineObject {
    param([string]$Value)

    # Remove braces
    $inner = $Value.Trim('{', '}').Trim()

    if ($inner -eq '') {
        return @{}
    }

    $result = @{}

    # Split into pairs by commas that are not inside quotes or nested structures
    $pairs = @()
    $current = ''
    $inQuote = $false
    $quoteChar = ''
    $braceLevel = 0
    $bracketLevel = 0

    for ($i = 0; $i -lt $inner.Length; $i++) {
        $char = $inner[$i]

        if (($char -eq '"' -or $char -eq "'") -and -not $inQuote) {
            $inQuote = $true
            $quoteChar = $char
            $current += $char
        }
        elseif ($inQuote -and $char -eq $quoteChar) {
            $inQuote = $false
            $current += $char
        }
        elseif (-not $inQuote) {
            if ($char -eq '{') {
                $braceLevel++
                $current += $char
            }
            elseif ($char -eq '}') {
                $braceLevel--
                $current += $char
            }
            elseif ($char -eq '[') {
                $bracketLevel++
                $current += $char
            }
            elseif ($char -eq ']') {
                $bracketLevel--
                $current += $char
            }
            elseif ($char -eq ',' -and $braceLevel -eq 0 -and $bracketLevel -eq 0) {
                if ($current.Trim() -ne '') {
                    $pairs += $current.Trim()
                }
                $current = ''
            }
            else {
                $current += $char
            }
        }
        else {
            $current += $char
        }
    }

    if ($current.Trim() -ne '') {
        $pairs += $current.Trim()
    }

    # Parse each key:value pair
    foreach ($pair in $pairs) {
        if ([string]::IsNullOrWhiteSpace($pair)) {
            continue
        }

        # Find the first colon not inside quotes
        $inQuote = $false
        $quoteChar = ''
        $colonIndex = -1

        for ($i = 0; $i -lt $pair.Length; $i++) {
            $char = $pair[$i]

            if (($char -eq '"' -or $char -eq "'") -and -not $inQuote) {
                $inQuote = $true
                $quoteChar = $char
            }
            elseif ($inQuote -and $char -eq $quoteChar) {
                $inQuote = $false
            }
            elseif (-not $inQuote -and $char -eq ':') {
                $colonIndex = $i
                break
            }
        }

        if ($colonIndex -lt 0) {
            continue
        }

        $key = $pair.Substring(0, $colonIndex).Trim()
        $val = $pair.Substring($colonIndex + 1).Trim()

        # Remove surrounding quotes from key
        if ($key.Length -ge 2) {
            $firstChar = $key[0]
            $lastChar = $key[$key.Length - 1]
            if (($firstChar -eq $lastChar) -and ($firstChar -eq '"' -or $firstChar -eq "'")) {
                $key = $key.Substring(1, $key.Length - 2)
            }
        }

        # Remove surrounding quotes from value
        if ($val.Length -ge 2) {
            $firstChar = $val[0]
            $lastChar = $val[$val.Length - 1]
            if (($firstChar -eq $lastChar) -and ($firstChar -eq '"' -or $firstChar -eq "'")) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }

        if ($key -ne '') {
            $result[$key] = $val
        }
    }

    return $result
}

# Export functions
Export-ModuleMember -Function Get-YamlContent, ConvertFrom-SimpleYaml -ErrorAction SilentlyContinue
