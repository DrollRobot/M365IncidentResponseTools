<#
.SYNOPSIS
    A developer helper script. Checks that each source file explicitly names 
    every external module it uses.
.DESCRIPTION
    For each .ps1 file under Source\, parses the file with Find-ScriptCommand,
    resolves each command to its owning module with Resolve-CommandModule, and
    checks that every module classified as Installed appears as a literal string
    in the file. The intent is to ensure each file explicitly calls
    Import-IRTModule for every external module it depends on.

    To suppress all findings for a file, add this comment anywhere in the file:

        # noqa: Test-ExplicitModuleImport

.PARAMETER Path
    Root directory to search. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively.
.OUTPUTS
    Formatted table to the host. No pipeline output.
.EXAMPLE
    .\Test-ExplicitModuleImport.ps1 -Path . -Recurse
    Lists all external-module usage that lacks an explicit module name reference.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse
)

# import helper functions. they must be in same directory.
. (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ModuleRoot.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ScriptCommand.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Resolve-CommandModule.ps1')

$ExcludedFolders = @()
$ExcludedFiles = @()

if ($Global:IRT_FormattingExclusions) {
    $ExcludedFiles += $Global:IRT_FormattingExclusions.ExcludeFiles
    $ExcludedFolders += $Global:IRT_FormattingExclusions.ExcludeFolders
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Exclude the host module itself so calls to sibling functions are not flagged.
$CurrentModuleName = (Find-ModuleRoot -Path $PSScriptRoot).Name

if (-not (Get-Module -Name $CurrentModuleName)) {
    $ErrMsg = "Module '$CurrentModuleName' is not imported. " +
        "Import it before running this test."
    Write-Error $ErrMsg
    exit 1
}

# Build a set of all function names defined in the module (public and private)
# so they are excluded from the external-module check.
$ModuleFunctions = [System.Collections.Generic.HashSet[string]](
    Get-Command -Module $CurrentModuleName -All | Select-Object -ExpandProperty Name
)

# Narrow scan to Source\ when the repo root is passed
$SourceSubdir = Join-Path -Path $Path -ChildPath 'Source'
$ScanPath = if (Test-Path -Path $SourceSubdir -PathType Container) { $SourceSubdir } else { $Path }

$GetChildParams = @{
    Path = $ScanPath
    File = $true
}
if ($Recurse -or ($ScanPath -ne $Path)) {
    $GetChildParams.Recurse = $true
}

$files = Get-ChildItem @GetChildParams |
    Where-Object Extension -eq '.ps1' |
    Where-Object {
        $Rel = [System.IO.Path]::GetRelativePath($ScanPath, $_.FullName)
        (-not ($ExcludedFiles -contains $Rel)) -and
        (-not ($ExcludedFolders | Where-Object { $Rel -like "$_\*" -or $Rel -like "*\$_\*" }))
    }

$hitCount = 0
$totalFiles = 0
$hits = [System.Collections.Generic.List[PSCustomObject]]::new()

$FileTotal = @($files).Count
$FileIndex = 0

foreach ($file in $files) {
    $FileIndex++
    $WpParams = @{
        Activity        = $MyInvocation.MyCommand.Name
        Status          = [System.IO.Path]::GetRelativePath($ScanPath, $file.FullName)
        PercentComplete = ($FileIndex / $FileTotal) * 100
    }
    Write-Progress @WpParams
    $totalFiles++

    $content = Get-Content -Path $file.FullName -Raw

    if ($content -match '#\s*noqa:\s*Test-ExplicitModuleImport') { continue }

    $commands = @(Find-ScriptCommand -Path $file.FullName)
    if ($commands.Count -eq 0) { continue }

    $AllCommands = $commands | Resolve-CommandModule 
    $ModuleGroups = $AllCommands |
        Where-Object {
            $_.Source -eq 'Installed' -and
            $_.Module -ne $CurrentModuleName -and
            -not $ModuleFunctions.Contains($_.Name)
        } |
        Group-Object -Property Module

    foreach ($group in $moduleGroups) {
        if ($content -notlike "*$($group.Name)*") {
            $hitCount++
            $hits.Add([PSCustomObject]@{
                File     = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
                Module   = $group.Name
                Commands = ($group.Group.Name | Sort-Object -Unique) -join ', '
            })
        }
    }
}

if ($hitCount -gt 0) {
    $hits | Format-Table -AutoSize
}

Write-Progress -Activity $MyInvocation.MyCommand.Name -Completed
$Stopwatch.Stop()
$Elapsed = "$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 2))s"
$SummaryColor = if ($hitCount -gt 0) { 'Red' } else { 'Green' }
$Msg = "$hitCount missing module reference(s) -- $totalFiles file(s) checked. ($Elapsed)"
Write-Host $Msg -ForegroundColor $SummaryColor
