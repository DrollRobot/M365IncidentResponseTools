# Investigation

Before running investigation commands, select a target user. (or multiple users. all commands will apply to all selected users)

```powershell
Find-IRTUser -Search joseph.smith
```
`Find-IRTUser` uses regex matching against DisplayName, Id, OnPremisisSamAccountName, and all Mail/Proxy addresses. If a search query matches multiple users, none will be selected and a warning will be shown.

Multiple users can be selected if multiple search queries are passed.
```
Find-IRTUser joseph, sarah, mary
```

If a search returns only one user, the user object will be saved in `$Global:IRT_UserObjects`, which most commands read from automatically when no `-UserObject` parameter is provided. (-UserObject expects a Graph user object)

## Running the Investigation Playbook

The investigation playbook runs ~15 commands in parallel to return results quickly. By default, it will create a new folder, move into the folder, and save all files there.

```powershell
# run all playbook commands for the users in the global variable
Start-IRTPlaybook

# run playbook for specific user with ticket number in folder name
Start-IRTPlaybook -UserObject $User -Ticket 'INC-1234'

# limit parallelism on slower devices
Start-IRTPlaybook -MaxRunspaces 5
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
| [Get-IRTLicenseReport](commands/Get-IRTLicenseReport.md) | Displays tenant license consumption across all subscribed SKUs. |
| [Show-IRTUser](commands/Show-IRTUser.md) | Displays all user properties as a formatted tree. |
| [Get-IRTUserServicePrincipal](commands/Get-IRTUserServicePrincipal.md) | Lists OAuth2 applications the user has personally consented to. |
| [Show-IRTMailbox](commands/Show-IRTMailbox.md) | Displays Exchange Online mailbox configuration including quotas, forwarding, hold status, and permissions. |
| [Get-IRTAdminRole](commands/Get-IRTAdminRole.md) | Lists all Entra ID directory roles and their effective members, expanding nested groups inline. |
| [Find-IRTRiskyServicePrincipal](commands/Find-IRTRiskyServicePrincipal.md) | Checks tenant service principals against threat intelligence feeds for known malicious OAuth apps. |
| [Show-IRTUserMfa](commands/Show-IRTUserMfa.md) | Lists all registered authentication methods for the user. |
| [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (user, 90 days) | Retrieves and exports Exchange Online message trace records for the user over 90 days. |
| [Get-IRTInboxRule](commands/Get-IRTInboxRule.md) | Fetches and exports all inbox rules for the user. |
| [Get-IRTEntraAuditLog](commands/Get-IRTEntraAuditLog.md) | Queries and exports Entra ID directory audit log activity for the user. |
| [Get-IRTEntraSignInLog](commands/Get-IRTEntraSignInLog.md) | Retrieves and exports interactive Entra ID sign-in logs enriched with geolocation and error descriptions. |
| [Get-IRTUnifiedAuditLog](commands/Get-IRTUnifiedAuditLog.md) (all records) | Queries and exports all Unified Audit Log records for the user. (1 day) |
| [Get-IRTUnifiedAuditLog](commands/Get-IRTUnifiedAuditLog.md) (risky operations) | Queries UAL for a curated set of high-risk operations. (180 days) |
| [Get-IRTUnifiedAuditLog](commands/Get-IRTUnifiedAuditLog.md) (UAL sign-in logs) | Retrieves sign-in events from the Unified Audit Log. (180 days) |
| [Get-IRTNonInteractiveSignIn](commands/Get-IRTNonInteractiveSignIn.md) | Retrieves non-interactive sign-in logs including token refreshes and service-to-service calls. (30 days) |
| [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (all users) | Retrieves message trace records for all tenant users. (10 days) |

## Other Investigation Commands

| Command | Description |
|---------|-------------|
| [Find-IRTServicePrincipal](commands/Find-IRTServicePrincipal.md) | Searches tenant service principals by name, app ID, or object ID. |
| [Show-IRTServicePrincipal](commands/Show-IRTServicePrincipal.md) | Lists all service principals (enterprise apps) in the tenant with optional filtering and export. |
| [Find-IRTDevice](commands/Find-IRTDevice.md) | Searches Entra ID and Intune devices by name, user, or device ID. |
| [Show-IRTDevice](commands/Show-IRTDevice.md) | Displays Entra ID and Intune device properties for devices found via Find-IRTDevice. |
| [Get-IRTTenantOwner](commands/Get-IRTTenantOwner.md) | Looks up an Entra ID tenant by domain or GUID and returns its display name, domain, tenant ID, and cloud. |
| [Show-IRTMailboxAccess](commands/Show-IRTMailboxAccess.md) | Displays all users with access permissions to the target user's mailbox. |
| [Find-IRTDirectoryObject](commands/Find-IRTDirectoryObject.md) | Extracts GUIDs from text or clipboard and resolves them to their Graph directory objects. |
| [New-IRTEmailSearch](commands/New-IRTEmailSearch.md) | Builds and launches a compliance content search for email activity. |

**Remediation:**
[Remediation](remediation.md)