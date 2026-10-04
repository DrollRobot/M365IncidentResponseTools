---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTUnifiedAuditLog
---

# Show-IRTUnifiedAuditLog

## SYNOPSIS

Processes unified audit log records into an Excel spreadsheet.

## SYNTAX

### Objects (Default)

```
Show-IRTUnifiedAuditLog [[-Log] <List`1[psobject]>] [-TableStyle <string>] [-Font <string>]
 [-IpInfo <bool>] [-Open <bool>] [-WaitOnMessageTrace <bool>] [-MaxWaitMinutes <int>] [-Cached]
 [<CommonParameters>]
```

### Xml

```
Show-IRTUnifiedAuditLog [-XmlPath] <string> [-TableStyle <string>] [-Font <string>] [-IpInfo <bool>]
 [-Open <bool>] [-WaitOnMessageTrace <bool>] [-MaxWaitMinutes <int>] [-Cached] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Takes unified audit log records produced by Get-IRTUnifiedAuditLog or the Graph UAL
commands (or imported from a raw XML export) and renders them into a formatted Excel
workbook.
The workbook always has an all-operations sheet, plus a sign-in sheet when
the logs contain sign-in operations.
Logs from a -SignInLog query get only the
sign-in sheet.
Data-gap marker rows appear on every sheet.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTUnifiedAuditLog -XmlPath '.\UnifiedAuditLogs_7Days_contoso.com_bob_26-09-16_14-30.xml'
```
Rebuilds the unified audit log workbook from a raw XML export.

### EXAMPLE 2

```powershell
Show-IRTUnifiedAuditLog -XmlPath $XmlPath -IpInfo $false -Open $false
```
Rebuilds the workbook without IP lookups, and saves it without opening it.

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

Enrich IP addresses with ip_info lookup data.
Defaults to IRT_Config.IpInfoAvailable.

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

A list of unified audit log records with a metadata entry at index 0.
Produced by
Get-IRTUnifiedAuditLog.
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

### -MaxWaitMinutes

How long -WaitOnMessageTrace waits before continuing without email subjects.
Default: 15.

```yaml
Type: System.Int32
DefaultValue: 15
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

### -WaitOnMessageTrace

Wait for pending message trace jobs to finish, so email subjects can be added to the
all-operations sheet.
Intended for use when running playbook.
(running functions in
parallel) Default: $false.

```yaml
Type: System.Boolean
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

### -XmlPath

Path to a raw XML file exported by Get-IRTUnifiedAuditLog.
Mutually exclusive with
-Log.

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

## OUTPUTS

### None. Results are written to an Excel workbook.

## NOTES

Version: 1.0.2
1.0.2 - Data-gap marker rows (IRTDataGap) always pass operation filtering so
        missing-data markers appear on every sheet.
1.0.1 - Added option pass raw log objects, not just import from file.


## RELATED LINKS

{{ Fill in the related links here }}
