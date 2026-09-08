# User Investigation

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
| [Get-IRTLicenseReport](M365IncidentResponseTools/Get-IRTLicenseReport.md) | Displays tenant license consumption across all subscribed SKUs. |
| [Show-IRTUser](M365IncidentResponseTools/Show-IRTUser.md) | Displays all user properties as a formatted tree. |
| [Get-IRTUserServicePrincipal](M365IncidentResponseTools/Get-IRTUserServicePrincipal.md) | Lists OAuth2 applications the user has personally consented to. |
| [Show-IRTMailbox](M365IncidentResponseTools/Show-IRTMailbox.md) | Displays Exchange Online mailbox configuration including quotas, forwarding, hold status, and permissions. |
| [Get-IRTAdminRole](M365IncidentResponseTools/Get-IRTAdminRole.md) | Lists all Entra ID directory roles and their effective members, expanding nested groups inline. |
| [Find-IRTRiskyServicePrincipal](M365IncidentResponseTools/Find-IRTRiskyServicePrincipal.md) | Checks tenant service principals against threat intelligence feeds for known malicious OAuth apps. |
| [Show-IRTUserMfa](M365IncidentResponseTools/Show-IRTUserMfa.md) | Lists all registered authentication methods for the user. |
| [Get-IRTMessageTrace](M365IncidentResponseTools/Get-IRTMessageTrace.md) (user, 90 days) | Retrieves and exports Exchange Online message trace records for the user over 90 days. |
| [Get-IRTInboxRule](M365IncidentResponseTools/Get-IRTInboxRule.md) | Fetches and exports all inbox rules for the user. |
| [Get-IRTEntraAuditLog](M365IncidentResponseTools/Get-IRTEntraAuditLog.md) | Queries and exports Entra ID directory audit log activity for the user. |
| [Get-IRTEntraSignInLog](M365IncidentResponseTools/Get-IRTEntraSignInLog.md) | Retrieves and exports interactive Entra ID sign-in logs enriched with geolocation and error descriptions. |
| [Get-IRTUnifiedAuditLog](M365IncidentResponseTools/Get-IRTUnifiedAuditLog.md) (all records) | Queries and exports all Unified Audit Log records for the user. (1 day) |
| [Get-IRTUnifiedAuditLog](M365IncidentResponseTools/Get-IRTUnifiedAuditLog.md) (risky operations) | Queries UAL for a curated set of high-risk operations. (180 days) |
| [Get-IRTUnifiedAuditLog](M365IncidentResponseTools/Get-IRTUnifiedAuditLog.md) (UAL sign-in logs) | Retrieves sign-in events from the Unified Audit Log. (180 days) |
| [Get-IRTNonInteractiveSignIn](M365IncidentResponseTools/Get-IRTNonInteractiveSignIn.md) | Retrieves non-interactive sign-in logs including token refreshes and service-to-service calls. (30 days) |
| [Get-IRTMessageTrace](M365IncidentResponseTools/Get-IRTMessageTrace.md) (all users) | Retrieves message trace records for all tenant users. (10 days) |

## Running Commands Individually

All playbook commands can also be run on their own. Like the playbook, they read the
selected user from `$Global:IRT_UserObjects` unless `-UserObject` is passed.

### Sign-In Logs

```powershell
# last 30 days of interactive sign-in logs for the selected user
Get-IRTEntraSignInLog

# 7 days for a specific user
Get-IRTEntraSignInLog -UserObject $User -Days 7

# all sign-ins from a specific IP over the last 14 days
Get-IRTEntraSignInLog -IpAddress '203.0.113.5' -Days 14

# non-interactive sign-ins for a specific time range.
Get-IRTEntraSignInLog -NonInteractive -Start '2026-04-01' -End '2026-04-3'
```

Results are exported to an Excel workbook.

### Message Trace

```powershell
# last 10 days of incoming and outgoing mail for the selected user
Get-IRTMessageTrace

# 30 days for a specific user
Get-IRTMessageTrace -UserObject $User -Days 30

# all tenant mail for an absolute date range
Get-IRTMessageTrace -AllUsers -Start '2026-04-01' -End '2026-04-30'
```

### MFA Methods

```powershell
# all registered authentication methods for the selected user
Show-IRTUserMfa

# for a specific user
Show-IRTUserMfa -UserObject $User
```

Review for methods registered by the attacker, such as new authenticator apps or
phone numbers added around the time of compromise.

### Entra Devices

See [Devices](devices.md) for finding, displaying, and remediating Entra and Intune
devices.

### Unified Audit Log

```powershell
# all UAL records for the selected user (defaults to 1 day)
Get-IRTUnifiedAuditLog

# 90 days for a specific user
Get-IRTUnifiedAuditLog -UserObject $User -Days 90

# only a predefined list of high-risk operations
Get-IRTUnifiedAuditLog -RiskyOperation -Days 180

# only sign-in operations
Get-IRTUnifiedAuditLog -SignInLog -Days 180

# specific operations across all users in a date range
Get-IRTUnifiedAuditLog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'

# only specific record types
Get-IRTUnifiedAuditLog -RecordType 'ExchangeItem', 'AzureActiveDirectoryStsLogon'
```

## Other Investigation Commands

| Command | Description |
|---------|-------------|
| [Show-IRTMailboxAccess](M365IncidentResponseTools/Show-IRTMailboxAccess.md) | Displays all users with access permissions to the target user's mailbox. |
| [Find-IRTDirectoryObject](M365IncidentResponseTools/Find-IRTDirectoryObject.md) | Extracts GUIDs from text or clipboard and resolves them to their Graph directory objects. |
| [New-IRTEmailSearch](M365IncidentResponseTools/New-IRTEmailSearch.md) | Builds and launches a compliance content search for email activity. |
| [Get-IRTEmailSearch](M365IncidentResponseTools/Get-IRTEmailSearch.md) | Interactive manager for existing email searches: start, wait, view results, purge matched email, or delete the search. |

**Investigating service principals:**
[Service Principal Investigation](investigation-sp.md)

**Devices:**
[Devices](devices.md)

**Remediation:**
[Remediation](remediation-user.md)
