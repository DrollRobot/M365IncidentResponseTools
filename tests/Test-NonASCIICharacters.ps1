<#
.SYNOPSIS
    Checks all .ps1, .psm1, and .psd1 files in a directory for non-ASCII characters.
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
$totalLines = 0

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName
    $totalLines += $lines.Count
    $nonAsciiMatches = $lines | Select-String -Pattern '[^\x00-\x7F]'
    if ($nonAsciiMatches) {
        $hitCount += $nonAsciiMatches.Count
        foreach ($match in $nonAsciiMatches) {
            Write-Warning "Non-ASCII in '$($file.Name)' line $($match.LineNumber): $($match.Line.Trim())"
        }
    }
}

if ($hitCount -eq 0) {
    Write-Host "All $($files.Count) file(s), $totalLines line(s) checked. No non-ASCII characters found."
}
else {
    Write-Host "$hitCount non-ASCII occurrence(s) found across $($files.Count) file(s), $totalLines line(s)."
}
