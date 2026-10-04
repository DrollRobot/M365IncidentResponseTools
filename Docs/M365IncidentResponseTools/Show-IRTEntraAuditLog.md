---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTEntraAuditLog
---

# Show-IRTEntraAuditLog

## SYNOPSIS

Processes Entra audit log objects into an Excel spreadsheet.

## SYNTAX

### Objects (Default)

```
Show-IRTEntraAuditLog [[-Log] <List`1[psobject]>] [-TableStyle <string>] [-Font <string>]
 [-IpInfo <bool>] [-Open <bool>] [-Cached] [<CommonParameters>]
```

### Xml

```
Show-IRTEntraAuditLog -XmlPath <string> [-TableStyle <string>] [-Font <string>] [-IpInfo <bool>]
 [-Open <bool>] [-Cached] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Takes Entra audit log objects produced by Get-IRTEntraAuditLog (or imported from a
raw XML export) and renders them into a formatted Excel workbook.
User, group, role
and service principal IDs in the logs are resolved to display names.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTEntraAuditLog -XmlPath '.\EntraAuditLogs_30Days_contoso.com_bob_26-09-16_14-30.xml'
```
Rebuilds the Entra audit log workbook from a raw XML export.

## PARAMETERS

### -Cached

Use pre-cached Graph data where available.

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

Enrich the InitiatedByIp column with ip_info lookup data.
Defaults to
IRT_Config.IpInfoAvailable.

```yaml
Type: System.Boolean
DefaultValue: '[bool]$Global:IRT_Config.IpInfoAvailable'
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

### -Log

A list of Entra audit log objects with a metadata entry at index 0.
Produced by
Get-IRTEntraAuditLog.
Mutually exclusive with -XmlPath.

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Logs
ParameterSets:
- Name: Objects
  Position: 0
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

Path to a raw XML file exported by Get-IRTEntraAuditLog.
Mutually exclusive with -Log.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Xml
  Position: Named
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

## OUTPUTS

### None. Results are written to an Excel workbook.

## NOTES

Version: 1.2.1
1.2.1 - Updates to use new get-graphobject functions.
1.2.0 - Many small updates to standardize across IR functions.
Updated to readable
        date format.


## RELATED LINKS

{{ Fill in the related links here }}
