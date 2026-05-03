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

.EXAMPLE
    .\Install-Dependencies.ps1 -Scope AllUsers -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$DarkCyan = @{ForegroundColor = 'DarkCyan'}
$Yellow   = @{ForegroundColor = 'Yellow'}

# ---------------------------------------------------------------------------
# Discover manifest
# ---------------------------------------------------------------------------
$ManifestFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.psd1' -File)

if (($ManifestFiles | Measure-Object).Count -eq 0) {
    throw "No .psd1 manifest found in: $PSScriptRoot"
}
if (($ManifestFiles | Measure-Object).Count -gt 1) {
    $names = $ManifestFiles.Name -join ', '
    throw "Multiple .psd1 manifests found in $PSScriptRoot ($names). Cannot determine which to use."
}

$ManifestPath = $ManifestFiles[0].FullName
Write-Host @DarkCyan "Using manifest: $ManifestPath"

$Manifest        = Import-PowerShellDataFile -Path $ManifestPath
$RequiredModules = $Manifest.RequiredModules

if (-not $RequiredModules) {
    Write-Warning 'No RequiredModules found in manifest.'
    return
}

Write-Host @DarkCyan "Found $($RequiredModules.Count) required module(s) in manifest."

# ---------------------------------------------------------------------------
# Install each module
# ---------------------------------------------------------------------------
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
        Force = $Force.IsPresent
    }

    $VersionLabel = '(latest)'

    if ($Entry -is [hashtable]) {
        if ($Entry.RequiredVersion) {
            $InstallParams['RequiredVersion'] = $Entry.RequiredVersion
            $VersionLabel = "v$($Entry.RequiredVersion) [exact]"
        }
        else {
            if ($Entry.ModuleVersion) {
                $InstallParams['MinimumVersion'] = $Entry.ModuleVersion
                $VersionLabel = ">= $($Entry.ModuleVersion)"
            }
            if ($Entry.MaximumVersion) {
                $InstallParams['MaximumVersion'] = $Entry.MaximumVersion
                $VersionLabel += " <= $($Entry.MaximumVersion)"
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
        if ($Entry -is [hashtable] -and $Entry.RequiredVersion) {
            $Required  = [version]$Entry.RequiredVersion
            $Satisfied = $InstalledVersions -contains $Required
        }
        else {
            $Min = if ($Entry -is [hashtable] -and $Entry.ModuleVersion)  { [version]$Entry.ModuleVersion  } else { $null }
            $Max = if ($Entry -is [hashtable] -and $Entry.MaximumVersion) { [version]$Entry.MaximumVersion } else { $null }
            $Satisfied = $null -ne (
                $InstalledVersions | Where-Object {
                    ($null -eq $Min -or $_ -ge $Min) -and
                    ($null -eq $Max -or $_ -le $Max)
                } | Select-Object -First 1
            )
        }
    }

    if ($Satisfied) {
        Write-Host @DarkCyan "  $ModuleName $VersionLabel - already satisfied, skipping."
        continue
    }

    $ColorParam = if ($VersionLabel -eq '(latest)') { $DarkCyan } else { $Yellow }
    Write-Host @ColorParam "Installing $ModuleName $VersionLabel"

    if ($PSCmdlet.ShouldProcess($ModuleName, 'Install-Module')) {
        Install-Module @InstallParams
    }
}

Write-Host @DarkCyan "Done."
