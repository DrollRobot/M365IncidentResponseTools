#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Runs selected test categories for M365IncidentResponseTools.

.DESCRIPTION
    Runs each test category that is explicitly requested via a switch parameter.
    Nothing runs by default -- you must pass at least one flag.

.PARAMETER Offline
    Run offline tests: Format-Codebase, custom Test-*.ps1 scripts (excluding
    Test-ScriptAnalyzer), and Pester tests that do not require connectivity.

.PARAMETER PSScriptAnalyzer
    Run Test-ScriptAnalyzer.ps1. This step takes 2-3 minutes; omit it during
    rapid development and run it before committing.

.PARAMETER Online
    Run Pester tests tagged 'Online'. These tests expect an active connection to
    Microsoft Graph, Exchange Online, and/or IPPS. Connect-IRT is called
    automatically using $env:IRT_TEST_TENANT_ID from tests/.env.ps1.

.EXAMPLE
    .\Invoke-Tests.ps1 -Offline
    Runs all offline tests.

.EXAMPLE
    .\Invoke-Tests.ps1 -Offline -PSScriptAnalyzer
    Runs offline tests plus the PSScriptAnalyzer step.

.EXAMPLE
    .\Invoke-Tests.ps1 -Offline -PSScriptAnalyzer -Online
    Runs all test categories.

.EXAMPLE
    .\Invoke-Tests.ps1 -Online
    Runs only the online Pester tests.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [Parameter()]
    [switch] $Offline,

    [Parameter()]
    [switch] $PSScriptAnalyzer,

    [Parameter()]
    [switch] $Online
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ($Offline -or $PSScriptAnalyzer -or $Online)) {
    Write-Host "No test categories selected. Pass -Offline, -PSScriptAnalyzer, or -Online." -ForegroundColor Yellow
    exit 0
}

# Import the module under test so PSScriptAnalyzer and Pester tests both have
# access to full parameter metadata for all IRT functions and cmdlets.
$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "$(Split-Path $PSScriptRoot -Leaf).psd1"
if (Test-Path $ManifestPath) {
    $ModuleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "Loading module..." -ForegroundColor Cyan
    Import-Module $ManifestPath -Force
    $ModuleStopwatch.Stop()
    Write-Host "Module loaded in $($ModuleStopwatch.Elapsed.TotalSeconds)s." -ForegroundColor Cyan
}
else {
    Write-Error "Module manifest not found at $ManifestPath. Make sure you're running this from the repo root and the manifest file is present."
    exit 1
}

$TestsFolder = Join-Path $PSScriptRoot 'tests'

# --- Offline ---
if ($Offline) {
    Write-Host "`n=== Format-Codebase ===" -ForegroundColor Cyan
    & (Join-Path $TestsFolder 'Format-Codebase.ps1') -Path $PSScriptRoot -Recurse

    $TestScripts = Get-ChildItem -Path $TestsFolder -Filter 'Test-*.ps1' |
        Where-Object { $_.BaseName -ne 'Test-ScriptAnalyzer' } |
        Sort-Object Name

    foreach ($Script in $TestScripts) {
        Write-Host "`n=== $($Script.BaseName) ===" -ForegroundColor Cyan
        & $Script.FullName -Path $PSScriptRoot -Recurse
    }

    Write-Host "`n=== Invoke-Pester (Offline) ===" -ForegroundColor Cyan
    Invoke-Pester -Path $TestsFolder -ExcludeTagFilter 'Online'
}

# --- PSScriptAnalyzer ---
if ($PSScriptAnalyzer) {
    Write-Host "`n=== Test-ScriptAnalyzer ===" -ForegroundColor Cyan
    & (Join-Path $TestsFolder 'Test-ScriptAnalyzer.ps1') -Path $PSScriptRoot -Recurse
}

# --- Online ---
if ($Online) {
    Write-Host "`n=== Invoke-Pester (Online) ===" -ForegroundColor Cyan
    Invoke-Pester -Path $TestsFolder -TagFilter 'Online'
}
