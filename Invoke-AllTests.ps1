#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Runs all developer tests for M365IncidentResponseTools.

.DESCRIPTION
    Invokes each Test-*.ps1 script in the tests/ folder against the repo root,
    then runs Invoke-Pester against the same folder.

    By default, only offline tests are run. Use -Online to include tests that
    require an active Graph/Exchange/IPPS session.

    To mark a Pester test as requiring connectivity, add -Tag 'Online' to its
    Describe or It block.

.PARAMETER Online
    Include tests tagged 'Online'. These tests expect an active connection to
    Microsoft Graph, Exchange Online, and/or IPPS.

.EXAMPLE
    .\Invoke-AllTests.ps1
    Runs all offline tests.

.EXAMPLE
    .\Invoke-AllTests.ps1 -Online
    Runs all tests, including those that require a live tenant connection.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [Parameter()]
    [switch] $Online
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TestsFolder = Join-Path $PSScriptRoot 'tests'

# --- Format ---
Write-Host "`n=== Format-Codebase ===" -ForegroundColor Cyan
& (Join-Path $TestsFolder 'Format-Codebase.ps1') -Path $PSScriptRoot -Recurse

# --- Custom test scripts ---
$TestScripts = Get-ChildItem -Path $TestsFolder -Filter 'Test-*.ps1' | Sort-Object Name

foreach ($Script in $TestScripts) {
    Write-Host "`n=== $($Script.BaseName) ===" -ForegroundColor Cyan
    & $Script.FullName -Path $PSScriptRoot -Recurse
}

# --- Pester ---
Write-Host "`n=== Invoke-Pester ===" -ForegroundColor Cyan

$PesterParams = @{
    Path = $TestsFolder
}

if (-not $Online) {
    $PesterParams.ExcludeTagFilter = 'Online'
}

Invoke-Pester @PesterParams
