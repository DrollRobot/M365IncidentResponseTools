---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTDevice
---

# Find-IRTDevice

## SYNOPSIS

Finds devices by display name, device ID, operating system, registered owner, serial number,
or other Entra/Intune identifiers. Creates $IRT_DeviceObjects from combined Entra + Intune
device records.

## SYNTAX

### Search (Default)

```
Find-IRTDevice [-Search] <string[]> [-VarPrefix <string>] [-Script] [-AllMatches]
 [<CommonParameters>]
```

### Clipboard

```
Find-IRTDevice -FromClipboard [-VarPrefix <string>] [-Script] [-AllMatches] [<CommonParameters>]
```

## ALIASES

FindDevice, FindDevices

## DESCRIPTION

Searches the cached combined Entra + Intune device records for one or more search strings.
Each string is matched against DisplayName, DeviceId, OperatingSystem, OwnerUPN, the Entra
object id, the Entra registered-owner display names, and the Intune object id, device name,
serial number, email address, and IMEI.

Matching devices are stored in $Global:IRT_DeviceObjects.
Use -VarPrefix to change the
variable name (e.g.
'Admin' > $Global:IRT_AdminDeviceObjects).
A search that returns more
than one device is reported but contributes nothing unless -AllMatches is used.
Use -Script
to suppress global side effects and return the objects directly.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTDevice DESKTOP-ABC123
```
Finds devices matching 'DESKTOP-ABC123' and creates $IRT_DeviceObjects.

### EXAMPLE 2

```powershell
Find-IRTDevice -Search DESKTOP-ABC123,LAPTOP-XYZ789
```
Searches for two devices, one query per string.

### EXAMPLE 3

```powershell
Find-IRTDevice -Search SN1234567890
```
Searches by Intune serial number. Partial device, Entra, and Intune ids also match.

### EXAMPLE 4

```powershell
$Devices = Find-IRTDevice -Search 'DESKTOP-ABC123' -AllMatches -Script
```
Returns every matching device object without setting globals or writing to the console.

### EXAMPLE 5

```powershell
Find-IRTDevice -FromClipboard
```
Reads the clipboard and searches for each line as a separate query.

## PARAMETERS

### -AllMatches

Keep every device returned by a search instead of only searches that match exactly one
device.
Results are deduplicated by Entra object id.

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

Return objects directly and suppress console output and global variable assignment.
Use when
calling from scripts or the playbook.

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
'Admin' > $Global:IRT_AdminDeviceObjects).
Useful when working with multiple sets of
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

### System.Management.Automation.PSObject[]

## NOTES

Version: 1.3.1
1.3.1 - Added missing help sections so PlatyPS can generate the command page.
1.3.0 - Added -FromClipboard to read one search query per clipboard line.
1.2.0 - Added -AllMatches to collect all matching devices and deduplicate results.


## RELATED LINKS

{{ Fill in the related links here }}
