---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTUserObject

## SYNOPSIS
Gets user objects from global variables.
Designed to be used by other scripts.

## SYNTAX

```
Get-IRTUserObject [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Returns the de-duplicated, DisplayName-sorted list of Entra ID user objects currently
stored in $Global:IRT_UserObjects.
This is the standard way IRT functions resolve users
when no -UserObject parameter is supplied directly.

## EXAMPLES

### EXAMPLE 1
```
$Users = Get-IRTUserObject
Returns all user objects currently in the global session.
```

## PARAMETERS

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

### System.Collections.Generic.List[PSObject]
## NOTES
Version: 1.0.3

## RELATED LINKS
