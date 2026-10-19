#Requires -Version 7.5

<#
.SYNOPSIS
    Project-specific test teardown for M365IncidentResponseTools (IRT).

.DESCRIPTION
    Dot-sourced by Tests.ps1 in a finally block, so it always runs -- even if a
    test section or PreTests.ps1 threw. Restores the token-cache config and clears
    the auth and strict-error env vars that PreTests.ps1 set for a Live or
    Destructive run. Reads saved values from the shared $TestContext hashtable and
    guards each one so a partial or failed setup still tears down cleanly.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Only Live and Destructive runs override config; the saved cache path is the
# signal that PreTests mutated it. Nothing to restore otherwise.
if ($TestContext.ContainsKey('OriginalCachePath')) {
    if ($TestContext.ContainsKey('OriginalCachePath')) {
        $Global:IRT_Config.MsalCachePath = $TestContext.OriginalCachePath
    }
    if ($TestContext.ContainsKey('OriginalCacheEnable')) {
        $Global:IRT_Config.EnableTokenCache = $TestContext.OriginalCacheEnable
    }
    $env:IRT_TEST_SILENT_AUTH = $null
    $env:IRT_TEST_STRICT_ERRORS = $null
}
