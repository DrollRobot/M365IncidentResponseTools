#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Runs selected test categories for M365IncidentResponseTools.

.DESCRIPTION
    Runs each test category that is explicitly requested via a switch parameter.
    Nothing runs by default -- you must pass at least one flag.

.PARAMETER Offline
    Run Pester tests that do not require connectivity.

.PARAMETER Formatting
    Run all Format-*.ps1 scripts, custom Test-*.ps1 scripts (excluding Test-PSSA),
    and Test-PSSA.ps1 (which applies -AutoFormat then reports remaining issues).
    This step takes 2-3 minutes to load PSScriptAnalyzer; run it after all Pester
    tests are passing.

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

.PARAMETER Agent
    Suppresses human-only test scripts (e.g. Test-FixmeComments.ps1) when running
    -Formatting. Pass this flag when running from an automated agent or CI context
    to avoid spending tokens on informational output that is only useful to humans.

.PARAMETER Built
    Load the module from the built artifact at the repo root (M365IncidentResponseTools.psd1)
    instead of the source manifest. Use this to test the compiled output after running a build.

.EXAMPLE
    .\ tests.ps1 -Offline
    Runs Pester offline tests only.

.EXAMPLE
    .\ tests.ps1 -Offline -Online
    Runs all Pester tests (offline and online).

.EXAMPLE
    .\ tests.ps1 -Formatting
    Runs formatting checks and auto-fixes.

.EXAMPLE
    .\ tests.ps1 -Online
    Runs online tests. Deletes the test token cache and prompts for sign-in.

.EXAMPLE
    .\ tests.ps1 -Online -CachedAuth
    Runs online tests silently using cached credentials (no browser prompt).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [Parameter()]
    [switch] $Offline,

    [Parameter()]
    [switch] $Formatting,

    [Parameter()]
    [switch] $Online,

    [Parameter()]
    [switch] $CachedAuth,

    [Parameter()]
    [switch] $Agent,

    [Parameter()]
    [switch] $Built
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Scripts that produce informational output intended for human review only.
# They are excluded when -Agent is passed.
$HumanOnlyScripts = @('Test-FixmeComments')

if (-not ($Offline -or $Formatting -or $Online)) {
    $Msg = "No test categories selected. Pass -Offline, -Formatting, or -Online."
    Write-Host $Msg -ForegroundColor Yellow
    exit 0
}

# Import the module under test so Pester tests and PSScriptAnalyzer both have
# access to full parameter metadata for all IRT functions and cmdlets.
$ModuleName = Split-Path -Path $PSScriptRoot -Leaf
$ManifestPath = if ($Built) {
    Join-Path -Path $PSScriptRoot -ChildPath "$ModuleName.psd1"
} else {
    Join-Path -Path $PSScriptRoot -ChildPath "source\$ModuleName.psd1"
}
if (Test-Path $ManifestPath) {
    $ModuleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "Loading module..." -ForegroundColor Cyan
    Import-Module $ManifestPath -Force
    $ModuleStopwatch.Stop()
    Write-Host "Module loaded in $($ModuleStopwatch.Elapsed.TotalSeconds)s." -ForegroundColor Cyan

    # Import-IRTConfig runs automatically on module load (via suffix.ps1) and always
    # populates $Global:IRT_Config -- either from the user's config file in $env:APPDATA
    # or, on first run, by creating that file from the bundled template. If the variable
    # is still unset after module import, something is wrong with the installation and
    # tests should not proceed with silent defaults.
    $IrtConfigVar = Get-Variable -Name 'IRT_Config' -Scope Global -ErrorAction SilentlyContinue
    if (-not $IrtConfigVar -or -not $IrtConfigVar.Value) {
        $ErrMsg = '$Global:IRT_Config not found. ' +
            "If you've never run the module before, try importing to create the user config file."
        Write-Error $ErrMsg
        exit 1
    }
    $KeyCount = ($Global:IRT_Config.PSObject.Properties.Name).Count
    Write-Host "Config loaded ($KeyCount keys)." -ForegroundColor Cyan
}
else {
    $ErrMsg = "Module manifest not found at $ManifestPath. " +
    "Make sure you're running this from the repo root and the manifest file is present."
    Write-Error $ErrMsg
    exit 1
}

$TestsFolder = Join-Path -Path $PSScriptRoot -ChildPath 'tests'
$LocalTestsFolder = Join-Path -Path $PSScriptRoot -ChildPath '.local\tests'

