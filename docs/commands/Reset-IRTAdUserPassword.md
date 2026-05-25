---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Reset-IRTAdUserPassword

## SYNOPSIS
Resets an Active Directory user's password.

## SYNTAX

### RandomCharacters
```
Reset-IRTAdUserPassword [[-UserObjects] <PSObject[]>] [-RandomCharacters] [-Length <Int32>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Custom
```
Reset-IRTAdUserPassword [[-UserObjects] <PSObject[]>] [-Custom] [-ProgressAction <ActionPreference>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### ForceChangePasswordNextSignIn
```
Reset-IRTAdUserPassword [[-UserObjects] <PSObject[]>] [-ForceChangePasswordNextSignIn]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Resets the on-premises AD password for one or more users.
Exactly one of the three password mode switches must be specified:

- RandomCharacters: generates a random password (default length: 30 characters) and sets
  it immediately. The password is written via [Console]::WriteLine to bypass transcript logging.
- Custom: prompts the operator via Read-Host -AsSecureString.
- ForceChangePasswordNextSignIn: sets ChangePasswordAtLogon = $true without changing the
  current password.

After the reset, updated account properties are retrieved and displayed as a table.
If running on a domain controller, intra-AD replication is triggered via repadmin.
If the ADSync service is local, an Azure AD delta sync is started.

Falls back to global session objects via Get-AdGlobalUserObject if no -UserObjects is passed.

## EXAMPLES

### EXAMPLE 1
```
Reset-IRTAdUserPassword -RandomCharacters
Generates and sets a random password for the user in the global session.
```

### EXAMPLE 2
```
Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters
Resets the password for a specific user object using a random password.
```

### EXAMPLE 3
```
Reset-IRTAdUserPassword -Custom
Prompts the operator to enter a custom password for the global session user.
```

### EXAMPLE 4
```
Reset-IRTAdUserPassword -UserObjects $User -ForceChangePasswordNextSignIn
Forces the user to set a new password on their next sign-in without changing the current password.
```

### EXAMPLE 5
```
Reset-IRTAdUserPassword -RandomCharacters -Length 48
Resets the password using a random 48-character password.
```

## PARAMETERS

### -UserObjects
One or more AD user objects whose passwords will be reset.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObject

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RandomCharacters
Generates a random password of the specified length and applies it to the account.
The password is written directly to the console (bypassing transcript logging).

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
The length of the randomly generated password. Only valid with -RandomCharacters.
Must be at least 4 characters. Defaults to 30.

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
Prompts the operator to enter a custom password via Read-Host -AsSecureString.

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
Sets ChangePasswordAtLogon = $true on the account without changing the current password.
The user will be required to set a new password on their next sign-in.

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
Shows what would happen if the cmdlet runs. The cmdlet is not run.

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

### None. The new password is written to the console (bypassing transcripts).
## NOTES
Version: 1.0.0

## RELATED LINKS
