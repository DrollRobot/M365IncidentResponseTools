function Get-IRTGraphDefaultScope {
    <#
    .SYNOPSIS
    Returns the default Microsoft Graph delegated scopes requested for incident response.

    .DESCRIPTION
    Internal helper. Single source of truth for the default Graph scope set used by
    Get-IRTAccessToken and Connect-IRTGraph. Returns plain scope names (no resource
    URL prefix); callers prefix with the cloud-specific Graph base URL when building
    MSAL scope strings.

    Every ReadWrite permission is requested together with its Read permission, when one
    exists.

    .EXAMPLE
    Get-IRTGraphDefaultScope

    .OUTPUTS
    [string[]] - the default Graph scope names.

    .NOTES
    Version: 1.2.0
    1.2.0 - Added Application.ReadWrite.All for Disable-IRTServicePrincipal, and the Read
    permission alongside each ReadWrite permission.
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
        # Read applications and service principals, including their app role assignments.
        # Used by: Show-IRTServicePrincipal, Get-IRTServicePrincipal, Find-IRTDirectoryObject
        'Application.Read.All'
        # Enable and disable service principals.
        # Used by: Disable-IRTServicePrincipal, Enable-IRTServicePrincipal
        'Application.ReadWrite.All'
        # Read Entra sign-in and directory audit logs.
        # Used by: Get-IRTEntraUserSignInLog, Get-IRTEntraSPSignInLog, Get-IRTEntraAuditLog
        'AuditLog.Read.All'
        # Run Unified Audit Log searches through Graph.
        # Used by: Start-IRTGraphUAL, Receive-IRTGraphUAL
        'AuditLogsQuery.Read.All'
        # Look up basic details of any tenant by ID or domain.
        # Used by: Get-IRTTenantOwner
        'CrossTenantInformation.ReadBasic.All'
        # Read app consent grants.
        # Used by: Get-IRTUserServicePrincipal, Find-IRTRiskyServicePrincipal, Connect-IRT
        'DelegatedPermissionGrant.Read.All'
        # Read Entra device objects.
        # Used by: Find-IRTDevice, Show-IRTDevice, Get-IRTAllEntraDevice
        'Device.Read.All'
        # Read Intune managed devices.
        # Used by: Show-IRTDevice, Find-IRTDevice
        'DeviceManagementManagedDevices.Read.All'
        # Delete Intune managed devices.
        # Used by: Remove-IRTDevice
        'DeviceManagementManagedDevices.ReadWrite.All'
        # Act as the signed-in user, with all of their directory rights.
        # Used by: Disable-IRTDevice, Enable-IRTDevice, Remove-IRTDevice
        'Directory.AccessAsUser.All'
        # Read all directory data (users, groups, roles, devices, apps).
        # Used by: Find-IRTDirectoryObject, Get-IRTAdminRole, Show-IRTServicePrincipal
        'Directory.Read.All'
        # Read the tenant's domains.
        # Used by: Connect-IRT, New-IRTInvestigationFolder, Get-IRTAdminRole
        'Domain.Read.All'
        # Read tenant details, such as licenses and directory sync status.
        # Used by: Get-IRTLicenseReport, Disable-IRTUser, Connect-IRT
        'Organization.Read.All'
        # Read tenant policies, such as the app consent (authorization) policy.
        # Used by: Find-IRTRiskyServicePrincipal
        'Policy.Read.All'
        # Read users' leave dates, which also needs the Lifecycle Workflows Administrator
        # or Global Reader role.
        # Used by: Show-IRTUser
        'User-LifeCycleInfo.Read.All'
        # Reset user passwords. There is no Read permission for password profiles.
        # Used by: Reset-IRTUserPassword
        'User-PasswordProfile.ReadWrite.All'
        # Read user accounts.
        # Used by: Find-IRTUser, Show-IRTUser, Get-IRTAdminRole
        'User.Read.All'
        # Update user accounts, including enable/disable and session revocation.
        # Used by: Disable-IRTUser, Revoke-IRTUserSession, Set-IRTUserUsageLocation
        'User.ReadWrite.All'
        # Read users' MFA methods.
        # Used by: Show-IRTUserMfa
        'UserAuthenticationMethod.Read.All'
        # Remove users' MFA methods. No function removes them; Show-IRTUserMfa prints the
        # Remove-Mg* command for each method, for the analyst to run by hand.
        'UserAuthenticationMethod.ReadWrite.All'

        # No IRT functions use these. They're here so analysts can run Graph commands by
        # hand during investigations.
        # Read basic message details (no body) in mailboxes the user can open.
        'Mail.ReadBasic.Shared'
        # Read Conditional Access policies.
        'Policy.Read.ConditionalAccess'
        # Read Defender XDR alerts.
        'SecurityAlert.Read.All'
        # Read Defender XDR incidents.
        'SecurityIncident.Read.All'
    )
}
