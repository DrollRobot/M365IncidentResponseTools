---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTMessageTrace
---

# Show-IRTMessageTrace

## SYNOPSIS

Processes message trace data into an Excel spreadsheet.

## SYNTAX

### Objects (Default)

```
Show-IRTMessageTrace [[-Message] <List`1[psobject]>] [-TableStyle <string>] [-Font <string>]
 [-IpInfo] [-Open <bool>] [<CommonParameters>]
```

### Xml

```
Show-IRTMessageTrace [-XmlPath] <string> [-TableStyle <string>] [-Font <string>] [-IpInfo]
 [-Open <bool>] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Takes message trace records produced by Get-IRTMessageTrace (or imported from a raw
XML export) and renders them into a formatted Excel workbook.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTMessageTrace -XmlPath '.\MessageTrace_10Days_bob_26-09-16_14-30.xml'
```
Rebuilds the message trace workbook from a raw XML export.

### EXAMPLE 2

```powershell
Show-IRTMessageTrace -XmlPath '.\MessageTrace_10Days_bob_26-09-16_14-30.xml' -IpInfo
```
Rebuilds the workbook with ip_info lookups on the FromIP and ToIP columns.

## PARAMETERS

### -Font

Excel font name.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelFont
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

### -IpInfo

Enrich FromIP/ToIP with ip_info lookup data in the Excel output.
Off by default
because lookups are slow for large message traces.
Ignored if ip_info is not installed.

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

### -Message

A list of message trace records with a metadata entry at index 0.
Produced by
Get-IRTMessageTrace.
Accepts pipeline input.
Mutually exclusive with -XmlPath.

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Messages
ParameterSets:
- Name: Objects
  Position: 0
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Open

Open the Excel workbook after exporting.
Defaults to IRT_Config.OpenSpreadsheets.

```yaml
Type: System.Boolean
DefaultValue: '[bool]$Global:IRT_Config.OpenSpreadsheets'
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
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -XmlPath

Path to a raw XML file exported by Get-IRTMessageTrace.
Mutually exclusive with
-Message.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Xml
  Position: 0
  IsRequired: true
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

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

{{ Fill in the Description }}

## OUTPUTS

### None. Results are written to an Excel workbook.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
