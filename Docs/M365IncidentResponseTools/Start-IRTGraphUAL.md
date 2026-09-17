---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Start-IRTGraphUAL
---

# Start-IRTGraphUAL

## SYNOPSIS

Starts a Unified Audit Log search through the Microsoft Graph audit search API.

## SYNTAX

### UserObject (Default)

```
Start-IRTGraphUAL [[-UserObject] <psobject[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-Operation <string[]>] [-RecordType <string[]>] [-RiskyOperation] [-SignInLog]
 [-FreeText <string[]>] [-IpAddress <string[]>] [-NoWait] [-Audio <bool>] [-Excel <bool>]
 [-Xml <bool>] [-Cached] [-NamePrefix <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### AllUsers

```
Start-IRTGraphUAL [-AllUsers] [-Days <int>] [-Start <string>] [-End <string>]
 [-Operation <string[]>] [-RecordType <string[]>] [-RiskyOperation] [-SignInLog]
 [-FreeText <string[]>] [-IpAddress <string[]>] [-NoWait] [-Audio <bool>] [-Excel <bool>]
 [-Xml <bool>] [-Cached] [-NamePrefix <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### ServicePrincipal

```
Start-IRTGraphUAL [[-ServicePrincipal] <psobject[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-Operation <string[]>] [-RecordType <string[]>] [-RiskyOperation] [-SignInLog]
 [-FreeText <string[]>] [-IpAddress <string[]>] [-NoWait] [-Audio <bool>] [-Excel <bool>]
 [-Xml <bool>] [-Cached] [-NamePrefix <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

GraphUAL, StartGraphUAL

## DESCRIPTION

Submits one or more server-side audit log query jobs and, by default, waits for them
and downloads the results.

This is the duplicate-free alternative to Get-IRTUnifiedAuditLog.
That function runs
several overlapping Search-UnifiedAuditLog queries per user and pages each with
ReturnLargeSet, which returns the same event more than once, sometimes under a
different Identity so deduplication misses it.
The Graph API runs one server-side job
per filter set and returns each record once with a stable id, and it is not capped at
50,000 records.

The trade is speed.
The service schedules these jobs in batches: expect roughly
35 minutes before results are ready, whatever the size of the search.
A one hour
window costs the same as ninety days.
Use Get-IRTUnifiedAuditLog when time matters and
this when completeness does.

Jobs run server-side, so Ctrl+C during the wait is safe.
The jobs keep running and can
be collected later with Wait-IRTGraphUAL or Receive-IRTGraphUAL.
They cannot be
cancelled or deleted; the API offers neither, and they expire on their own after about
thirty days.

Each search submits a group of jobs, one per identifier.
For a user that means three
keyword jobs: their address, their object id, and their object id with the dashes
stripped, because workloads differ in which form they record.
Keyword matching also
finds records where the user was the target of someone else's action, not only ones
they performed themselves.

Requires a Microsoft Graph connection with AuditLogsQuery.Read.All.

## EXAMPLES

### EXAMPLE 1

```powershell
Start-IRTGraphUAL -UserObject $User -Days 90
```
Searches 90 days for a user, waits, and exports the results.

### EXAMPLE 2

```powershell
Start-IRTGraphUAL -UserObject $User -Days 30 -NoWait
```
Submits the jobs and returns. Collect them later with Wait-IRTGraphUAL.

### EXAMPLE 3

```powershell
Start-IRTGraphUAL -AllUsers -RecordType 'MicrosoftTeams' -Days 7
```
Searches the whole tenant for Teams records over the last week.

### EXAMPLE 4

```powershell
Start-IRTGraphUAL -ServicePrincipal $Sp -Days 180
```
Searches 180 days for a service principal by object id and app id.

## PARAMETERS

### -AllUsers

Search the whole tenant.
Mutually exclusive with -UserObject and -ServicePrincipal.
The service allows only one unfiltered job to be open at a time, so this is refused
while another is still running.

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

### -Audio

Play a sound when the search finishes.
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

### -Cached

Use pre-cached Graph data where available when building the workbook.

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

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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
Cannot be combined with -Start or -End.

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

End of an absolute date range, as any parseable date string.
Used with -Start.

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

Export results to an Excel workbook when they are downloaded.
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

### -FreeText

One or more free text strings.
The API takes a single keyword per job, so each string
adds a job to the group.

```yaml
Type: System.String[]
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

### -IpAddress

Restrict the search to one or more client IP addresses.

```yaml
Type: System.String[]
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

### -NamePrefix

Prefix for the job display names.
Defaults to IRT_Config.JobNamePrefix, the
same marker used for email compliance searches.

```yaml
Type: System.String
DefaultValue: (Get-IRTJobNamePrefix)
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

### -NoWait

Submit the jobs and return immediately instead of waiting for them.

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

### -Operation

Restrict the search to specific UAL operation names.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Operations
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

### -RecordType

Restrict the search to one or more UAL record types, for example MicrosoftTeams.
Unlike Search-UnifiedAuditLog, the Graph API accepts several in a single job.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- RecordTypes
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

### -RiskyOperation

Search only the high risk operations listed in the operations sheet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- RiskyOperations
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

### -ServicePrincipal

One or more service principal objects to search for.
Mutually exclusive with
-UserObject and -AllUsers.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- ServicePrincipals
ParameterSets:
- Name: ServicePrincipal
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SignInLog

Search only UAL sign-in operations.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- SignInLogs
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

Start of an absolute date range, as any parseable date string.
Used with -End.

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

### -UserObject

One or more user objects to search for.
Mutually exclusive with -AllUsers and
-ServicePrincipal.
Falls back to the global session objects if omitted.

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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

Export the raw records alongside the workbook.
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

### [pscustomobject] describing the submitted group: GroupId

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

## NOTES

Version: 1.1.0
1.1.0 - Removed -ResultLimit.
It was stored on the group but never reached the
download.


## RELATED LINKS

{{ Fill in the related links here }}
