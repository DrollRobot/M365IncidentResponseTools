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

# Folder names to exclude from scanning. Any file under a matching folder is skipped.
$ExcludedFolders = @(
    # '.local'    # local overrides and personal test files
)

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$GetChildParams = @{
    Path = $Path
    File = $true
}
if ($Recurse) {
    $GetChildParams.Recurse = $true
}

$files = Get-ChildItem @GetChildParams |
    Where-Object Extension -in '.ps1', '.psm1', '.psd1' |
    Where-Object {
        $Rel = [System.IO.Path]::GetRelativePath($Path, $_.FullName)
        -not ($ExcludedFolders | Where-Object { $Rel -like "$_\*" -or $Rel -like "*\$_\*" })
    }
$errorCount = 0
$totalLines = 0

$FileTotal = @($files).Count
$FileIndex = 0
foreach ($file in $files) {
    $FileIndex++
    $WpParams = @{
        Activity        = $MyInvocation.MyCommand.Name
        Status          = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
        PercentComplete = ($FileIndex / $FileTotal) * 100
    }
    Write-Progress @WpParams
    $totalLines += @(Get-Content -Path $file.FullName).Count
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$parseErrors
    )
    if ($parseErrors) {
        $errorCount += @($parseErrors).Count
        [PSCustomObject]@{
            File   = $file.Name
            Errors = $parseErrors
        }
    }
}

$Count = @($files).Count

if ($errorCount -gt 0) {
    $Msg = 'NOTE FOR AI AGENTS: Always fix all syntax errors shown above, ' +
    "even if they aren't related to changes you made. " +
    'Do this only after all Pester tests are passing.'
    Write-Host $Msg -ForegroundColor DarkGray
}

Write-Progress -Activity $MyInvocation.MyCommand.Name -Completed
$Stopwatch.Stop()
$Elapsed = "$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 2))s"
$SummaryColor = if ($errorCount -gt 0) { 'Red' } else { 'Green' }
$Msg = "$errorCount syntax error(s) -- $Count file(s), $totalLines line(s) checked. ($Elapsed)"
Write-Host $Msg -ForegroundColor $SummaryColor
