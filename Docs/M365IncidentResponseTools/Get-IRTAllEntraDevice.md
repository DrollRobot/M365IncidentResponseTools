---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTAllEntraDevice
---

# Get-IRTAllEntraDevice

## SYNOPSIS

Exports every Entra ID (Azure AD) device to a spreadsheet, newest registration first.

## SYNTAX

```
Get-IRTAllEntraDevice [[-Open] <bool>] [[-Xml] <bool>] [[-TableStyle] <string>] [[-Font] <string>]
 [<CommonParameters>]
```

## ALIASES

Get-IRTAllEntraDevices, GetAllEntraDevice, GetAllEntraDevices, AllEntraDevices

## DESCRIPTION

Queries Microsoft Graph for all registered/joined Entra devices and writes them to an
Excel workbook sorted by registration date (newest first).
Threat actors sometimes
register their own device against a compromised identity to persist and to satisfy
device-based Conditional Access, so surfacing the most recently registered devices at
the top of the sheet makes new, unexpected registrations easy to spot.

As much device detail as Graph exposes is included: join/trust type, registered owner,
operating system, compliance and management state, ownership, enrollment type, and the
registration and last sign-in timestamps.

## EXAMPLES

### EXAMPLE 1

Get-IRTAllEntraDevice
Exports all Entra devices to a spreadsheet and opens it.

### EXAMPLE 2

Get-IRTAllEntraDevice -Open $false -Xml $true
Writes the spreadsheet and a raw XML dump without opening the workbook.

## PARAMETERS

### -Font

Worksheet font.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelFont
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Open

Open the Excel file immediately after export.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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

### -TableStyle

Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelTableStyle
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Xml

Export the raw device objects to a .xml file alongside the workbook.
Defaults to IRT_Config.ExportXml.

```yaml
Type: System.Boolean
DefaultValue: $Global:IRT_Config.ExportXml
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
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

### None. Results are exported to an Excel workbook.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
