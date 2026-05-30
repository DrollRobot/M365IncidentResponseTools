<#
.SYNOPSIS
    Parses all .ps1, .psm1, and .psd1 files in a directory for syntax errors.
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
$errorCount = 0
$totalLines = 0

foreach ($file in $files) {
    $totalLines += (Get-Content -Path $file.FullName).Count
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$parseErrors
    )
    if ($parseErrors) {
        $errorCount += $parseErrors.Count
        [PSCustomObject]@{
            File   = $file.Name
            Errors = $parseErrors
        }
    }
}

$Count = $files.Count
if ($errorCount -eq 0) {
    $Msg = "All $Count file(s), $totalLines line(s) parsed successfully. " +
        'No syntax errors found.'
    Write-Host $Msg
}
else {
    Write-Host "$errorCount error(s) found across $Count file(s), $totalLines line(s)."
}
