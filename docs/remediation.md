# Remediation

## M365 Remediation Commands

| Command | Description |
|---------|-------------|
| [Revoke-IRTUserSession](commands/Revoke-IRTUserSession.md) | Revokes all active sessions for the user. |
| [Disable-IRTUser](commands/Disable-IRTUser.md) | Disables a user's Entra ID account, blocking all cloud sign-ins. |
| [Enable-IRTUser](commands/Enable-IRTUser.md) | Re-enables a previously disabled Entra ID user account. |
| [Reset-IRTUserPassword](commands/Reset-IRTUserPassword.md) | Resets a user's Entra ID password using a randomly generated or custom password. |
| [Disable-IRTDevice](commands/Disable-IRTDevice.md) | Disables an Entra ID / Intune device, preventing it from authenticating. |
| [Remove-IRTDevice](commands/Remove-IRTDevice.md) | Deletes a device record from Entra ID / Intune. |
| [Add-IRTMailboxFullAccess](commands/Add-IRTMailboxFullAccess.md) | Grants the currently logged-in user full access to the target user's mailbox. |
| [Remove-IRTMailboxFullAccess](commands/Remove-IRTMailboxFullAccess.md) | Removes full access permissions to a target user's mailbox. |
| [Open-IRTMailboxInOwa](commands/Open-IRTMailboxInOwa.md) | Opens a user's mailbox in Outlook on the Web in a browser. |

## On-Premises AD Commands

| Command | Description |
|---------|-------------|
| [Find-IRTAdUser](commands/Find-IRTAdUser.md) | Searches on-premises AD users by display name, UPN, email, SAM account name, or GUID. |
| [Show-IRTAdUser](commands/Show-IRTAdUser.md) | Displays comprehensive on-premises AD user attributes including password metadata and group memberships. |
| [Disable-IRTAdUser](commands/Disable-IRTAdUser.md) | Disables one or more AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Enable-IRTAdUser](commands/Enable-IRTAdUser.md) | Re-enables one or more disabled AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Reset-IRTAdUserPassword](commands/Reset-IRTAdUserPassword.md) | Resets one or more on-premises AD user passwords using a randomly generated, custom, or forced-change-at-next-sign-in approach. |
| [Push-IRTAdSync](commands/Push-IRTAdSync.md) | Forces an Active Directory to Entra ID delta sync cycle, automatically discovering the sync server if needed. |
| [Find-IRTAdDevice](commands/Find-IRTAdDevice.md) | Finds an on-premises AD computer by Name, DNSHostName, SamAccountName, Description, or ObjectGUID. |
| [Show-IRTAdDevice](commands/Show-IRTAdDevice.md) | Displays all on-premises AD computer properties for the device in `$Global:IRT_DeviceObject`. |
| [Find-IRTAdOu](commands/Find-IRTAdOu.md) | Searches Active Directory Organizational Units by name, CanonicalName, or DistinguishedName. |
| [Show-IRTAdOus](commands/Show-IRTAdOus.md) | Lists all OUs in the domain sorted by CanonicalName with user and computer counts. |
| [Find-IRTDomainController](commands/Find-IRTDomainController.md) | Returns the names of all domain controllers in the current AD domain. |
| [Get-IRTAdAdminUser](commands/Get-IRTAdAdminUser.md) | Retrieves all on-premises AD users with AdminCount=1 (accounts that have been members of privileged groups). |

## Running AD Commands on Remote Devices

To run them from a remote device that does not have the IRT module installed,
use [Copy-IRTFunction](commands/Copy-IRTFunction.md) to copy the relevant functions to the clipboard,
then paste and execute them in a remote session.

```powershell
# Copy the default set (core helpers + all on-prem AD functions) to clipboard
Copy-IRTFunction

# Include additional functions beyond the default set
Copy-IRTFunction -FunctionName 'Get-IRTMessageTrace'

# Pipeline form
Copy-IRTFunction
```

`Copy-IRTFunction` retrieves function definitions from any module imported in memory and concatenates
them into a single pasteable script, then sends the result to the clipboard.
