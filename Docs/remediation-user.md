# M365 Remediation

These commands run against Entra ID, Intune, and Exchange Online via Microsoft Graph and
Exchange Online PowerShell. Run [Connect-IRT](M365IncidentResponseTools/Connect-IRT.md)
first. For hybrid environments, see [On-Premises AD Remediation](remediation-ad.md).

## Finding a User

Before running remediation commands, select a target user with `Find-IRTUser`. The search
is matched against DisplayName, UserPrincipalName, the user object id, ProxyAddresses, and
OnPremisesSamAccountName.

```powershell
# search by name fragment
Find-IRTUser flast

# search by email address
Find-User flast@contoso.com

# select multiple users with multiple search strings
finduser flast, jsmith

# read one search query per line from the clipboard
finduser -FromClipboard

# return objects directly for use in scripts, without setting globals
$Users = Find-IRTUser -Search 'flast' -AllMatches -Script
```

Matching users are stored in `$Global:IRT_UserObjects` and subsequent commands use them
automatically. A search that matches more than one user is reported but selects nothing
unless `-AllMatches` is used.

## Revoking Sessions

```powershell
# revoke all active sessions for the selected user(s)
Revoke-IRTUserSession

# revoke sessions for a specific user object
RevokeSessions -UserObject $User
```

Revokes all refresh tokens, forcing re-authentication. Note: MFA sessions cannot be revoked
through Graph APIs; that must be done in the Entra web portal.

## Disabling a User

```powershell
# disable the user(s) selected with Find-IRTUser
Disable-IRTUser

# disable a specific user object
DisableUser -UserObject $User
```

Blocks all cloud sign-ins. Use [Enable-IRTUser](M365IncidentResponseTools/Enable-IRTUser.md)
(alias `EnableUser`) to reverse.

## Resetting a Password

Exactly one password mode must be specified: `-RandomCharacters`, `-Custom`,
`-ForceChangePasswordNextSignIn`, or `-ClearForceChangePasswordNextSignIn`.

```powershell
# generate and set a random 30-character password for the selected user
Reset-IRTUserPassword -RandomCharacters

# random password with custom length
ResetPassword -RandomCharacters -Length 48

# prompt operator to enter a password interactively
ResetPassword -Custom

# don't change the password; force a new password (with MFA) at next sign-in
ResetPassword -ForceChangePasswordNextSignIn

# undo a previous force-change flag
ResetPassword -ClearForceChangePasswordNextSignIn

# target a specific user object, preview with -WhatIf
Reset-IRTUserPassword -UserObject $User -RandomCharacters -WhatIf
```

With `-RandomCharacters`, the new password is printed to the console via
`[Console]::WriteLine` so it is not captured in PowerShell transcripts. If the user is
synced from on-premises AD, a warning reminds the operator to also reset the password in
local AD (see [Reset-IRTAdUserPassword](M365IncidentResponseTools/Reset-IRTAdUserPassword.md)).

## Disabling or Removing a Device

See [Devices](devices.md) for finding devices and disabling or removing devices the
attacker registered.

## Mailbox Access

Grant yourself full access to the target user's mailbox to review contents during an
investigation, then remove the grant when finished.

```powershell
# grant the currently connected account full access to the selected user's mailbox
Add-IRTMailboxFullAccess

# grant access to a different account
FullAccess -GrantAccessTo 'analyst@contoso.com'

# open the selected user's mailbox in Outlook on the Web
Open-IRTMailboxInOwa

# copy the OWA URL to the clipboard instead of opening a browser
OpenMailbox -ToClipboard

# remove the full access grant when done
Remove-IRTMailboxFullAccess
```

## Commands

| Command | Description |
|---------|-------------|
| [Find-IRTUser](M365IncidentResponseTools/Find-IRTUser.md) | Searches Entra ID users by display name, UPN, email, object id, or on-prem SAM account name. |
| [Revoke-IRTUserSession](M365IncidentResponseTools/Revoke-IRTUserSession.md) | Revokes all active sessions for the user. |
| [Disable-IRTUser](M365IncidentResponseTools/Disable-IRTUser.md) | Disables a user's Entra ID account, blocking all cloud sign-ins. |
| [Enable-IRTUser](M365IncidentResponseTools/Enable-IRTUser.md) | Re-enables a previously disabled Entra ID user account. |
| [Reset-IRTUserPassword](M365IncidentResponseTools/Reset-IRTUserPassword.md) | Resets a user's Entra ID password using a randomly generated or custom password. |
| [Add-IRTMailboxFullAccess](M365IncidentResponseTools/Add-IRTMailboxFullAccess.md) | Grants the currently logged-in user full access to the target user's mailbox. |
| [Remove-IRTMailboxFullAccess](M365IncidentResponseTools/Remove-IRTMailboxFullAccess.md) | Removes full access permissions to a target user's mailbox. |
| [Open-IRTMailboxInOwa](M365IncidentResponseTools/Open-IRTMailboxInOwa.md) | Opens a user's mailbox in Outlook on the Web in a browser. |
