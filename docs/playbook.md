# Incident Response Playbook

`Start-IncidentResponsePlaybook` is the primary investigation entry point. It accepts one or
more Entra ID user objects and runs up to 15 data-collection steps in parallel using a runspace
pool. Each step writes its output to a timestamped investigation folder.

## Syntax

```powershell
Start-IncidentResponsePlaybook [[-UserObject] <psobject[]>] [-Ticket <string>]
    [-NoFolder] [-MaxRunspaces <int>] [-Test]
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-UserObject` | `psobject[]` | One or more Entra ID user objects. Falls back to `$Global:IRT_UserObjects` if omitted. |
| `-Ticket` | `string` | Ticket or case number. Used to name the investigation folder. |
| `-NoFolder` | switch | Skip creating an investigation folder. Output goes to the current directory. |
| `-MaxRunspaces` | `int` | Maximum parallel runspaces (default: 15). |
| `-Test` | switch | Enables stopwatch timing output for benchmarking. |

## Before Running

Load the target user into the session and connect to the required services:

```powershell
# 1. Connect to Graph and Exchange Online
Connect-IRT

# 2. Resolve the user
Get-IRTUserObject -UserPrincipalName user@contoso.com

# 3. Run the playbook
Start-IncidentResponsePlaybook -Ticket 'INC-1234'
```

## Playbook Steps

The following steps run in parallel. Steps marked **Requires Exchange** need an active
Exchange Online connection -- the playbook connects Exchange in a separate runspace for
those steps automatically.

| Step | Command | Requires Exchange | Output |
|------|---------|-------------------|--------|
| 1 | [Get-LicenseReport](commands/Get-LicenseReport.md) | | `LicenseReport.xlsx` |
| 2 | [Show-UserInfo](commands/Show-UserInfo.md) | | `UserInfo.xlsx` |
| 3 | [Get-UserApplication](commands/Get-UserApplication.md) | | `UserApplications.xlsx` |
| 4 | [Show-Mailbox](commands/Show-Mailbox.md) | | `Mailbox.xlsx` |
| 5 | [Get-AdminRole](commands/Get-AdminRole.md) | | `AdminRoles.xlsx` |
| 6 | [Find-RiskyApplication](commands/Find-RiskyApplication.md) | | `RiskyApplications.xlsx` |
| 7 | [Show-UserMFA](commands/Show-UserMFA.md) | | `UserMFA.xlsx` |
| 8 | [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (user, 90 days) | Yes | `MessageTrace.xlsx` |
| 9 | [Get-IRTInboxRule](commands/Get-IRTInboxRule.md) | Yes | `InboxRules.xlsx` |
| 10 | [Get-EntraAuditLog](commands/Get-EntraAuditLog.md) | | `EntraAuditLog.xlsx` |
| 11 | [Get-SignInLog](commands/Get-SignInLog.md) | | `SignInLogs.xlsx` |
| 12 | [Get-UALog](commands/Get-UALog.md) (all records) | Yes | `UALog.xlsx` |
| 13 | [Get-UALog](commands/Get-UALog.md) (risky operations, 180 days) | Yes | `UALog_RiskyOps.xlsx` |
| 14 | [Get-UALog](commands/Get-UALog.md) (sign-in logs via UAL) | Yes | `UALog_SignIn.xlsx` |
| 15 | [Get-NonInteractiveLog](commands/Get-NonInteractiveLog.md) | | `NonInteractiveLogs.xlsx` |
| 16 | [Get-IRTMessageTrace](commands/Get-IRTMessageTrace.md) (all users, 2 days) | Yes | `MessageTrace_AllUsers.xlsx` |

## Investigation Folder

Unless `-NoFolder` is specified, the playbook creates a folder named after the ticket number
and timestamp under your configured output path:

```
C:\Investigations\
  INC-1234_2026-05-03_1430\
    LicenseReport.xlsx
    UserInfo.xlsx
    Mailbox.xlsx
    ...
```

Use `Compress-InvestigationFolder` to zip the folder for handoff or archival.

## Examples

```powershell
# Minimal -- uses global user objects, no folder
Start-IncidentResponsePlaybook

# Full investigation with ticket number
Start-IncidentResponsePlaybook -UserObject $User -Ticket 'INC-1234'

# Limit parallelism on a slower machine
Start-IncidentResponsePlaybook -MaxRunspaces 5
```
