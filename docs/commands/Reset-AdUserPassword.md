---
external help file: LocalAdTools-help.xml
Module Name: LocalAdTools
online version:
schema: 2.0.0
---

# Reset-AdUserPassword

## SYNOPSIS
Resets an Active Directory user's password.

## SYNTAX

### RandomCharacters (Default)
```
Reset-AdUserPassword [[-UserObjects] <PSObject[]>] [-RandomCharacters] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### Custom
```
Reset-AdUserPassword [[-UserObjects] <PSObject[]>] [-Custom] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Resets the on-premises AD password for one or more users.
Two modes are available:

- RandomCharacters (default): generates a 30-character random password using
  Get-RandomPassword and writes it directly to \[Console\]::WriteLine to intentionally
  bypass transcript logging.
- Custom: prompts interactively via Read-Host -AsSecureString.

After the reset, the user object is re-fetched to confirm PasswordLastSet changed.
If running on a domain controller, intra-AD replication is triggered via repadmin.
If the ADSync service is local, an Azure AD delta sync is started.

Falls back to $Global:UserObjects if no -UserObjects is passed.

## EXAMPLES

### EXAMPLE 1
```
Reset-AdUserPassword
Generates and sets a random password for the user in the global session.
```

### EXAMPLE 2
```
Reset-AdUserPassword -UserObjects $User -Custom
Prompts for a custom password for a specific user.
```

## PARAMETERS

### -UserObjects
One or more AD user objects to reset.
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

### -Custom
Prompt for a custom password instead of generating a random one.

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

### -RandomCharacters
Generate a 30-character random password (default behavior).

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
