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
.PARAMETER Quiet
    Suppress the per-finding table, printing only the one-line summary. Useful
    for a quick pass/fail check.
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
    [switch] $Recurse,
    [switch] $Quiet
)

# import helper functions. they must be in same directory.
. (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ModuleRoot.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ScriptCommand.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Resolve-CommandModule.ps1')

$ExcludedFolders = @()
$ExcludedFiles = @()

if ($Global:Dev_FormattingExclusions) {
    $ExcludedFiles += $Global:Dev_FormattingExclusions.ExcludeFiles
    $ExcludedFolders += $Global:Dev_FormattingExclusions.ExcludeFolders
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Find current module name. Error out if not currently imported.
#   Prefer erroring over importing because script doesn't know if dev wants
#   to test source or build module.
$CurrentModuleName = (Find-ModuleRoot -Path $PSScriptRoot).Name
if (-not (Get-Module -Name $CurrentModuleName)) {
    $ErrMsg = "Module '$CurrentModuleName' is not imported. " +
        "Import it before running this test."
    Write-Error $ErrMsg
    exit 1
}

# Static map for commands that Get-Command cannot discover on this machine
# (e.g. modules not installed here, like ActiveDirectory RSAT tools).
# Add entries as new undiscoverable dependencies are introduced.
$CommandModuleMap = @{
    'Get-ADDomain'             = 'ActiveDirectory'
    'Get-ADDomainController'   = 'ActiveDirectory'
    'Get-ADOrganizationalUnit' = 'ActiveDirectory'
    'Get-ADUser'               = 'ActiveDirectory'
    'Set-ADUser'               = 'ActiveDirectory'
    'Start-ADSyncSyncCycle'    = 'ADSync'
}

$GetChildParams = @{
    Path = $Path
    File = $true
}
if ($Recurse) {
    $GetChildParams.Recurse = $true
}

$files = Get-ChildItem @GetChildParams |
    Where-Object Extension -eq '.ps1' |
    Where-Object {
        $Rel = [System.IO.Path]::GetRelativePath($Path, $_.FullName)
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
        Status          = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
        PercentComplete = ($FileIndex / $FileTotal) * 100
    }
    Write-Progress @WpParams
    $totalFiles++

    $content = Get-Content -Path $file.FullName -Raw

    if ($content -match '#\s*noqa:\s*Test-ExplicitModuleImport') { continue }

    $commands = @(Find-ScriptCommand -Path $file.FullName)
    if ($commands.Count -eq 0) { continue }

    $ResolvedCommands = $commands | Resolve-CommandModule -HostModuleName $CurrentModuleName
    $PrivateShadowed = [System.Collections.Generic.HashSet[string]](
        $ResolvedCommands |
            Where-Object { $_.Source -eq 'HostPrivate' } |
            Select-Object -ExpandProperty Name
    )
    $InstalledCommands = $ResolvedCommands |
        Where-Object { $_.Source -eq 'Installed' -and -not $PrivateShadowed.Contains($_.Name) } |
        Select-Object Name, Module

    $MappedCommands = $ResolvedCommands |
        Where-Object { $_.Source -eq 'NotFound' -and $CommandModuleMap.ContainsKey($_.Name) } |
        ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Module = $CommandModuleMap[$_.Name] } }

    $UnknownCommands = @(
        $ResolvedCommands |
            Where-Object {
                $_.Source -eq 'NotFound' -and
                -not $PrivateShadowed.Contains($_.Name) -and
                -not $CommandModuleMap.ContainsKey($_.Name)
            }
    )

    $ModuleGroups = @($InstalledCommands) + @($MappedCommands) | Group-Object -Property Module

    foreach ($group in $ModuleGroups) {
        if ($content -notlike "*$($group.Name)*") {
            $hitCount++
            $hits.Add([PSCustomObject]@{
                File     = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
                Module   = $group.Name
                Commands = ($group.Group.Name | Sort-Object -Unique) -join ', '
            })
        }
    }

    if ($UnknownCommands.Count -gt 0) {
        $hitCount++
        $hits.Add([PSCustomObject]@{
            File     = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
            Module   = '(unknown - add to $CommandModuleMap)'
            Commands = ($UnknownCommands.Name | Sort-Object -Unique) -join ', '
        })
    }
}

if ($hitCount -gt 0 -and -not $Quiet) {
    $hits | Format-Table -AutoSize
}

Write-Progress -Activity $MyInvocation.MyCommand.Name -Completed
$Stopwatch.Stop()
$Elapsed = "$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 2))s"
$SummaryColor = if ($hitCount -gt 0) { 'Red' } else { 'Green' }
$Msg = "$hitCount missing module reference(s) -- $totalFiles file(s) checked. ($Elapsed)"
Write-Host $Msg -ForegroundColor $SummaryColor
