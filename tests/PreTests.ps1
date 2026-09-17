#Requires -Version 7.5

<#
.SYNOPSIS
    Project-specific test setup for M365IncidentResponseTools (IRT).

.DESCRIPTION
    Dot-sourced by Tests.ps1 after the module is imported and before the test
    sections run. Receives the $TestContext hashtable from the orchestrator;
    state shared with PostTests.ps1 (e.g. saved config values) is stored back on
    $TestContext so teardown can restore it.

    Responsibilities:
      * Verify $Global:IRT_Config was populated on module load.
      * For Live runs: point auth at an isolated test token cache, force the
        cache on, choose silent vs. interactive auth, and run the live Pester
        suite in two passes (Connect-IRT first, then the rest only if the
        connection succeeded). Sets $TestContext.LiveHandled so the
        orchestrator skips its generic Live run. PostTests.ps1 restores the
        cache config and auth env var.

    A throw here aborts the run; Tests.ps1 still runs PostTests.ps1 for cleanup.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import-IRTConfig runs automatically on module load (via suffix.ps1) and always
# populates $Global:IRT_Config -- either from the user's config file in $env:APPDATA
# or, on first run, by creating that file from the bundled template. If the variable
# is still unset after module import, something is wrong with the installation and
# tests should not proceed with silent defaults.
$IrtConfigVar = Get-Variable -Name 'IRT_Config' -Scope Global -ErrorAction SilentlyContinue
if (-not $IrtConfigVar -or -not $IrtConfigVar.Value) {
    throw ('$Global:IRT_Config not found. ' +
        "If you've never run the module before, try importing to create the user config file.")
}
$KeyCount = ($Global:IRT_Config.PSObject.Properties.Name).Count
Write-Host "Config loaded ($KeyCount keys)." -ForegroundColor Cyan

# --- PSScriptAnalyzer config (consumed by Tests\Test-PSSA.ps1) ---------------
# Test-PSSA.ps1 handles the generic cases (source manifest export field;
# Write-Host under Build\, Tests\, Scripts\, Source\Private\Lib\). Only IRT's
# specifics live here; they are merged on top of those defaults.
$Global:Dev_PSSAConfig = @{
    # Write-IRT is the module's user-output wrapper; allow positional parameters.
    CommandAllowList    = @('Write-IRT')
    # Format-Tree's internal helpers use positional parameters intentionally.
    # RequiredModules.psd1 is a dependency list, not a module manifest, but PSSA
    # applies manifest rules to every .psd1 it sees.
    PerFileSuppressions = @{
        'Source\Private\Lib\Format-Tree\Format-Tree.ps1'  = @('PSAvoidUsingPositionalParameters')
        'Source\ScriptsToProcess\RequiredModules.psd1'    = @('PSMissingModuleManifestField')
    }
    PerPathSuppressions = @{}
}

# --- Live auth/cache setup + run ---------------------------------------------
if ('Live' -in $TestContext.Test) {
    $PesterTestsFolder = $TestContext.PesterTestsFolder

    # Derive the test cache path alongside the primary cache.
    $PrimaryCache = $Global:IRT_Config.MsalCachePath
    $CacheParentDir = Split-Path $PrimaryCache -Parent
    $TestCachePath = Join-Path -Path $CacheParentDir -ChildPath 'irt-testing-cache.bin'

    # Override config for this run: always use the test cache with caching forced
    # on. Originals are stashed on $TestContext so PostTests.ps1 can restore them.
    $TestContext.OriginalCachePath = $Global:IRT_Config.MsalCachePath
    $TestContext.OriginalCacheEnable = $Global:IRT_Config.EnableTokenCache
    $Global:IRT_Config.MsalCachePath = $TestCachePath
    $Global:IRT_Config.EnableTokenCache = $true

    if (-not $TestContext.OriginalCacheEnable) {
        Write-Host ''
        Write-Host '  WARNING: Live tests override the token cache config.' -ForegroundColor Red
        Write-Host "           Test cache : $TestCachePath" -ForegroundColor Red
        Write-Host '         EnableTokenCache has been forced on for this run.' -ForegroundColor Red
    }

    if ($TestContext.InteractiveAuth) {
        $env:IRT_TEST_SILENT_AUTH = '0'
        if (Test-Path $TestCachePath) {
            Remove-Item -Path $TestCachePath -Force
            Write-Host ''
            $Msg = '  Deleted existing test token cache. Interactive sign-in will be required.'
            Write-Host $Msg -ForegroundColor Cyan
        }
    }
    else {
        $env:IRT_TEST_SILENT_AUTH = '1'
    }

    # This hook owns the Live run; tell the orchestrator to skip its generic one.
    $TestContext.LiveHandled = $true

    # Both passes filter on 'live' and exclude 'destructive', matching the
    # orchestrator's own Live run: destructive tests are opted into separately
    # through the Destructive category and its DISPOSABLE_ENVIRONMENT /
    # Confirm-RemoteDisposable.ps1 gates, never as a side effect of a Live run.
    $LiveFilter = @{
        TagFilter        = 'live'
        ExcludeTagFilter = 'destructive'
        PassThru         = $true
    }

    # Pass 1: Connect-IRT.Tests.ps1 runs first. Its BeforeAll genuinely tests
    # Connect-IRT by clearing $Global:IRT_Session and calling it from scratch.
    # On success the session is populated and available to all subsequent files.
    $ConnectTestFile = Join-Path -Path $PesterTestsFolder -ChildPath 'Connect-IRT.Tests.ps1'
    Write-Host "`n=== Invoke-Pester (Live: Connect-IRT) ===" -ForegroundColor Cyan
    $ConnectResult = Invoke-Pester -Path $ConnectTestFile @LiveFilter

    # Failures are added to the orchestrator's counter (this hook is dot-sourced,
    # so the variable is the same one) -- otherwise a hook-owned Live run would
    # always exit 0 and CI could not gate on it.
    $PesterFailedCount += $ConnectResult.FailedCount

    # Pass 2: remaining live tests, only if the connection is now active.
    # Skipping when the connection tests failed avoids a cascade of misleading
    # failures in every downstream test file that relies on the session.
    if ($ConnectResult.FailedCount -gt 0 -or -not $Global:IRT_Session) {
        Write-Host ''
        $Msg = '  Connect-IRT live tests failed or no session was established.'
        Write-Host $Msg -ForegroundColor Red
        Write-Host '  Skipping remaining live tests.' -ForegroundColor Red
    }
    else {
        # *.Lint.Tests.ps1 files are excluded outright: they carry no 'live' tag,
        # but discovering them here would scan the whole repo for nothing.
        $RemainingTests = Get-ChildItem -Path $PesterTestsFolder -Filter '*.Tests.ps1' |
            Where-Object { $_.Name -ne 'Connect-IRT.Tests.ps1' } |
            Where-Object { $_.Name -notlike '*.Lint.Tests.ps1' } |
            Select-Object -ExpandProperty FullName

        if ($RemainingTests) {
            Write-Host "`n=== Invoke-Pester (Live: remaining) ===" -ForegroundColor Cyan
            $RemainingResult = Invoke-Pester -Path $RemainingTests @LiveFilter
            $PesterFailedCount += $RemainingResult.FailedCount
        }
    }
}
