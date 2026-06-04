<#
.SYNOPSIS
    Installs required modules for a PowerShell module.

.DESCRIPTION
    Discovers the .psd1 manifest in the same directory as this script, reads
    RequiredModules, and installs each one.  Version constraints
    (ModuleVersion, RequiredVersion, MaximumVersion) are read directly from
    the manifest and passed through to Install-Module.

    The script must be placed in the root folder of a PowerShell module
    (i.e. alongside the .psd1 file).

.PARAMETER Scope
    Installation scope: CurrentUser (default) or AllUsers.

.PARAMETER Force
    Pass -Force to Install-Module, overwriting existing installations.

.EXAMPLE
    .\Install-Dependencies.ps1

.PARAMETER Check
    Check whether all required modules are installed without installing anything.
    If any are missing, prints the exact command to run to install them.

.PARAMETER Quiet
    Suppress all informational output. When combined with -Check, produces no output
    if all modules are satisfied; prints only the missing-modules summary if any are missing.
    Useful for CI or wrapper scripts.

.EXAMPLE
    .\Install-Dependencies.ps1 -Scope AllUsers -WhatIf

.EXAMPLE
    .\Install-Dependencies.ps1 -Check

.EXAMPLE
    .\Install-Dependencies.ps1 -Check -Quiet

.NOTES
Version 1.1.0
1.1.0 - Added -Check and -Quiet parameters and hard coded module list for better integration 
        with Confirm-Dependencies.ps1.

# FIXME add mixed graph module versions as a failure mode.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force,

    [switch]$Check,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$DarkCyan = @{ForegroundColor = 'DarkCyan' }
$Yellow = @{ForegroundColor = 'Yellow' }

