---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Disable-AdUser

## SYNOPSIS
Disable on-premises AD user account(s).

## SYNTAX

```
Disable-AdUser [[-UserObject] <PSObject[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Thin wrapper around Set-AdUserEnabled that sets Enabled = $false.
Disables one or
more AD user accounts, re-fetches each account to confirm the change, then triggers
AD replication and an Azure AD delta sync if the relevant services are available.

Falls back to $Global:UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1
```
Disable-AdUser
Disables the user(s) in the global session.
```

### EXAMPLE 2
```
Disable-AdUser -UserObject $AdUser
Disables a specific user.
```

## PARAMETERS

### -UserObject
One or more AD user objects to disable.
Falls back to global session objects if omitted.

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

### None. Status is written to the console.
## NOTES
Version: 2.0.0

## RELATED LINKS
