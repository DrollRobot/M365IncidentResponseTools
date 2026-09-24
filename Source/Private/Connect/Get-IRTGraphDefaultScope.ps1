function Get-IRTGraphDefaultScope {
    <#
    .SYNOPSIS
    Returns the default Microsoft Graph delegated scopes requested for incident response.

    .DESCRIPTION
    Internal helper. Single source of truth for the default Graph scope set used by
    Get-IRTAccessToken and Connect-IRTGraph. Returns plain scope names (no resource
    URL prefix); callers prefix with the cloud-specific Graph base URL when building
    MSAL scope strings.

    .EXAMPLE
    Get-IRTGraphDefaultScope

    .OUTPUTS
    [string[]] - the default Graph scope names.

    .NOTES
    Version: 1.1.0
    #>
    [OutputType([string[]])]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', '',
        Justification = 'Returns a scope list; singular noun reads as the scope set.')]
    param()

    Import-IRTModule -Name 'PSFramework'

    Write-PSFMessage -Level 9 -Message 'Get-IRTGraphDefaultScope: returning default scope set.'

    return [string[]]@(
        'AuditLog.Read.All'
        'AuditLogsQuery.Read.All'
        'CrossTenantInformation.ReadBasic.All'
        'DelegatedPermissionGrant.ReadWrite.All'
        'Device.Read.All'
        'DeviceManagementApps.Read.All'
        'DeviceManagementConfiguration.Read.All'
        # ReadWrite: Remove-IRTDevice deletes the Intune managed device record.
        'DeviceManagementManagedDevices.ReadWrite.All'
        'DeviceManagementServiceConfig.Read.All'
        # Delegated device update/delete accept no other scope (Set-IRTDeviceEnabled,
        # Remove-IRTDevice).
        'Directory.AccessAsUser.All'
        'Directory.Read.All'
        'Domain.Read.All'
        'Mail.ReadBasic.Shared'
        'Organization.Read.All'
        'Policy.Read.All'
        'Policy.Read.ConditionalAccess'
        'SecurityEvents.ReadWrite.All'
        'SecurityIncident.ReadWrite.All'
        # Least-privileged scope for passwordProfile; User.ReadWrite.All does not cover it.
        'User-PasswordProfile.ReadWrite.All'
        'User.ManageIdentities.All'
        'User.ReadWrite.All'
        'UserAuthenticationMethod.ReadWrite.All'
    )
}