# ---------------------------------------------------------------------------
# Hard-coded fallback module list
#
# Used only when the manifest's RequiredModules cannot be read (missing,
# empty, or the manifest itself can't be found).
# ---------------------------------------------------------------------------
$HardCodedRequiredModules = @(
    @{ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.DeviceManagement'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Beta.Identity.Signins'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Beta.Reports'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.DirectoryObjects'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Identity.Signins'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Reports'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Users'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'Microsoft.Graph.Users.Actions'; ModuleVersion = '2.27.0' }
    @{ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.4.0' }
    @{ModuleName = 'ImportExcel'; ModuleVersion = '7.8.0' }
    @{ModuleName = 'PSToml'; ModuleVersion = '0.3.0' }
    @{ModuleName = 'PSFramework'; ModuleVersion = '1.13.426' }
)

# ---------------------------------------------------------------------------
# Discover manifest
# ---------------------------------------------------------------------------
$ManifestFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.psd1' -File)

$RequiredModules = $null
$FromManifest = $false

if (($ManifestFiles | Measure-Object).Count -eq 0) {
    # No manifest present -- silently fall back to the hard-coded list below.
}
elseif (($ManifestFiles | Measure-Object).Count -gt 1) {
    $names = $ManifestFiles.Name -join ', '
    Write-Warning "Multiple .psd1 manifests found in $PSScriptRoot ($names). Cannot determine which to use."
}
else {
    $ManifestPath = $ManifestFiles[0].FullName
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $RequiredModules = $Manifest.RequiredModules
    if ($RequiredModules) {
        $FromManifest = $true
    }
}

if (-not $RequiredModules) {
    $RequiredModules = $HardCodedRequiredModules
}

if (-not $RequiredModules) {
    Write-Warning 'No required modules to install.'
    return
}

$SourcePath = if ($FromManifest) { $ManifestPath } else { $PSCommandPath }

if (-not $Quiet) {
    Write-Host @DarkCyan "Using source: $SourcePath"
    Write-Host @DarkCyan "Found $($RequiredModules.Count) required module(s)."
}

# ---------------------------------------------------------------------------
# Install each module
# ---------------------------------------------------------------------------
$Missing = @()
foreach ($Entry in $RequiredModules) {
    # RequiredModules entries can be a plain string or a hashtable with version constraints
    if ($Entry -is [hashtable]) {
        $ModuleName = $Entry.ModuleName
    }
    else {
        $ModuleName = $Entry
    }

    $InstallParams = @{
        Name  = $ModuleName
        Scope = $Scope
    }

    $VersionLabel = '(latest)'

    if ($Entry -is [hashtable]) {
        if ($Entry.ContainsKey('RequiredVersion')) {
            $InstallParams['RequiredVersion'] = $Entry.RequiredVersion
            $VersionLabel = "== v$($Entry.RequiredVersion)"
        }
        else {
            if ($Entry.ContainsKey('ModuleVersion')) {
                $InstallParams['MinimumVersion'] = $Entry.ModuleVersion
                $VersionLabel = ">= $($Entry.ModuleVersion)"
            }
            if ($Entry.ContainsKey('MaximumVersion')) {
                $InstallParams['MaximumVersion'] = $Entry.MaximumVersion
                $VersionLabel += "<= $($Entry.MaximumVersion)"
            }
            $VersionLabel = $VersionLabel.Trim()
        }
    }

    # ------------------------------------------------------------------
    # Check whether the requirement is already satisfied
    # ------------------------------------------------------------------
    $InstalledVersions = @(
        Get-Module -Name $ModuleName -ListAvailable |
            Select-Object -ExpandProperty Version
    )

    $Satisfied = $false
    if ($InstalledVersions.Count -gt 0) {
        if ($Entry -is [hashtable] -and $Entry.ContainsKey('RequiredVersion')) {
            $Required = [version]$Entry.RequiredVersion
            $Satisfied = $InstalledVersions -contains $Required
        }
        else {
            $Min = if ($Entry -is [hashtable] -and $Entry.ContainsKey('ModuleVersion')) {
                [version]$Entry.ModuleVersion
            }
            else { $null }
            $Max = if ($Entry -is [hashtable] -and $Entry.ContainsKey('MaximumVersion')) {
                [version]$Entry.MaximumVersion
            } else { $null }
            $Satisfied = $null -ne (
                $InstalledVersions | Where-Object {
                    ($null -eq $Min -or $_ -ge $Min) -and
                    ($null -eq $Max -or $_ -le $Max)
                } | Select-Object -First 1
            )
        }
    }

    if ($Satisfied) {
        if (-not $Quiet) {
            if ($Check) {
                Write-Host "    $ModuleName $VersionLabel -- OK"
            }
            else {
                Write-Host "    $ModuleName $VersionLabel - already installed, skipping."
            }
        }
        continue
    }

    if ($Check) {
        $Missing += $ModuleName
        if (-not $Quiet) {
            Write-Host @Yellow "    $ModuleName $VersionLabel -- MISSING"
        }
        continue
    }

    $ColorParam = if ($VersionLabel -eq '(latest)') { $DarkCyan } else { $Yellow }
    Write-Host @ColorParam "Installing $ModuleName $VersionLabel"

    if ($PSCmdlet.ShouldProcess($ModuleName, 'Install-Module')) {
        Install-Module @InstallParams
    }
}

if ($Check) {
    $Stopwatch.Stop()
    $Elapsed = $Stopwatch.Elapsed.TotalSeconds
    Write-Verbose "Install-Dependencies: Check completed in $($Elapsed.ToString('N2'))s."
    if ($Missing.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host @DarkCyan "All required modules are installed."
        }
    }
    else {
        if (-not $Quiet) {
            Write-Host @Yellow "$($Missing.Count) module(s) missing. To install, run:"
            $SelfPath = Join-Path -Path $PSScriptRoot -ChildPath 'Install-Dependencies.ps1'
            Write-Host @Yellow "& '$SelfPath'"
        }
        exit 1
    }
    return
}

if (-not $Quiet) {
    Write-Host @DarkCyan "Done."
}
