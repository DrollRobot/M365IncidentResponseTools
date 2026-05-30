---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTUser

## SYNOPSIS
Displays user properties.

## SYNTAX

```
Show-IRTUser [[-UserObject] <MicrosoftGraphUser[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves the full Graph user object (all available properties) and displays it as a
formatted tree in the console.
Also updates $Global:IRT_UserObjects with the enriched
object so downstream playbook steps receive complete data.

Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1
```
Show-IRTUser
Displays info for the user stored in the global session.
```

### EXAMPLE 2
```
Show-IRTUser -UserObject $User
Displays info for a specific user object.
```

## PARAMETERS

### -UserObject
One or more Microsoft Graph user objects to display.
Falls back to global session
objects if omitted.

```yaml
Type: MicrosoftGraphUser[]
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

### None. Output is written to the console.
## NOTES
Version: 1.2.0
1.2.0 - Switched to Format-Tree, Show-GraphUserTree

## RELATED LINKS
