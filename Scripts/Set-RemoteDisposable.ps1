#Requires -Version 7.5

<#
.SYNOPSIS
    Marks an Entra tenant as disposable, so destructive 'remote' tests may change it.

.DESCRIPTION
    For human use only. Agents must never run this script, and must never mark a
    tenant disposable by any other means. Marking a tenant declares it
    throwaway: destructive tests may then disable users, reset passwords,
    remove devices, and purge mail in it. Running this against a tenant anyone
    depends on lets tests damage it.

    Write half of a pair with Tests\Confirm-RemoteDisposable.ps1, which
    Tests.ps1 runs before any test tagged 'destructive','remote'.

    What it changes: it appends the DisposableMarker address from
    Tests\TestConfig.psd1 to the organization's marketingNotificationEmails,
    leaving any existing entries alone. Nothing else about the tenant is
    touched. -Unmark removes that one address. The address uses the reserved
    .invalid domain, so it can never receive mail. It names no project:
    azure-auth uses the same address, so a tenant marked once is disposable for
    both.

    The tenant is given on the command line every time and never read from the
    environment or Tests\.env.ps1: marking a tenant is a deliberate act, so the
    person running this names the tenant, not a configuration that might point
    somewhere else.

    It signs in with Connect-IRT from this repo's Source\ module, replacing any
    IRT session already open in the window. Reading the marker needs only
    Connect-IRT's default permissions. Changing it needs
    Organization.ReadWrite.All, which in practice means a Global Administrator;
    the script asks for that permission only after you confirm the change, the
    same way Scripts\Revoke-IRTGraphConsent.ps1 does. The first time in a tenant
    this may open a browser to approve it.

.PARAMETER TenantId
    Tenant ID (GUID) to mark or check.

.PARAMETER Status
    Show whether the tenant is marked, and change nothing.

.PARAMETER Unmark
    Remove the marker.

.PARAMETER Trace
    Write debug output.

.OUTPUTS
    None. Writes status to the host.

.EXAMPLE
    .\Scripts\Set-RemoteDisposable.ps1 -TenantId 00000000-0000-0000-0000-000000000000
    Shows the tenant, asks for confirmation, then adds the marker.

.EXAMPLE
    .\Scripts\Set-RemoteDisposable.ps1 -TenantId 00000000-0000-0000-0000-000000000000 -Status
    Shows whether the tenant is marked.

.EXAMPLE
    .\Scripts\Set-RemoteDisposable.ps1 -TenantId 00000000-0000-0000-0000-000000000000 -Unmark
    Asks for confirmation, then removes the marker.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding(DefaultParameterSetName = 'Mark')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $TenantId,

    [Parameter(ParameterSetName = 'Status')]
    [switch] $Status,

    [Parameter(ParameterSetName = 'Unmark')]
    [switch] $Unmark,

    [switch] $Trace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'ScriptVersion')]
$ScriptVersion = '1.0.0'

if ($Trace) { $InformationPreference = 'Continue' }
function Write-Trace {
    param([Parameter(Mandatory)][string] $Message)
    Write-Information $Message -Tags 'Trace'
}

# Asks a yes/no question; anything but 'y' or 'yes' is no.
function Confirm-Choice {
    param([Parameter(Mandatory)][string] $Question)
    $Answer = Read-Host "$Question [y/N]"
    return $Answer.Trim() -in @('y', 'yes')
}

$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Tests\TestConfig.psd1'
$Marker = (Import-PowerShellDataFile -Path $ConfigPath).remote.DisposableMarker
Write-Trace "Set-RemoteDisposable.ps1 $ScriptVersion, marker '$Marker'."

Write-Host ''
Write-Host '== Mark remote target disposable ==' -ForegroundColor Cyan

# import this repo's module, not an installed copy
. (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ModuleRoot.ps1')
$HostModuleInfo = Find-ModuleRoot -Path $PSScriptRoot
$PsdName = "$($HostModuleInfo.Name).psd1"
$SourcePath = Join-Path -Path $HostModuleInfo.Path -ChildPath "Source\$PsdName"
Write-Trace "Importing $SourcePath."
Import-Module $SourcePath

Connect-IRT -TenantId $TenantId -Graph

$OrgRequest = @{
    Method      = 'GET'
    Uri         = 'v1.0/organization?$select=id,displayName,marketingNotificationEmails'
    ErrorAction = 'Stop'
}
$Organization = @((Invoke-MgGraphRequest @OrgRequest).value)[0]
$OrgId = $Organization.id
$Marks = @($Organization.marketingNotificationEmails | ForEach-Object { "$_" })
$Others = @($Marks | Where-Object { $_ -ne $Marker })
$IsMarked = $Others.Count -lt $Marks.Count
$OthersText = if ($Others) { $Others -join ', ' } else { '(none)' }

Write-Host ''
Write-Host "  Display name    : $($Organization.displayName)"
Write-Host "  Tenant ID       : $OrgId"
Write-Host "  Signed in as    : $($Global:IRT_Session.Graph.Account)"
Write-Host '  Field           : organization.marketingNotificationEmails'
Write-Host "  Marker          : $Marker"
Write-Host "  Disposable      : $(if ($IsMarked) { 'YES' } else { 'no' })"
Write-Host "  Other addresses : $OthersText"
Write-Host ''

if ($Status) { return }

if ($Unmark) {
    if (-not $IsMarked) {
        Write-Host 'Not marked; nothing to remove.' -ForegroundColor Green
        return
    }
    Write-Host "Removing '$Marker'. Keeping: $OthersText"
    if (-not (Confirm-Choice -Question 'Remove the disposable marker?')) {
        Write-Host 'Unchanged.' -ForegroundColor Yellow
        return
    }
    $NewList = $Others
    $DoneMsg = 'Marker removed. Destructive remote tests will now refuse to run.'
}
else {
    if ($IsMarked) {
        Write-Host 'Already marked disposable. Nothing to do.' -ForegroundColor Green
        return
    }
    Write-Host "Appending '$Marker'. Keeping: $OthersText"
    $WarnMsg = "This declares '$($Organization.displayName)' a THROWAWAY tenant. " +
    'Destructive tests may then disable users, reset passwords, remove devices, ' +
    'and purge mail in it. Do not do this to a tenant anyone depends on.'
    Write-Host $WarnMsg -ForegroundColor Yellow
    if (-not (Confirm-Choice -Question 'Is this tenant genuinely disposable?')) {
        Write-Host 'Unchanged.' -ForegroundColor Yellow
        return
    }
    $NewList = @($Marks) + $Marker
    $DoneMsg = "Marked. Destructive remote tests may now run against $OrgId."
}

# The session's Graph connection can only read the organization. Mint a separate
# token with the write scope, so the session itself never holds it.
$TokenParams = @{
    Service         = 'Graph'
    AdditionalScope = 'Organization.ReadWrite.All'
}
$Token = (Get-IRTAccessToken @TokenParams).AccessToken
$GraphBaseUrl = $Global:IRT_Session.CloudConfig.Graph
Write-Trace "Acquired an organization write token for $GraphBaseUrl."

$PatchRequest = @{
    Method      = 'PATCH'
    Uri         = "$GraphBaseUrl/v1.0/organization/$OrgId"
    Headers     = @{ Authorization = "Bearer $Token" }
    Body        = @{ marketingNotificationEmails = @($NewList) } | ConvertTo-Json
    ContentType = 'application/json'
    ErrorAction = 'Stop'
}
$null = Invoke-RestMethod @PatchRequest
Write-Host $DoneMsg -ForegroundColor Green