# --- Offline ---
if ($Offline) {
    Write-Host "`n=== Invoke-Pester (Offline) ===" -ForegroundColor Cyan
    Invoke-Pester -Path $TestsFolder -ExcludeTagFilter 'Online'
}

# --- Formatting ---
if ($Formatting) {

    # collect all Format-*.ps1 scripts from tests/ and .local/tests/
    $FormatScripts = [System.Collections.Generic.List[System.IO.FileInfo]](
        Get-ChildItem -Path $TestsFolder -Filter 'Format-*.ps1' |
            Where-Object { $_.Name -notlike '*.Tests.ps1' }
    )
    if (Test-Path $LocalTestsFolder) {
        Get-ChildItem -Path $LocalTestsFolder -Filter 'Format-*.ps1' |
            Where-Object { $_.Name -notlike '*.Tests.ps1' } |
            ForEach-Object { $FormatScripts.Add($_) }
    }
    $FormatScripts = $FormatScripts | Sort-Object Name

    # run each Format-*.ps1 script first, before any of the Test-*.ps1 scripts
    foreach ($Script in $FormatScripts) {
        $RelPath = [System.IO.Path]::GetRelativePath($PSScriptRoot, $Script.FullName)
        Write-Host "`n=== $RelPath ===" -ForegroundColor Cyan
        & $Script.FullName -Path $PSScriptRoot -Recurse
    }

    # collect all Test-*.ps1 scripts from tests/ and .local/tests/, exempting Test-PSSA
    $TestScripts = [System.Collections.Generic.List[System.IO.FileInfo]](
        Get-ChildItem -Path $TestsFolder -Filter 'Test-*.ps1' |
            Where-Object {
                $_.BaseName -ne 'Test-PSSA' -and
                $_.Name -notlike '*.Tests.ps1' -and
                -not ($Agent -and $HumanOnlyScripts -contains $_.BaseName)
            }
    )
    if (Test-Path $LocalTestsFolder) {
        Get-ChildItem -Path $LocalTestsFolder -Filter 'Test-*.ps1' |
            Where-Object { $_.Name -notlike '*.Tests.ps1' } |
            ForEach-Object { $TestScripts.Add($_) }
    }
    $TestScripts = $TestScripts | Sort-Object Name

    # run each Test-*.ps1 script
    foreach ($Script in $TestScripts) {
        $RelPath = [System.IO.Path]::GetRelativePath($PSScriptRoot, $Script.FullName)
        Write-Host "`n=== $RelPath ===" -ForegroundColor Cyan
        & $Script.FullName -Path $PSScriptRoot -Recurse
    }

    Write-Host "`n=== Test-PSSA ===" -ForegroundColor Cyan
    $AnalyzerScript = Join-Path -Path $TestsFolder -ChildPath 'Test-PSSA.ps1'
    & $AnalyzerScript -Path $PSScriptRoot -Recurse -AutoFormat
}

# --- Online ---
if ($Online) {
    # Derive the test cache path alongside the primary cache.
    $PrimaryCache = $Global:IRT_Config.MsalCachePath
    $CacheParentDir = Split-Path $PrimaryCache -Parent
    $TestCachePath = Join-Path -Path $CacheParentDir -ChildPath 'irt-testing-cache.bin'

    # Override config for this run: always use the test cache with caching forced on.
    $OriginalCachePath = $Global:IRT_Config.MsalCachePath
    $OriginalCacheEnable = $Global:IRT_Config.EnableTokenCache
    $Global:IRT_Config.MsalCachePath = $TestCachePath
    $Global:IRT_Config.EnableTokenCache = $true

    if (-not $OriginalCacheEnable) {
        Write-Host ''
        Write-Host '  WARNING: Online tests override the token cache config.' -ForegroundColor Red
        Write-Host "           Test cache : $TestCachePath" -ForegroundColor Red
        Write-Host '         EnableTokenCache has been forced on for this run.' -ForegroundColor Red
    }

    if ($CachedAuth) {
        $env:IRT_TEST_SILENT_AUTH = '1'
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
    $ConnectTestFile = Join-Path -Path $TestsFolder -ChildPath 'Connect-IRT.Tests.ps1'
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
        $Global:IRT_Config.MsalCachePath = $OriginalCachePath
        $Global:IRT_Config.EnableTokenCache = $OriginalCacheEnable
        $env:IRT_TEST_SILENT_AUTH = $null
    }
}
