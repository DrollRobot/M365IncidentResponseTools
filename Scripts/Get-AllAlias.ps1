<#
.SYNOPSIS
    Outputs the command-level aliases of each public function as a hashtable literal.

.DESCRIPTION
    Reads every file under source\Public and emits a PowerShell hashtable literal
    mapping each function name to its sorted aliases. Functions without aliases are
    omitted. Run from the repository root.

.EXAMPLE
    .\Get-AllAlias.ps1 | Set-Clipboard

.OUTPUTS
    System.String. The lines of the hashtable literal.
#>

& {
    $result = [ordered]@{}

    $files = Get-ChildItem -Path source\Public -Recurse -Filter '*.ps1' | Sort-Object FullName
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw

        # Find the param( position -- command-level attributes appear before it
        $paramPos = $content.IndexOf("`n    param ")
        if ($paramPos -lt 0) { $paramPos = $content.IndexOf("`n    param(") }
        if ($paramPos -lt 0) { continue }

        # Find the [Alias( that is BEFORE param(
        $aliasIdx = $content.IndexOf('[Alias(')
        if ($aliasIdx -lt 0 -or $aliasIdx -gt $paramPos) { continue }

        # Extract the full alias block up to the closing )]
        $closeIdx = $content.IndexOf(')]', $aliasIdx)
        if ($closeIdx -lt 0) { continue }
        $block = $content.Substring($aliasIdx, $closeIdx - $aliasIdx + 2)

        # Pull out individual alias strings
        $aliases = [regex]::Matches($block, "'([^']+)'") |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object

        # Function name = file base name without extension
        $funcName = $f.BaseName
        $result[$funcName] = $aliases
    }

    # Pretty-print as a PowerShell hashtable literal
    '@{'
    foreach ($key in $result.Keys) {
        $vals = $result[$key] | ForEach-Object { "'$_'" }
        "    '$key' = @($($vals -join ', '))"
    }
    '}'
}
