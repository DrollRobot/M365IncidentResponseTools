---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTAdDevice
---

# Show-IRTAdDevice

## SYNOPSIS

Displays AD computer properties.

## SYNTAX

```
Show-IRTAdDevice [[-DeviceObject] <psobject[]>] [<CommonParameters>]
```

## ALIASES

Show-IRTAdDevices, Show-AdDevice, Show-AdDevices, ShowIRTAdDevice, ShowIRTAdDevices, ShowAdDevice, ShowAdDevices

## DESCRIPTION

Retrieves all properties of an on-premises AD computer object, converts every DateTime
value to local time, and displays the result with Format-Tree.
Falls back to
$Global:IRT_DeviceObject if no -DeviceObject is passed.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTAdDevice
```
Displays info for the device in $Global:IRT_DeviceObject.

### EXAMPLE 2

```powershell
Show-IRTAdDevice -DeviceObject $AdComputer
```
Displays info for a specific AD computer object.

## PARAMETERS

### -DeviceObject

One or more AD computer objects to display.
Falls back to $Global:IRT_DeviceObject
if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Output is written to the console.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
