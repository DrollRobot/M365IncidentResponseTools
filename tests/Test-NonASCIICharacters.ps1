<#
.SYNOPSIS
    Checks all .ps1, .psm1, and .psd1 files in a directory for non-ASCII characters.
.PARAMETER Path
    Root directory to search. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively.
.PARAMETER ExemptCharacters
    Array of specific non-ASCII characters to ignore. Matches are suppressed when
    the offending character is in this list.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse,
    [char[]] $ExemptCharacters = @()
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
    $nonAsciiMatches = $lines | Select-String -Pattern '[^\x00-\x7F]' | Where-Object {
        $line = $_.Line
        ($line.ToCharArray() |
            Where-Object { [int]$_ -gt 0x7F -and $_ -notin $ExemptCharacters }).Count -gt 0
    }
    if ($nonAsciiMatches) {
        $hitCount += $nonAsciiMatches.Count
        foreach ($match in $nonAsciiMatches) {
            $WarnMsg = "Non-ASCII in '$($file.Name)' line " +
                "$($match.LineNumber): $($match.Line.Trim())"
            Write-Warning $WarnMsg
        }
    }
}

$Count = $files.Count
if ($hitCount -eq 0) {
    $Msg = "All $Count file(s), $totalLines line(s) checked. No non-ASCII characters found."
    Write-Host $Msg
}
else {
    $Msg = "$hitCount non-ASCII occurrence(s) found across $Count file(s), $totalLines line(s)."
    Write-Host $Msg
}
