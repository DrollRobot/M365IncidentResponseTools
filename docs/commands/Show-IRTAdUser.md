---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTAdUser

## SYNOPSIS
Displays AD user properties.

## SYNTAX

```
Show-IRTAdUser [[-UserObjects] <PSObject[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves all properties of an on-premises AD user object, converts every DateTime
value to local time, and displays the result with Format-Tree.
Falls back to
$Global:IRT_UserObject (via Get-AdGlobalUserObject) if no -UserObjects is passed.

## EXAMPLES

### EXAMPLE 1
```
Show-IRTAdUser
Displays info for the user(s) in the global session.
```

### EXAMPLE 2
```
Show-IRTAdUser -UserObjects $AdUser
Displays info for a specific AD user object.
```

## PARAMETERS

### -UserObjects
One or more AD user objects to display.
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

### None. Output is written to the console.
## NOTES
Version: 1.2.0
1.2.0 - Switched to Format-Tree with dynamic DateTime conversion.
1.1.2 - Added pwdLastSet

## RELATED LINKS
