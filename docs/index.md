# M365 Incident Response Tools

M365IncidentResponseTools is a Powershell module for incident response
investigations. It provides commands to collect sign-in logs, audit logs, mailbox data,
OAuth application assignments, admin roles, and on-premises Active Directory information --
all structured for rapid triage and export to Excel.

## Quick Start

```powershell
# Connect to Graph and Exchange Online
Connect-IRT

# Resolve a user and load into the session
Get-IRTUserObject -UserPrincipalName user@contoso.com

# Run the full investigation playbook
Start-IncidentResponsePlaybook
```

## Playbook

The [incident response playbook](playbook.md) (`Start-IncidentResponsePlaybook`) orchestrates
up to 15 data-collection steps in parallel using a runspace pool. Each step writes its output
to a timestamped investigation folder. Commands marked **Yes** in the Playbook column below
are called automatically by the playbook.

See [Playbook](playbook.md) for a detailed step-by-step breakdown.

---

## M365 / Cloud Commands

| Command | Category | Playbook | Description |
|---------|----------|----------|-------------|
| [Start-IncidentResponsePlaybook](commands/Start-IncidentResponsePlaybook.md) | Playbook | Yes | Runs multiple functions to assist in investigating a user's activity. |
| [Find-RiskyApplication](commands/Find-RiskyApplication.md) | Applications | Yes | Identifies potentially malicious OAuth applications registered in the tenant. |
| [Get-IRTTenantInfo](commands/Get-IRTTenantInfo.md) | Applications | | Resolves a tenant GUID to its organization name, default domain, and cloud environment. |
| [Get-UserApplication](commands/Get-UserApplication.md) | Applications | Yes | Displays user's OAuth2 permission grants. |
| [Show-TenantServicePrincipal](commands/Show-TenantServicePrincipal.md) | Applications | | Displays all service principals in the tenant, or filters by a search term. |
| [Connect-IRT](commands/Connect-IRT.md) | Connect | | Connects to Microsoft Graph and Exchange Online for incident response. |
| [Connect-IRTExchange](commands/Connect-IRTExchange.md) | Connect | | Connects to Exchange Online. |
| [Connect-IRTGraph](commands/Connect-IRTGraph.md) | Connect | | Connects to Microsoft Graph with default incident response scopes. |
| [Connect-IRTIPPS](commands/Connect-IRTIPPS.md) | Connect | | Connects to Security and Compliance PowerShell (IPPS). |
| [Connect-IRTTenant](commands/Connect-IRTTenant.md) | Connect | | Connects to a tenant using a friendly alias from a tenant configuration worksheet. |
| [Disconnect-IRT](commands/Disconnect-IRT.md) | Connect | | Disconnects from Microsoft Graph and Exchange Online and cleans up session state. |
| [Open-IRTTenantWorksheet](commands/Open-IRTTenantWorksheet.md) | Connect | | Opens the tenants worksheet for editing. |
| [Test-IRTConnection](commands/Test-IRTConnection.md) | Connect | | Shows which IRT services are connected and to which tenant. |
| [Show-DeviceInfo](commands/Show-DeviceInfo.md) | Devices | | Displays Entra and Intune device properties for combined device objects. |
| [Get-EntraAuditLog](commands/Get-EntraAuditLog.md) | Entra Audit Log | Yes | Downloads Entra ID audit log events for one or more users. |
| [Show-EntraAuditLog](commands/Show-EntraAuditLog.md) | Entra Audit Log | | Shows Entra audit logs in terminal, or saves as an Excel spreadsheet. |
| [Get-IRTInboxRule](commands/Get-IRTInboxRule.md) | Mailbox | Yes | Retrieves and displays Exchange Online inbox rules for one or more users. |
| [Get-UserMailboxPermission](commands/Get-UserMailboxPermission.md) | Mailbox | | Retrieves mailbox permission delegations for one or more users. |
| [Grant-MailboxFullAccess](commands/Grant-MailboxFullAccess.md) | Mailbox | | Grants the currently logged-in user full access to the target user's mailbox. |
| [Open-MailboxInOWA](commands/Open-MailboxInOWA.md) | Mailbox | | Opens a user mailbox in OWA in a browser. |
| [Remove-MailboxFullAccess](commands/Remove-MailboxFullAccess.md) | Mailbox | | Removes full access to the target user's mailbox. |
| [Show-Mailbox](commands/Show-Mailbox.md) | Mailbox | Yes | Displays mailbox properties. |
| [Show-MailboxAccess](commands/Show-MailboxAccess.md) | Mailbox | | Shows mailbox permission delegations. |
| [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) | Message Trace | Yes | Downloads incoming and outgoing message trace for a specified user or all users. |
| [Show-IRTMessageTrace](commands/Show-IRTMessageTrace.md) | Message Trace | | Processes message trace data and creates a spreadsheet. |
| [Get-AdminRole](commands/Get-AdminRole.md) | Roles | Yes | Reports all Entra ID directory role members for the tenant. |
| [Get-NonInteractiveLog](commands/Get-NonInteractiveLog.md) | Sign-in Logs | Yes | Downloads non-interactive Entra ID sign-in logs for one or more users. |
| [Get-SignInLog](commands/Get-SignInLog.md) | Sign-in Logs | Yes | Downloads user sign-in logs. |
| [Show-SignInLog](commands/Show-SignInLog.md) | Sign-in Logs | | Processes a sign-in log XML file into an Excel spreadsheet. |
| [Get-UALog](commands/Get-UALog.md) | Unified Audit Log | Yes | Runs multiple queries to pull all Unified Audit Log records for a specific user. |
| [Show-UALog](commands/Show-UALog.md) | Unified Audit Log | | Parses and displays unified audit logs. |
| [Find-User](commands/Find-User.md) | Users | | Finds a Graph user by display name, email address, or user ID GUID. |
| [Get-FullUserObject](commands/Get-FullUserObject.md) | Users | | Retrieves a user with a broad set of properties and optional augmentations. |
| [Revoke-UserSession](commands/Revoke-UserSession.md) | Users | | Revokes all active sessions for one or more users. |
| [Set-UsageLocation](commands/Set-UsageLocation.md) | Users | | Sets a user's usage location. |
| [Show-UserInfo](commands/Show-UserInfo.md) | Users | Yes | Displays user properties. |
| [Show-UserMFA](commands/Show-UserMFA.md) | Users | Yes | Shows a Graph user's MFA methods. |
| [Compress-InvestigationFolder](commands/Compress-InvestigationFolder.md) | Utilities | | Compresses all investigation folders into a single archive. |
| [Copy-IRTFunction](commands/Copy-IRTFunction.md) | Utilities | | Copies IRT helper function contents to the clipboard. |
| [Find-GraphDirectoryObject](commands/Find-GraphDirectoryObject.md) | Utilities | | Searches Entra ID directory objects by display name or ID. |
| [Get-IRTUserObject](commands/Get-IRTUserObject.md) | Utilities | | Gets user objects from global session variables. |
| [Get-LicenseReport](commands/Get-LicenseReport.md) | Utilities | Yes | Shows a table of tenant licenses. |
| [Import-IRTConfig](commands/Import-IRTConfig.md) | Utilities | | Loads the current IRT configuration. |
| [Import-LogFile](commands/Import-LogFile.md) | Utilities | | Imports a structured log file for processing. |
| [New-InvestigationFolder](commands/New-InvestigationFolder.md) | Utilities | | Makes a new directory based on client and user info. |
| [Open-IRTConfig](commands/Open-IRTConfig.md) | Utilities | | Opens the IRT config.json file for editing. |
| [Request-DirectoryRole](commands/Request-DirectoryRole.md) | Utilities | | Requests directory roles from Microsoft Graph. |
| [Request-DirectoryRoleTemplate](commands/Request-DirectoryRoleTemplate.md) | Utilities | | Requests directory role templates from Microsoft Graph. |
| [Request-GraphDevice](commands/Request-GraphDevice.md) | Utilities | | Requests Entra and Intune devices from Microsoft Graph. |
| [Request-GraphGroup](commands/Request-GraphGroup.md) | Utilities | | Requests groups from Microsoft Graph. |
| [Request-GraphOauth2Grant](commands/Request-GraphOauth2Grant.md) | Utilities | | Requests OAuth2 permission grants from Microsoft Graph. |
| [Request-GraphServicePrincipal](commands/Request-GraphServicePrincipal.md) | Utilities | | Requests service principals from Microsoft Graph. |
| [Request-GraphUser](commands/Request-GraphUser.md) | Utilities | | Requests users from Microsoft Graph. |
| [Resolve-IRTDateRange](commands/Resolve-IRTDateRange.md) | Utilities | | Validates and resolves date range parameters into a standardized object. |
| [Set-IRTConfig](commands/Set-IRTConfig.md) | Utilities | | Interactively updates IRT configuration settings. |
| [Write-IRT](commands/Write-IRT.md) | Utilities | | Writes a colored, prefixed status message to the host. |

