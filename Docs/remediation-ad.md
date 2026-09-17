# On-Premises AD Remediation

For hybrid environments, these commands run against on-premises Active Directory using the
ActiveDirectory RSAT module. Disable/enable/reset commands automatically trigger AD replication
and an Entra ID delta sync when the relevant services are reachable.

## Running AD Commands on Remote Devices

To run them from a remote device that does not have the IRT module installed,
use [Copy-IRTFunction](M365IncidentResponseTools/Copy-IRTFunction.md) to copy the relevant functions to the clipboard,
then paste and execute them in a remote session.

```powershell
# Copy the default set (core helpers + all on-prem AD functions) to clipboard
Copy-IRTFunction

# Include additional functions beyond the default set
Copy-IRTFunction -FunctionName 'Get-IRTMessageTrace'
```

`Copy-IRTFunction` retrieves function definitions from any module imported in memory and concatenates
them into a single pasteable script, then sends the result to the clipboard.


## Finding a User

Before running remediation commands, select a target user with `Find-IRTAdUser`. The search
is matched against DisplayName, Name, UserPrincipalName, ProxyAddresses, SamAccountName,
and ObjectGUID.

```powershell
# search by name fragment
Find-IRTAdUser flast

# search by email address
Find-AdUser flast@contoso.com

# select multiple users with multiple search strings
findaduser flast, jsmith

# read one search query per line from the clipboard
finduser -FromClipboard

# return objects directly for use in scripts, without setting globals
$Users = Find-IRTAdUser -Search 'flast','jsmith' -Script
```

If exactly one user matches, the full AD object is stored in `$Global:IRT_UserObject` and
subsequent commands use it automatically. If a search string matches multiple users, the
results are displayed but nothing is selected.

## Disabling a User

```powershell
# disable the user(s) selected with Find-IRTAdUser
Disable-IRTAdUser

# disable a specific user object
disableuser -UserObject $AdUser
```

After disabling, the account is re-fetched to confirm the change, then AD replication and an
Entra ID delta sync are triggered if the relevant services are available. Use
[Enable-IRTAdUser](M365IncidentResponseTools/Enable-IRTAdUser.md) to reverse.

## Resetting a Password

Exactly one password mode must be specified: `-RandomCharacters`, `-Custom`, or
`-ForceChangePasswordNextSignIn`.

```powershell
# generate and set a random 30-character password for the selected user
Reset-IRTAdUserPassword -RandomCharacters

# random password with custom length
Reset-AdUserPassword -RandomCharacters -Length 48

# prompt operator to enter a password interactively
ResetPassword -Custom

# don't change the password; force the user to set a new one at next sign-in
resetpassword -ForceChangePasswordNextSignIn

# target a specific user object, preview with -WhatIf
Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters -WhatIf
```

With `-RandomCharacters`, the new password is printed to the console via
`[Console]::WriteLine` so it is not captured in PowerShell transcripts.

## Pushing an AD Sync

`Push-IRTAdSync` triggers an AD-to-Entra delta sync as quickly as possible. If running on a
domain controller, it forces intra-AD replication first (`repadmin /syncall /AdeP`). If the
ADSync service is local, the sync runs immediately; otherwise candidate servers are discovered
in parallel and the sync is invoked remotely on the first server running the service.

Domain admin credentials are cached for the session; use `-ResetCredentials` to re-prompt.

```powershell
# discover the sync server automatically and trigger a delta sync
Push-IRTAdSync

# target a known sync server directly, skipping discovery
Push-AdSync -SyncServer 'sync01.contoso.com'

# clear cached domain admin credentials and re-prompt
adsync -ResetCredentials
```

## Commands

| Command | Description |
|---------|-------------|
| [Find-IRTAdUser](M365IncidentResponseTools/Find-IRTAdUser.md) | Searches on-premises AD users by display name, UPN, email, SAM account name, or GUID. |
| [Show-IRTAdUser](M365IncidentResponseTools/Show-IRTAdUser.md) | Displays comprehensive on-premises AD user attributes including password metadata and group memberships. |
| [Disable-IRTAdUser](M365IncidentResponseTools/Disable-IRTAdUser.md) | Disables one or more AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Enable-IRTAdUser](M365IncidentResponseTools/Enable-IRTAdUser.md) | Re-enables one or more disabled AD user accounts and triggers AD replication and Entra ID delta sync. |
| [Reset-IRTAdUserPassword](M365IncidentResponseTools/Reset-IRTAdUserPassword.md) | Resets one or more on-premises AD user passwords using a randomly generated, custom, or forced-change-at-next-sign-in approach. |
| [Push-IRTAdSync](M365IncidentResponseTools/Push-IRTAdSync.md) | Forces an Active Directory to Entra ID delta sync cycle, automatically discovering the sync server if needed. |
| [Find-IRTAdDevice](M365IncidentResponseTools/Find-IRTAdDevice.md) | Finds an on-premises AD computer by Name, DNSHostName, SamAccountName, Description, or ObjectGUID. |
| [Show-IRTAdDevice](M365IncidentResponseTools/Show-IRTAdDevice.md) | Displays all on-premises AD computer properties for the device in `$Global:IRT_DeviceObject`. |
| [Find-IRTAdOu](M365IncidentResponseTools/Find-IRTAdOu.md) | Searches Active Directory Organizational Units by name, CanonicalName, or DistinguishedName. |
| [Show-IRTAdOus](M365IncidentResponseTools/Show-IRTAdOus.md) | Lists all OUs in the domain sorted by CanonicalName with user and computer counts. |
| [Find-IRTDomainController](M365IncidentResponseTools/Find-IRTDomainController.md) | Returns the names of all domain controllers in the current AD domain. |
| [Get-IRTAdAdminUser](M365IncidentResponseTools/Get-IRTAdAdminUser.md) | Retrieves all on-premises AD users with AdminCount=1 (accounts that have been members of privileged groups). |
