---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Reset-IRTUserPassword

## SYNOPSIS
Resets an Entra ID user's password.

## SYNTAX

### RandomCharacters
```
Reset-IRTUserPassword [[-UserObject] <PSObject[]>] [-RandomCharacters] [-Length <Int32>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Custom
```
Reset-IRTUserPassword [[-UserObject] <PSObject[]>] [-Custom] [-ProgressAction <ActionPreference>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### ForceChangePasswordNextSignIn
```
Reset-IRTUserPassword [[-UserObject] <PSObject[]>] [-ForceChangePasswordNextSignIn]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Resets the password for one or more Entra ID users via the Microsoft Graph API.
Exactly
one of the three password mode switches must be specified:

  -RandomCharacters     Generates a random 30-character password and sets it immediately.
                        The new password is printed to the console via \[Console\]::WriteLine
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

If no -UserObject is supplied, the function falls back to the global session objects
stored in $Global:IRT_UserObjects (populated by Get-IRTUserObject).
An error is thrown
if neither source yields a user.

After the reset, updated account properties are retrieved and displayed as a table.
If the user is synced from on-premises Active Directory, a warning is shown reminding
the operator to also reset the password in the local AD.

Supports -WhatIf and -Confirm via SupportsShouldProcess.

## EXAMPLES

### EXAMPLE 1
```
Reset-IRTUserPassword -RandomCharacters
Resets the password for the user stored in the global session using a random password.
The new password is printed to the console.
```

### EXAMPLE 2
```
Reset-IRTUserPassword -UserObject $User -RandomCharacters
Resets the password for a specific user object using a random password.
```

### EXAMPLE 3
```
Reset-IRTUserPassword -Custom
Prompts the operator to enter a custom password, then applies it to the global session user.
```

### EXAMPLE 4
```
Reset-IRTUserPassword -UserObject $User -ForceChangePasswordNextSignIn
Forces the user to set a new password (with MFA) on their next sign-in, without
changing the current password.
```

### EXAMPLE 5
```
Reset-IRTUserPassword -RandomCharacters -Length 48
Resets the password using a random 48-character password.
```

### EXAMPLE 6
```
Reset-IRTUserPassword -UserObject $User -RandomCharacters -WhatIf
Shows what would happen without actually resetting the password.
```

## PARAMETERS

### -UserObject
One or more Entra ID user objects whose passwords will be reset.
Falls back to
$Global:IRT_UserObjects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RandomCharacters
Generates a random password of the specified length (default: 30 characters) and
applies it to the account.
The password is written directly to the console (bypassing
transcript logging) so it can be recorded securely by the operator.

```yaml
Type: SwitchParameter
Parameter Sets: RandomCharacters
Aliases: Random

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Length
The length of the randomly generated password.
Only valid with -RandomCharacters.
Must be at least 4 characters.
Defaults to 30.

```yaml
Type: Int32
Parameter Sets: RandomCharacters
Aliases:

Required: False
Position: Named
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -Custom
Prompts the operator to enter a custom password via Read-Host.
The password is applied
immediately with ForceChangePasswordNextSignIn set to $false.

```yaml
Type: SwitchParameter
Parameter Sets: Custom
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ForceChangePasswordNextSignIn
Sets ForceChangePasswordNextSignInWithMfa = $true on the account without changing the
current password.
The user will be required to set a new password (verified with MFA)
on their next sign-in.

```yaml
Type: SwitchParameter
Parameter Sets: ForceChangePasswordNextSignIn
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Updated user properties are displayed as a formatted table in the console.
## NOTES
Version: 1.1.0
1.1.0 - Added ForceChangePasswordNextSignIn parameter set.
Removed default parameter set;
        operator must now explicitly choose a password mode.
Renamed to Reset-IRTUserPassword.
1.0.1 - Updated to output password in safe way.
Fixed bug preventing password reset.
        Updated variable names.

## RELATED LINKS
