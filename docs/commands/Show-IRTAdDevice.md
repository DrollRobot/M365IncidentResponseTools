---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTAdDevice

## SYNOPSIS
Displays AD computer properties.

## SYNTAX

```
Show-IRTAdDevice [[-DeviceObject] <PSObject[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves all properties of an on-premises AD computer object, converts every DateTime
value to local time, and displays the result with Format-Tree.
Falls back to
$Global:IRT_DeviceObject if no -DeviceObject is passed.

## EXAMPLES

### EXAMPLE 1
```
Show-IRTAdDevice
Displays info for the device in $Global:IRT_DeviceObject.
```

### EXAMPLE 2
```
Show-IRTAdDevice -DeviceObject $AdComputer
Displays info for a specific AD computer object.
```

## PARAMETERS

### -DeviceObject
One or more AD computer objects to display.
Falls back to $Global:IRT_DeviceObject
if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases:

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
Version: 1.0.0

## RELATED LINKS
