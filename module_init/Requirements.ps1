<#
.SYNOPSIS
    Installs required modules for IncidentResponseTools.

.DESCRIPTION
    Reads RequiredModules from IncidentResponseTools.psd1 and installs each one.
    Version constraints (ModuleVersion, RequiredVersion, MaximumVersion) are read
    directly from the manifest and passed through to Install-Module.

.PARAMETER Scope
    Installation scope: CurrentUser (default) or AllUsers.

.PARAMETER Force
    Pass -Force to Install-Module, overwriting existing installations.

.EXAMPLE
    .\Requirements.ps1

.EXAMPLE
    .\Requirements.ps1 -Scope AllUsers -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Read manifest
# ---------------------------------------------------------------------------
$ManifestPath = Join-Path $PSScriptRoot 'IncidentResponseTools.psd1'

if (-not (Test-Path $ManifestPath)) {
    throw "Module manifest not found at: $ManifestPath"
}

$Manifest        = Import-PowerShellDataFile -Path $ManifestPath
$RequiredModules = $Manifest.RequiredModules

if (-not $RequiredModules) {
    Write-Warning 'No RequiredModules found in manifest.'
    return
}

Write-Host "Found $($RequiredModules.Count) required module(s) in manifest." -ForegroundColor Cyan

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

    $Color = if ($VersionLabel -eq '(latest)') { 'Green' } else { 'Yellow' }
    Write-Host "  $ModuleName  $VersionLabel" -ForegroundColor $Color

    if ($PSCmdlet.ShouldProcess($ModuleName, 'Install-Module')) {
        Install-Module @InstallParams
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
