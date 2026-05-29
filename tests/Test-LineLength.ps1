<#
.SYNOPSIS
    Checks .ps1, .psm1, and .psd1 files for lines exceeding a maximum length.
    Pass a file path to check a single file, or a folder path to check all matching files.
.PARAMETER Path
    File or directory to check. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively (only applies when Path is a directory).
.PARAMETER MaxLength
    Maximum allowed line length in characters. Defaults to 100.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse,
    [int] $MaxLength = 100
)

if (Test-Path $Path -PathType Leaf) {
    $files = @(Get-Item $Path)
    $BaseDir = Split-Path $Path
} else {
    $GetChildParams = @{
        Path = $Path
        File = $true
    }
    if ($Recurse) {
        $GetChildParams.Recurse = $true
    }
    $files = Get-ChildItem @GetChildParams | Where-Object Extension -in '.ps1', '.psm1', '.psd1'
    $BaseDir = $Path
}
$hitCount = 0
$totalLines = 0
$hits = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName
    $totalLines += $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $length = $lines[$i].Length
        if ($length -gt $MaxLength) {
            $hitCount++
            $relativePath = [System.IO.Path]::GetRelativePath($BaseDir, $file.FullName)
            $hits.Add([PSCustomObject]@{
                File       = $relativePath
                LineNumber = $i + 1
                Length     = $length
            })
        }
    }
}

if ($hitCount -eq 0) {
    Write-Host "All $($files.Count) file(s), $totalLines line(s) checked. No lines exceed $MaxLength characters."
}
else {
    $hits | Format-Table -AutoSize
    Write-Host "$hitCount line(s) exceed $MaxLength characters across $($files.Count) file(s), $totalLines line(s)."
}
