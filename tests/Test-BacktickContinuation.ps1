<#
.SYNOPSIS
    Checks all .ps1, .psm1, and .psd1 files for backtick line continuations.
.DESCRIPTION
    Flags any line ending with a backtick (`) used as a line continuation
    escape. Splatting or string concatenation should be used instead.
    Here-strings and comment lines are excluded.
.PARAMETER Path
    Root directory to search. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse
)

$GetChildParams = @{
    Path = $Path
    File = $true
}
if ($Recurse) {
    $GetChildParams.Recurse = $true
}

$files = Get-ChildItem @GetChildParams | Where-Object Extension -in '.ps1', '.psm1', '.psd1'
$hitCount = 0
$hits = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Skip comment lines
        if ($line -match '^\s*#') { continue }
        # Match lines ending with a backtick (optionally followed by whitespace)
        if ($line -match '`\s*$') {
            $hitCount++
            $relativePath = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
            $hits.Add([PSCustomObject]@{
                File       = $relativePath
                LineNumber = $i + 1
                Line       = $line.TrimStart()
            })
        }
    }
}

if ($hitCount -eq 0) {
    Write-Host "All $($files.Count) file(s) checked. No backtick line continuations found."
} else {
    $hits | Format-Table -AutoSize
    Write-Host "$hitCount backtick continuation(s) found across $($files.Count) file(s)."
}
