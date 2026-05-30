#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Runs selected test categories for M365IncidentResponseTools.

.DESCRIPTION
    Runs each test category that is explicitly requested via a switch parameter.
    Nothing runs by default -- you must pass at least one flag.

.PARAMETER Offline
    Run offline tests: all Format-*.ps1 scripts, custom Test-*.ps1 scripts (excluding
    Test-ScriptAnalyzer), and Pester tests that do not require connectivity.

.PARAMETER PSScriptAnalyzer
    Run Test-ScriptAnalyzer.ps1. This step takes 2-3 minutes; omit it during
    rapid development and run it before committing.

.PARAMETER Online
    Run Pester tests tagged 'Online'. These tests expect an active connection to
    Microsoft Graph, Exchange Online, and/or IPPS. Connect-IRT is called
    automatically using $env:IRT_TEST_TENANT_ID from tests/.env.ps1.

.PARAMETER CachedAuth
    Used with -Online. When set, Connect-IRT runs in silent-only mode: MSAL
    attempts a token refresh from the test cache and fails immediately if no
    cached credentials exist (no browser prompt). Intended for automated agent
    runs where interactive auth is not possible.

    When omitted, the test token cache is deleted, Connect-IRT prompts once for
    interactive sign-in, then immediately reconnects silently to verify the full
    cache round-trip -- all in the same run.

.EXAMPLE
    .\ Invoke-Tests.ps1 -Offline
    Runs all offline tests.

.EXAMPLE
    .\ Invoke-Tests.ps1 -Offline -PSScriptAnalyzer
    Runs offline tests plus the PSScriptAnalyzer step.

.EXAMPLE
    .\ Invoke-Tests.ps1 -Offline -PSScriptAnalyzer -Online
    Runs all test categories.

.EXAMPLE
    .\ Invoke-Tests.ps1 -Online
    Runs online tests. Deletes the test token cache and prompts for sign-in.

.EXAMPLE
    .\ Invoke-Tests.ps1 -Online -CachedAuth
    Runs online tests silently using cached credentials (no browser prompt).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [Parameter()]
    [switch] $Offline,

    [Parameter()]
    [switch] $PSScriptAnalyzer,

    [Parameter()]
    [switch] $Online,

    [Parameter()]
    [switch] $CachedAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ($Offline -or $PSScriptAnalyzer -or $Online)) {
    $Msg = "No test categories selected. Pass -Offline, -PSScriptAnalyzer, or -Online."
    Write-Host $Msg -ForegroundColor Yellow
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
    $ErrMsg = "Module manifest not found at $ManifestPath. " +
        "Make sure you're running this from the repo root and the manifest file is present."
    Write-Error $ErrMsg
    exit 1
}

$TestsFolder = Join-Path $PSScriptRoot 'tests'

# --- Offline ---
if ($Offline) {

    # collect all Format-*.ps1 scripts
    $FormatScripts = Get-ChildItem -Path $TestsFolder -Filter 'Format-*.ps1' |
        Sort-Object Name

    # run each Format-*.ps1 script first, before any of the Test-*.ps1 scripts
    foreach ($Script in $FormatScripts) {
        Write-Host "`n=== $($Script.BaseName) ===" -ForegroundColor Cyan
        & $Script.FullName -Path $PSScriptRoot -Recurse
    }

    # collect all Test-*.ps1 scripts, exempting the PSScriptAnalyzer script
    $TestScripts = Get-ChildItem -Path $TestsFolder -Filter 'Test-*.ps1' |
        Where-Object { $_.BaseName -ne 'Test-ScriptAnalyzer' } |
        Sort-Object Name

    # run each Test-*.ps1 script
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
    # Derive the test cache path alongside the primary cache.
    $PrimaryCache        = $Global:IRT_Config.MsalCachePath
    $TestCachePath       = Join-Path (Split-Path $PrimaryCache -Parent) 'irt-testing-cache.bin'

    # Override config for this run: always use the test cache with caching forced on.
    $OriginalCachePath   = $Global:IRT_Config.MsalCachePath
    $OriginalCacheEnable = $Global:IRT_Config.EnableTokenCache
    $Global:IRT_Config.MsalCachePath    = $TestCachePath
    $Global:IRT_Config.EnableTokenCache = $true

    Write-Host ''
    Write-Host '  WARNING: Online tests override the token cache config.' -ForegroundColor Red
    Write-Host "           Test cache : $TestCachePath" -ForegroundColor Red
    Write-Host '           EnableTokenCache has been forced on for this run.' -ForegroundColor Red

    if ($CachedAuth) {
        $env:IRT_TEST_SILENT_AUTH = '1'
        Write-Host ''
        $Msg = '  -CachedAuth: silent refresh only. Tests will error immediately if no'
        Write-Host $Msg -ForegroundColor Cyan
        Write-Host '               cached credentials exist.' -ForegroundColor Cyan
        $Msg = "               Run '.\Invoke-Tests.ps1 -Online' (without -CachedAuth) to"
        Write-Host $Msg -ForegroundColor Cyan
        Write-Host '               populate the cache interactively first.' -ForegroundColor Cyan
    }
    else {
        $env:IRT_TEST_SILENT_AUTH = '0'
        if (Test-Path $TestCachePath) {
            Remove-Item -Path $TestCachePath -Force
            Write-Host ''
            $Msg = '  Deleted existing test token cache. Interactive sign-in will be required.'
            Write-Host $Msg -ForegroundColor Cyan
        }
    }

    # Pass 1: Connect-IRT.Tests.ps1 runs first. Its BeforeAll genuinely tests
    # Connect-IRT by clearing $Global:IRT_Session and calling it from scratch.
    # On success the session is populated and available to all subsequent files.
    $ConnectTestFile = Join-Path $TestsFolder 'Connect-IRT.Tests.ps1'
    try {
        Write-Host "`n=== Invoke-Pester (Online: Connect-IRT) ===" -ForegroundColor Cyan
        $ConnectResult = Invoke-Pester -Path $ConnectTestFile -TagFilter 'Online' -PassThru

        # Pass 2: remaining online tests, only if the connection is now active.
        # Skipping when the connection tests failed avoids a cascade of misleading
        # failures in every downstream test file that relies on the session.
        if ($ConnectResult.FailedCount -gt 0 -or -not $Global:IRT_Session) {
            Write-Host ''
            $Msg = '  Connect-IRT online tests failed or no session was established.'
            Write-Host $Msg -ForegroundColor Red
            Write-Host '  Skipping remaining online tests.' -ForegroundColor Red
        }
        else {
            $RemainingTests = Get-ChildItem -Path $TestsFolder -Filter '*.Tests.ps1' |
                Where-Object { $_.Name -ne 'Connect-IRT.Tests.ps1' } |
                Select-Object -ExpandProperty FullName

            if ($RemainingTests) {
                Write-Host "`n=== Invoke-Pester (Online: remaining) ===" -ForegroundColor Cyan
                Invoke-Pester -Path $RemainingTests -TagFilter 'Online'
            }
        }
    }
    finally {
        # Always restore the original config, even if Pester throws.
        $Global:IRT_Config.MsalCachePath    = $OriginalCachePath
        $Global:IRT_Config.EnableTokenCache = $OriginalCacheEnable
        $env:IRT_TEST_SILENT_AUTH           = $null
    }
}
