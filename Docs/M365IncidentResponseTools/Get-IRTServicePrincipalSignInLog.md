---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTServicePrincipalSignInLog
---

# Get-IRTServicePrincipalSignInLog

## SYNOPSIS

Downloads service principal sign-in logs.

## SYNTAX

### ServicePrincipalObject (Default)

```
Get-IRTServicePrincipalSignInLog [[-ServicePrincipalObject] <psobject[]>] [-Days <int>]
 [-Start <string>] [-End <string>] [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>]
 [-Xml <bool>] [<CommonParameters>]
```

### AllServicePrincipals

```
Get-IRTServicePrincipalSignInLog [-AllServicePrincipals] [-Days <int>] [-Start <string>]
 [-End <string>] [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>] [-Xml <bool>]
 [<CommonParameters>]
```

## ALIASES

GetSPSILog, GetSPSILogs, SPSILog, SPSILogs

## DESCRIPTION

Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
service principals or all service principals in the tenant.
Enriches each log entry
with IP geolocation data and human-readable Entra error descriptions, then exports
results to an Excel workbook.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
passed.
Use Find-IRTServicePrincipal first to populate that global variable.

## EXAMPLES

### EXAMPLE 1

Find-IRTServicePrincipal MyApp
Get-IRTServicePrincipalSignInLog
Two-step workflow: find the SP then download its sign-in logs.

### EXAMPLE 2

Get-IRTServicePrincipalSignInLog -ServicePrincipalObject $SP -Days 90
Downloads 90 days of sign-in logs for a specific service principal.

### EXAMPLE 3

Get-IRTServicePrincipalSignInLog -AllServicePrincipals -Days 7
Downloads 7 days of sign-in logs for all service principals in the tenant.

## PARAMETERS

### -AllServicePrincipals

Retrieve sign-in logs for all service principals in the tenant.
Mutually exclusive
with -ServicePrincipalObject.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: AllServicePrincipals
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

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

### -IpInfo

Enrich results with IP geolocation data.
Default: $true.

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

### -ServicePrincipalObject

One or more service principal objects whose sign-in logs to retrieve.
Mutually
exclusive with -AllServicePrincipals.
Falls back to global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- ServicePrincipalObjects
ParameterSets:
- Name: ServicePrincipalObject
  Position: 0
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

### None. Results are exported to an Excel workbook.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
