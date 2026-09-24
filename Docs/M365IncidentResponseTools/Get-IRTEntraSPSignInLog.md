---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTEntraSPSignInLog
---

# Get-IRTEntraSPSignInLog

## SYNOPSIS

Downloads service principal sign-in logs.

## SYNTAX

### ServicePrincipalObject (Default)

```
Get-IRTEntraSPSignInLog [[-ServicePrincipalObject] <psobject[]>] [-Days <int>] [-Start <string>]
 [-End <string>] [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>]
 [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>] [-Xml <bool>] [<CommonParameters>]
```

### AllServicePrincipals

```
Get-IRTEntraSPSignInLog [-AllServicePrincipals] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-Beta <bool>]
 [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>] [-Xml <bool>] [<CommonParameters>]
```

## ALIASES

GetSPSILog, GetSPSILogs, SPSILog, SPSILogs

## DESCRIPTION

Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
service principals or all service principals in the tenant.
Enriches each log entry
with IP geolocation data and human-readable Entra error descriptions, then exports
results to an Excel workbook.

A thin wrapper that resolves the target service principals, builds the SP-specific
filter and naming, and hands off to the shared Invoke-IRTSignInLogQuery engine
(chunking, throttle/retry, export).
For user sign-ins, see Get-IRTEntraUserSignInLog.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
passed.
Use Find-IRTServicePrincipal first to populate that global variable.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTServicePrincipal MyApp
Get-IRTEntraSPSignInLog
```
Two-step workflow: find the SP then download its sign-in logs.

### EXAMPLE 2

```powershell
Get-IRTEntraSPSignInLog -ServicePrincipalObject $SP -Days 90
```
Downloads 90 days of sign-in logs for a specific service principal.

### EXAMPLE 3

```powershell
Get-IRTEntraSPSignInLog -AllServicePrincipals -Days 7
```
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

### -ChunkDays

Splits the requested date range into sub-queries of this many days each, querying
newest to oldest and merging the results.
Default: 30.
Pass a smaller value to break
large pulls into windows small enough to return before Graph's per-request timeout.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -ChunkDelaySeconds

Seconds to pause between chunk queries to reduce throttling on multi-chunk pulls.
Default: 2.
Only applies when the range spans more than one chunk.

```yaml
Type: System.Int32
DefaultValue: 2
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

### -ThrottleDelaySeconds

Base backoff (seconds) used when Graph throttles a request but does not return a
Retry-After value.
Backoff grows exponentially per retry.
Default: 60.

```yaml
Type: System.Int32
DefaultValue: 60
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

Version: 2.0.0
2.0.0 - Renamed from Get-IRTServicePrincipalSignInLog.
Now a thin wrapper over the
        shared Invoke-IRTSignInLogQuery engine (parallel to Get-IRTEntraUserSignInLog),
        gaining chunking and throttle/timeout retry.
Resolution falls back to globals
        via the new Get-GlobalServicePrincipalObject helper.
1.0.0 - Initial version.


## RELATED LINKS

{{ Fill in the related links here }}
