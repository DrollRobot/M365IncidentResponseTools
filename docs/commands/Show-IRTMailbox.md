---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTMailbox

## SYNOPSIS
Displays mailbox properties.

## SYNTAX

```
Show-IRTMailbox [[-UserObject] <PSObject[]>] [-Cached] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Retrieves Exchange Online mailbox configuration and permissions for one or more users
and displays the results in the console.
Includes quota settings, forwarding rules,
litigation hold status, and current mailbox permissions.

Falls back to $Global:IRT_UserObjects if no -UserObject is passed.
Requires an active
Exchange Online connection.

## EXAMPLES

### EXAMPLE 1
```
Show-IRTMailbox
Displays mailbox details for the user in the global session.
```

### EXAMPLE 2
```
Show-IRTMailbox -UserObject $User
Displays mailbox details for a specific user.
```

## PARAMETERS

### -UserObject
One or more user objects to query.
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

### -Cached
Use pre-cached Exchange data where available instead of making new API calls.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

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

### None. Results are displayed in the console.
## NOTES
Version: 1.1.0

## RELATED LINKS
