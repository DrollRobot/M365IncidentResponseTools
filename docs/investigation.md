# Investigation

Before running investigation commands, select a target user.

```powershell
Find-User -Search joseph.smith
FindUser joseph,sarah,mary
```
Find-User uses regex matching against all users DisplayName, Id, OnPremesisSamAccountName, and all Mail/Proxy addresses. If the search query matches multiple users, none will be selected and a warning will be shown.
Multiple users can be selected if multiple search queries are passed.
If a search returns only one user, the user object will be saved in `$Global:IRT_UserObjects`, which most commands read from automatically when no `-UserObject` parameter is provided. (-UserObject expects a Graph user object)

## Running the Investigation Playbook

The investigation playbook runs ~15 commands in parallel to return results quickly. By default, it will create a new folder, move into the folder, and save all files there. 

```powershell
# run all playbook commands
Start-IncidentResponsePlaybook

# run playbook for specific user with ticket number in folder name
Start-IncidentResponsePlaybook -UserObject $User -Ticket 'INC-1234'

# limit parallelism on slower devices
Start-IncidentResponsePlaybook -MaxRunspaces 5
```

## Investigation Folder

Unless `-NoFolder` is specified, the playbook creates a folder at the current path where output files are save.
```
..\
  <domain>_<username>_<ticket>_<datetime>_Investigation\
    InboxRules*.xlsx
    SignInLogs*.xlsx
    ...
```

## Playbook Steps

The following steps run in parallel.

| Command | Description |
|---------|-------------|
| [Get-LicenseReport](commands/Get-LicenseReport.md) | Displays tenant license consumption across all subscribed SKUs. |
| [Show-UserInfo](commands/Show-UserInfo.md) | Displays all user properties as a formatted tree. |
| [Get-UserApplication](commands/Get-UserApplication.md) | Lists OAuth2 applications the user has personally consented to. |
| [Show-Mailbox](commands/Show-Mailbox.md) | Displays Exchange Online mailbox configuration including quotas, forwarding, hold status, and permissions. |
| [Get-AdminRole](commands/Get-AdminRole.md) | Lists all Entra ID directory roles and their effective members, expanding nested groups inline. |
| [Find-RiskyApplication](commands/Find-RiskyApplication.md) | Checks tenant service principals against threat intelligence feeds for known malicious OAuth apps. |
| [Show-UserMFA](commands/Show-UserMFA.md) | Lists all registered authentication methods for the user. |
| [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (user, 90 days) | Retrieves and exports Exchange Online message trace records for the user over 90 days. |
| [Get-IRTInboxRule](commands/Get-IRTInboxRule.md) | Fetches and exports all inbox rules for the user. |
| [Get-EntraAuditLog](commands/Get-EntraAuditLog.md) | Queries and exports Entra ID directory audit log activity for the user. |
| [Get-SignInLog](commands/Get-SignInLog.md) | Retrieves and exports interactive Entra ID sign-in logs enriched with geolocation and error descriptions. |
| [Get-UALog](commands/Get-UALog.md) (all records) | Queries and exports all Unified Audit Log records for the user across multiple operation categories. |
| [Get-UALog](commands/Get-UALog.md) (risky operations, 180 days) | Queries UAL for a curated set of high-risk operations over the past 180 days. |
| [Get-UALog](commands/Get-UALog.md) (sign-in logs via UAL) | Retrieves sign-in events from the Unified Audit Log. |
| [Get-NonInteractiveLog](commands/Get-NonInteractiveLog.md) | Retrieves non-interactive sign-in logs including token refreshes and service-to-service calls. |
| [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (all users, 2 days) | Retrieves message trace records for all tenant users over the past 2 days. |

## Other Investigation Commands

| Command | Description |
|---------|-------------|
| [Show-TenantServicePrincipal](commands/Show-TenantServicePrincipal.md) | Lists all service principals (enterprise apps) in the tenant with optional filtering and export. |
| [Get-IRTTenantInfo](commands/Get-IRTTenantInfo.md) | Looks up an Entra ID tenant by GUID and returns its display name and default domain. |
| [Get-UserMailboxPermission](commands/Get-UserMailboxPermission.md) | Lists all mailboxes in the tenant that the specified users have access to. |
| [Show-MailboxAccess](commands/Show-MailboxAccess.md) | Displays all users with access permissions to the target user's mailbox. |
| [Show-DeviceInfo](commands/Show-DeviceInfo.md) | Displays Entra ID and Intune device properties for devices found via Find-Device. |
| [Find-GraphDirectoryObject](commands/Find-GraphDirectoryObject.md) | Extracts GUIDs from text or clipboard and resolves them to their Graph directory objects. |

**Remediation:**  
[Remediation](remediation.md)