#Requires -Version 7.5

<#
.SYNOPSIS
    Checks whether the test tenant is marked disposable.

.DESCRIPTION
    Read half of a pair with Scripts\Set-RemoteDisposable.ps1, which writes the
    marker this script looks for. Tests.ps1 runs this before any Pester test
    tagged 'destructive','remote' and only cares whether it throws: a clean
    return means the tenant is confirmed disposable, a thrown error means
    refuse. It never calls `exit`, which can close the calling host session.

    The marker is the DisposableMarker address in Tests\TestConfig.psd1, placed
    in the organization's marketingNotificationEmails. It lives on the tenant,
    not in a local file, so pointing tests at a different tenant refuses on its
    own. It names no project: azure-auth reads the same address, so a tenant
    marked once is disposable for both.

    The check uses the Graph connection PreTests.ps1 opens for the run, and
    refuses unless that connection is to $env:IRT_TEST_TENANT_ID. Reading the
    marker needs Organization.Read.All, which Connect-IRT already requests.

.PARAMETER Trace
    Write debug output.

.OUTPUTS
    None. Prints a message and returns normally if the tenant is confirmed
    disposable, or throws otherwise.

.EXAMPLE
    .\Tests\Confirm-RemoteDisposable.ps1
    Runs the check against the connected test tenant; throws if it is not
    marked disposable.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [switch] $Trace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Trace) { $InformationPreference = 'Continue' }
function Write-Trace {
    param([Parameter(Mandatory)][string] $Message)
    Write-Information $Message -Tags 'Trace'
}

# Returns whether the connected test tenant carries the disposable marker.
# Prints a message for a human to read; the message is not parsed by the caller.
function Confirm-RemoteDisposable {
    [OutputType([bool])]
    param()

    $TenantId = $env:IRT_TEST_TENANT_ID
    if (-not $TenantId) {
        Write-Host 'IRT_TEST_TENANT_ID is not set (see Tests\.env.ps1).' -ForegroundColor Red
        return $false
    }

    $Session = Get-Variable -Name 'IRT_Session' -Scope Global -ValueOnly -ErrorAction Ignore
    if (-not ($Session -and $Session.Graph)) {
        Write-Host 'No IRT Graph connection to check the tenant with.' -ForegroundColor Red
        return $false
    }
    if ($Session.TenantId -ne $TenantId) {
        $Msg = "Connected to tenant $($Session.TenantId), not the test tenant $TenantId."
        Write-Host $Msg -ForegroundColor Red
        return $false
    }

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestConfig.psd1'
    $Marker = (Import-PowerShellDataFile -Path $ConfigPath).remote.DisposableMarker
    Write-Trace "Looking for '$Marker' on tenant $TenantId."

    $OrgRequest = @{
        Method      = 'GET'
        Uri         = 'v1.0/organization?$select=id,displayName,marketingNotificationEmails'
        ErrorAction = 'Stop'
    }
    $Organizations = @((Invoke-MgGraphRequest @OrgRequest).value)

    foreach ($Organization in $Organizations) {
        Write-Trace "Organization $($Organization.id): $($Organization.displayName)"
        if ($Organization.id -ne $TenantId) { continue }
        $Marks = @($Organization.marketingNotificationEmails | ForEach-Object { "$_".ToLower() })
        if ($Marker.ToLower() -in $Marks) {
            $Msg = "'$($Organization.displayName)' ($TenantId) is marked disposable."
            Write-Host $Msg -ForegroundColor Cyan
            return $true
        }
    }

    $Msg = "Tenant $TenantId is NOT marked disposable: no '$Marker' in the " +
    "organization's marketingNotificationEmails. A human can mark a throwaway " +
    'tenant with Scripts\Set-RemoteDisposable.ps1.'
    Write-Host $Msg -ForegroundColor Red
    return $false
}

$Confirmed = $false
try {
    $Confirmed = Confirm-RemoteDisposable
}
catch {
    Write-Host "Disposable check failed: $_" -ForegroundColor Red
}
if (-not $Confirmed) {
    throw "Remote target is not confirmed disposable; destructive 'remote' tests refuse."
}
