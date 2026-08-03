---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTNonInteractiveSignIn
---

# Get-IRTNonInteractiveSignIn

## SYNOPSIS

Downloads non-interactive Entra ID sign-in logs for one or more users.

## SYNTAX

```
Get-IRTNonInteractiveSignIn [[-UserObject] <psobject[]>] [-Days <int>] [-Beta <bool>] [-Xml <bool>]
 [-Script <bool>] [-Open <bool>] [<CommonParameters>]
```

## ALIASES

GetNILog, GetNILogs, NILog, NILogs

## DESCRIPTION

A convenience wrapper around Get-IRTEntraSignInLog that sets -NonInteractive automatically.
Non-interactive sign-ins include token refresh events, legacy protocol logins, and
service-to-service calls - often missed during investigations that focus only on
interactive sign-ins.

Date range and output behavior are identical to Get-IRTEntraSignInLog.
Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1

Get-IRTNonInteractiveSignIn
Downloads non-interactive sign-in logs for the user in the global session.

### EXAMPLE 2

Get-IRTNonInteractiveSignIn -UserObject $User -Days 30
Downloads 30 days of non-interactive sign-ins for a specific user.

## PARAMETERS

### -Beta

Use the Microsoft Graph beta endpoint.
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

### -Days

Number of days back to search.

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
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Script

Return raw objects instead of exporting to Excel.
Default: $false.

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

### -UserObject

One or more user objects to query.
Falls back to global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObjects
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

### None by default. PSCustomObject[] when -Script is $true.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
