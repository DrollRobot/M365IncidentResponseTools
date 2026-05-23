# Remediation

## M365 Remediation Commands

| Command | Description |
|---------|-------------|
| [Revoke-UserSession](commands/Revoke-UserSession.md) | Revokes all active sessions for the user. |
| [Disable-GraphUser](commands/Disable-GraphUser.md) | Disables a user's Entra ID account, blocking all cloud sign-ins. |
| [Enable-GraphUser](commands/Enable-GraphUser.md) | Re-enables a previously disabled Entra ID user account. |
| [Reset-IRTUserPassword](commands/Reset-IRTUserPassword.md) | Resets a user's Entra ID password using a randomly generated or custom password. |
| [Set-UsageLocation](commands/Set-UsageLocation.md) | Sets a user's usage location (ISO 3166 country code), required before assigning M365 licenses. |
| [Grant-MailboxFullAccess](commands/Grant-MailboxFullAccess.md) | Grants the currently logged-in user full access to the target user's mailbox. |
| [Remove-MailboxFullAccess](commands/Remove-MailboxFullAccess.md) | Removes full access permissions to a target user's mailbox. |
| [Open-MailboxInOWA](commands/Open-MailboxInOWA.md) | Opens a user's mailbox in Outlook on the Web in a browser. |

## On-Premises AD Commands

| Command | Description |
|---------|-------------|
| [Find-AdUser](commands/Find-AdUser.md) | Searches on-premises AD users by display name, UPN, email, SAM account name, or GUID. |
| [Show-AdUserInfo](commands/Show-AdUserInfo.md) | Displays comprehensive on-premises AD user attributes including password metadata and group memberships. |
| [Disable-AdUser](commands/Disable-AdUser.md) | Disables one or more AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Enable-AdUser](commands/Enable-AdUser.md) | Re-enables one or more disabled AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Reset-IRTAdUserPassword](commands/Reset-IRTAdUserPassword.md) | Resets one or more on-premises AD user passwords using a randomly generated, custom, or forced-change-at-next-sign-in approach. |
| [Push-AdSync](commands/Push-AdSync.md) | Forces an Active Directory to Entra ID delta sync cycle, automatically discovering the sync server if needed. |
| [Find-AdOu](commands/Find-AdOu.md) | Searches Active Directory Organizational Units by name, CanonicalName, or DistinguishedName. |
| [Show-AdOus](commands/Show-AdOus.md) | Lists all OUs in the domain sorted by CanonicalName with user and computer counts. |
| [Find-AllDomainController](commands/Find-AllDomainController.md) | Returns the names of all domain controllers in the current AD domain. |
| [Get-AdAdminUser](commands/Get-AdAdminUser.md) | Retrieves all on-premises AD users with AdminCount=1 (accounts that have been members of privileged groups). |

## Running On-Premises Commands on Remote Devices

To run them from a remote device that does not have the IRT module installed,
use [Copy-IRTFunction](commands/Copy-IRTFunction.md) to copy the relevant functions to the clipboard,
then paste and execute them in a remote session.

```powershell
# Copy all onprem_ad functions to clipboard (hardcoded default)
Copy-IRTFunction

# Copy onprem_ad functions plus additional folders
Copy-IRTFunction -Path .\sign

# Paste the clipboard contents into a remote PSSession or RDP window
```

`Copy-IRTFunction` reads every `.ps1` file in the `onprem_ad/` folder (always included) and any
additional paths supplied via `-Path`, concatenates them into a single block with file headers, and
sends the result to the clipboard. Use `-Recurse` to walk subdirectories for extra paths.
