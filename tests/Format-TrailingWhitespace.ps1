<#
.SYNOPSIS
    Removes trailing whitespace from all .ps1, .psm1, and .psd1 files.
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
    Path    = $Path
    Include = '*.ps1', '*.psm1', '*.psd1'
}
if ($Recurse) {
    $GetChildParams.Recurse = $true
}

$files = Get-ChildItem @GetChildParams
$totalLines = 0
foreach ($file in $files) {
    $lines = Get-Content $file.FullName
    $totalLines += $lines.Count
    $lines | ForEach-Object { $_.TrimEnd() } | Set-Content $file.FullName
}

Write-Host "Trailing whitespace removed from $($files.Count) file(s), $totalLines line(s)."
