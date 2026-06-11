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
    Version: 1.0.0
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
        'Application.ReadWrite.All'
        'AuditLog.Read.All'
        'AuditLogsQuery.Read.All'
        'BitLockerKey.Read.All'
        'CrossTenantInformation.ReadBasic.All'
        'DelegatedPermissionGrant.ReadWrite.All'
        'Device.ReadWrite.All'
        'DeviceLocalCredential.Read.All'
        'DeviceManagementApps.ReadWrite.All'
        'DeviceManagementConfiguration.ReadWrite.All'
        'DeviceManagementManagedDevices.ReadWrite.All'
        'DeviceManagementServiceConfig.ReadWrite.All'
        'Directory.AccessAsUser.All'
        'Directory.ReadWrite.All'
        'Domain.Read.All'
        'Group.ReadWrite.All'
        'GroupMember.ReadWrite.All'
        'IdentityRiskEvent.ReadWrite.All'
        'IdentityRiskyServicePrincipal.ReadWrite.All'
        'IdentityRiskyUser.ReadWrite.All'
        'Mail.ReadBasic.Shared'
        'Organization.Read.All'
        'Policy.Read.All'
        'Policy.Read.ConditionalAccess'
        'Policy.ReadWrite.Authorization'
        'RoleManagement.ReadWrite.Directory'
        'SecurityEvents.ReadWrite.All'
        'SecurityIncident.ReadWrite.All'
        'User-Mail.ReadWrite.All'
        'User-PasswordProfile.ReadWrite.All'
        'User-Phone.ReadWrite.All'
        'User.EnableDisableAccount.All'
        'User.ManageIdentities.All'
        'User.ReadWrite.All'
        'User.RevokeSessions.All'
        'UserAuthenticationMethod.ReadWrite'
        'UserAuthenticationMethod.ReadWrite.All'
        'UserAuthMethod-Passkey.ReadWrite.All'
    )
}
