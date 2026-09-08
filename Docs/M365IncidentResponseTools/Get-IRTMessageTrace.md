---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTMessageTrace
---

# Get-IRTMessageTrace

## SYNOPSIS

Downloads incoming and outgoing message trace for specified user, or all users.

## SYNTAX

### UserObject (Default)

```
Get-IRTMessageTrace [[-UserObject] <psobject[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-ResultLimit <int>] [-Variable <bool>] [-Excel <bool>] [-Quiet] [-Xml <bool>]
 [-TableStyle <string>] [-Font <string>] [<CommonParameters>]
```

### UserEmail

```
Get-IRTMessageTrace [-UserEmail <string[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-ResultLimit <int>] [-Variable <bool>] [-Excel <bool>] [-Quiet] [-Xml <bool>]
 [-TableStyle <string>] [-Font <string>] [<CommonParameters>]
```

### AllUsers

```
Get-IRTMessageTrace [-AllUsers] [-Days <int>] [-Start <string>] [-End <string>] [-ResultLimit <int>]
 [-Variable <bool>] [-Excel <bool>] [-Quiet] [-Xml <bool>] [-TableStyle <string>] [-Font <string>]
 [<CommonParameters>]
```

## ALIASES

MessageTrace

## DESCRIPTION

Retrieves Exchange Online message trace records for one or more users over a configurable
date range and exports results to Excel.
Accepts user objects, email addresses, or an
-AllUsers switch for tenant-wide queries.

Supports both the modern V2 API (large result sets via background jobs) and the legacy
V1 endpoint.
Date range defaults to the last 10 days when no -Days, -Start, or -End
is specified.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTMessageTrace
```
Downloads message trace for the user in the global session (last 10 days).

### EXAMPLE 2

```powershell
Get-IRTMessageTrace -UserObject $User -Days 30
```
Downloads 30 days of message trace for a specific user.

### EXAMPLE 3

```powershell
Get-IRTMessageTrace -AllUsers -Start '2026-04-01' -End '2026-04-30'
```
Downloads all tenant message trace for April 2026.

## PARAMETERS

### -AllUsers

Query message trace for all users in the tenant.
Mutually exclusive with -UserObject
and -UserEmail.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: AllUsers
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Days

Number of days back to search.
Cannot be used with -Start / -End.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -End

End of date range (parseable date string).
Used with -Start for an absolute range.

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

### -Excel

Export results to an Excel workbook.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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

### -Quiet

Suppress progress output.

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

### -ResultLimit

Maximum number of records to return.
Default: 50000.

```yaml
Type: System.Int32
DefaultValue: 50000
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

### -Start

Start of date range (parseable date string).
Used with -End for an absolute range.

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

### -UserEmail

One or more email addresses to trace.
Mutually exclusive with -UserObject and -AllUsers.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserEmails
ParameterSets:
- Name: UserEmail
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UserObject

One or more user objects to trace.
Mutually exclusive with -UserEmail and -AllUsers.
Falls back to global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObjects
ParameterSets:
- Name: UserObject
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Variable

Save results to a session variable for downstream use.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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

### -Xml

Export raw XML alongside the Excel file.
Defaults to IRT_Config.ExportXml.

```yaml
Type: System.Boolean
DefaultValue: $Global:IRT_Config.ExportXml
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

### None. Results are exported to Excel and stored in a session variable.

## NOTES

Version: 1.5.0
1.5.0 - Integrated V1 and V2 into same function.
1.4.0 - Switched to separate get/show functions.
Updated to passing objects, not files.
    Added global variables.


## RELATED LINKS

{{ Fill in the related links here }}