---

## On-Premises AD Commands

None of the on-premises AD commands run as part of the playbook. They are standalone utilities
for investigating Active Directory users, OUs, and domain controllers.

| Command | Description |
|---------|-------------|
| [Disable-AdUser](commands/Disable-AdUser.md) | Disables on-premises AD user account(s). |
| [Enable-AdUser](commands/Enable-AdUser.md) | Enables on-premises AD user account(s). |
| [Find-AdOu](commands/Find-AdOu.md) | Searches for specific OUs by name or distinguished name fragment. |
| [Find-AdUser](commands/Find-AdUser.md) | Finds a local AD user by display name, UPN, proxy address, SAM account name, or GUID. |
| [Find-AllDomainController](commands/Find-AllDomainController.md) | Lists the names of all domain controllers in the current AD domain. |
| [Get-AdAdminUser](commands/Get-AdAdminUser.md) | Displays a list of privileged AD admin users. |
| [Push-AdSync](commands/Push-AdSync.md) | Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle. |
| [Reset-AdUserPassword](commands/Reset-AdUserPassword.md) | Resets an Active Directory user's password. |
| [Show-AdOus](commands/Show-AdOus.md) | Shows a list of all OUs with a count of users and devices. |
| [Show-AdUserInfo](commands/Show-AdUserInfo.md) | Displays AD user properties. |
