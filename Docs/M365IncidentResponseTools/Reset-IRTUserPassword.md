---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Reset-IRTUserPassword
---

# Reset-IRTUserPassword

## SYNOPSIS

Resets an Entra ID user's password.

## SYNTAX

### RandomCharacters

```
Reset-IRTUserPassword [[-UserObject] <psobject[]>] [-RandomCharacters] [-Length <int>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### Custom

```
Reset-IRTUserPassword [[-UserObject] <psobject[]>] [-Custom] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### ForceChangePasswordNextSignIn

```
Reset-IRTUserPassword [[-UserObject] <psobject[]>] [-ForceChangePasswordNextSignIn] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### ClearForceChangePasswordNextSignIn

```
Reset-IRTUserPassword [[-UserObject] <psobject[]>] [-ClearForceChangePasswordNextSignIn] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

ResetPassword, ResetPasswords

## DESCRIPTION

Resets the password for one or more Entra ID users via the Microsoft Graph API.
Exactly
one of the three password mode switches must be specified:

  -RandomCharacters     Generates a random 30-character password and sets it immediately.
                        The new password is printed to the console via [Console]::WriteLine
                        so it is NOT captured in PowerShell transcripts.

  -Custom               Prompts the operator to enter a password interactively via
                        Read-Host.
The password is set immediately with no forced
                        change on next sign-in.

  -ForceChangePasswordNextSignIn
                        Does not set a new password.
Instead, sets
                        ForceChangePasswordNextSignInWithMfa = $true on the account,
                        which forces the user to choose a new password (with MFA
                        verification) on their next login.

  -ClearForceChangePasswordNextSignIn
                        Clears the force-change flag.
Sets both
                        ForceChangePasswordNextSignIn and
                        ForceChangePasswordNextSignInWithMfa to $false without
                        changing the current password.

If no -UserObject is supplied, the function falls back to the global session objects
stored in $Global:IRT_UserObjects (populated by Get-GlobalUserObject).
An error is thrown
if neither source yields a user.

After the reset, updated account properties are retrieved and displayed as a table.
If the user is synced from on-premises Active Directory, a warning is shown reminding
the operator to also reset the password in the local AD.

Supports -WhatIf and -Confirm via SupportsShouldProcess.

## EXAMPLES

### EXAMPLE 1

Reset-IRTUserPassword -RandomCharacters
Resets the password for the user stored in the global session using a random password.
The new password is printed to the console.

### EXAMPLE 2

Reset-IRTUserPassword -UserObject $User -RandomCharacters
Resets the password for a specific user object using a random password.

### EXAMPLE 3

Reset-IRTUserPassword -Custom
Prompts the operator to enter a custom password, then applies it to the global session user.

### EXAMPLE 4

Reset-IRTUserPassword -UserObject $User -ForceChangePasswordNextSignIn
Forces the user to set a new password (with MFA) on their next sign-in, without
changing the current password.

### EXAMPLE 5

Reset-IRTUserPassword -RandomCharacters -Length 48
Resets the password using a random 48-character password.

### EXAMPLE 6

Reset-IRTUserPassword -UserObject $User -RandomCharacters -WhatIf
Shows what would happen without actually resetting the password.

### EXAMPLE 7

Reset-IRTUserPassword -UserObject $User -ClearForceChangePasswordNextSignIn
Clears the forced-change flag on the user's account.

## PARAMETERS

### -ClearForceChangePasswordNextSignIn

Clears the forced-change-on-next-sign-in flag.
Sets both ForceChangePasswordNextSignIn
and ForceChangePasswordNextSignInWithMfa to $false without changing the current password.
Use this to undo a previous -ForceChangePasswordNextSignIn call.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- UndoForceChangePasswordNextSignIn
ParameterSets:
- Name: ClearForceChangePasswordNextSignIn
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Custom

Prompts the operator to enter a custom password via Read-Host.
The password is applied
immediately with ForceChangePasswordNextSignIn set to $false.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Custom
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ForceChangePasswordNextSignIn

Sets ForceChangePasswordNextSignInWithMfa = $true on the account without changing the
current password.
The user will be required to set a new password (verified with MFA)
on their next sign-in.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ForceChangePasswordNextSignIn
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Length

The length of the randomly generated password.
Only valid with -RandomCharacters.
Must be at least 4 characters.
Defaults to 30.

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RandomCharacters
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RandomCharacters

Generates a random password of the specified length (default: 30 characters) and
applies it to the account.
The password is written directly to the console (bypassing
transcript logging) so it can be recorded securely by the operator.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- Random
ParameterSets:
- Name: RandomCharacters
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UserObject

One or more Entra ID user objects whose passwords will be reset.
Falls back to
$Global:IRT_UserObjects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObjects
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Updated user properties are displayed as a formatted table in the console.

## NOTES

Version: 1.2.0
1.2.0 - Added ClearForceChangePasswordNextSignIn parameter set to undo the force-change flag.
1.1.0 - Added ForceChangePasswordNextSignIn parameter set.
Removed default parameter set;
        operator must now explicitly choose a password mode.
Renamed to Reset-IRTUserPassword.
1.0.1 - Updated to output password in safe way.
Fixed bug preventing password reset.
        Updated variable names.


## RELATED LINKS

{{ Fill in the related links here }}
