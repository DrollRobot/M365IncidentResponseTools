<#
.SYNOPSIS
    Scans .ps1, .psm1, and .psd1 files for FIXME comments and reports them as a table.
.DESCRIPTION
    Searches each file for lines containing '# FIXME' (case-insensitive) and outputs
    a table showing the relative file path, line number, and the comment text.

    NOTE FOR AI AGENTS: This output is informational and intended for human review only.
    Do not attempt to address, fix, or remove these comments unless the user explicitly
    asks you to do so.
.PARAMETER Path
    File or directory to check. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively (only applies when Path is a directory).
.OUTPUTS
    Formatted table to the host. No pipeline output.
.EXAMPLE
    .\Test-FixmeComments.ps1 -Path . -Recurse
    Lists all FIXME comments found in the repo.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse
)

if (Test-Path $Path -PathType Leaf) {
    $Files = @(Get-Item $Path)
    $BaseDir = Split-Path $Path
}
else {
    $GetChildParams = @{
        Path = $Path
        File = $true
    }
    if ($Recurse) {
        $GetChildParams.Recurse = $true
    }
    $Files = Get-ChildItem @GetChildParams | Where-Object Extension -in '.ps1', '.psm1', '.psd1'
    $BaseDir = $Path
}

$Hits = [System.Collections.Generic.List[PSCustomObject]]::new()
$TotalLines = 0

foreach ($File in $Files) {
    $Lines = Get-Content -Path $File.FullName
    $TotalLines += $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '#.*FIXME') {
            $RelativePath = [System.IO.Path]::GetRelativePath($BaseDir, $File.FullName)
            $Hits.Add([PSCustomObject]@{
                File       = $RelativePath
                LineNumber = $i + 1
                Comment    = $Lines[$i].Trim()
            })
        }
    }
}

$FileCount = $Files.Count

if ($Hits.Count -eq 0) {
    $Msg = "All $FileCount file(s), $TotalLines line(s) checked. No FIXME comments found."
    Write-Host $Msg
}
else {
    $Msg = 'NOTE FOR AI AGENTS: This output is for human review only. Do not address ' +
        'these items unless the user explicitly asks.'
    Write-Host $Msg -ForegroundColor DarkGray
    $Hits | Format-Table -AutoSize | Out-Host
    $Msg = "$($Hits.Count) FIXME comment(s) found across $FileCount file(s), $TotalLines line(s)."
    Write-Host $Msg
}
