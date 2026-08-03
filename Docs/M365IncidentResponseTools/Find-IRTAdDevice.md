---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTAdDevice
---

# Find-IRTAdDevice

## SYNOPSIS

Finds a local AD computer by Name, DNSHostName, SamAccountName, Description,
or ObjectGUID.

## SYNTAX

### Search (Default)

```
Find-IRTAdDevice [-Search] <string[]> [-VarPrefix <string>] [-Script] [<CommonParameters>]
```

### Clipboard

```
Find-IRTAdDevice -FromClipboard [-VarPrefix <string>] [-Script] [<CommonParameters>]
```

## ALIASES

Find-IRTAdDevices, Find-AdDevice, Find-AdDevices, FindIRTAdDevice, FindIRTAdDevices, FindAdDevice, FindAdDevices

## DESCRIPTION

Searches Active Directory for computers matching one or more search strings.
The search
is applied across Name, DNSHostName, SamAccountName, Description, and ObjectGUID.

If a single computer is found, the full AD object is retrieved and stored in
$Global:IRT_DeviceObject.
Use -VarPrefix to change the variable name
(e.g.
'Target' > $Global:IRT_TargetDeviceObject).
For multiple matches the results are
displayed but no global is set.
Use -Script to suppress global side effects and
return objects directly.

## EXAMPLES

### EXAMPLE 1

Find-IRTAdDevice DESKTOP-ABC123
Finds computers matching 'DESKTOP-ABC123' and sets the global device object if exactly
one match.

### EXAMPLE 2

Find-IRTAdDevice desktop-abc123.contoso.com
Searches by DNS host name.

### EXAMPLE 3

$Devices = Find-IRTAdDevice -Search 'DESKTOP-ABC123','LAPTOP-XYZ789' -Script
Returns matching computer objects for two search strings without setting globals.

### EXAMPLE 4

Find-IRTAdDevice -FromClipboard
Reads the clipboard and searches for each line as a separate query.

## PARAMETERS

### -FromClipboard

Read one search query per line from the clipboard instead of supplying -Search.
Each
non-empty line is treated as a separate search string.
Mutually exclusive with -Search.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Clipboard
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Script

Return objects directly and suppress global variable assignment.
Use when calling from
scripts or the playbook.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Search

One or more search strings.
Each string is independently searched across all supported
fields.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -VarPrefix

Optional prefix inserted after 'IRT_' in the global variable name
(e.g.
'Target' > $Global:IRT_TargetDeviceObject).
Useful when working with multiple
devices simultaneously.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
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

### None by default (sets global variables).
Microsoft.ActiveDirectory.Management.ADComputer[] when -Script is used.

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

## NOTES

Version: 1.1.0
1.1.0 - Added -FromClipboard to read one search query per clipboard line.


## RELATED LINKS

{{ Fill in the related links here }}
