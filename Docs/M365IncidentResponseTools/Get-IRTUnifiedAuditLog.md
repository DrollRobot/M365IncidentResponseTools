---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTUnifiedAuditLog
---

# Get-IRTUnifiedAuditLog

## SYNOPSIS

Runs multiple queries to pull all Unified Audit Log records related to a specific user.

## SYNTAX

### UserObject (Default)

```
Get-IRTUnifiedAuditLog [[-UserObject] <psobject[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-ResultLimit <int>]
 [-Operation <string[]>] [-RiskyOperation] [-SignInLog] [-FreeText <string[]>] [-Excel <bool>]
 [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [<CommonParameters>]
```

### AllUsers

```
Get-IRTUnifiedAuditLog [-AllUsers] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-ResultLimit <int>]
 [-Operation <string[]>] [-RiskyOperation] [-SignInLog] [-FreeText <string[]>] [-Excel <bool>]
 [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [<CommonParameters>]
```

### ServicePrincipal

```
Get-IRTUnifiedAuditLog [[-ServicePrincipal] <psobject[]>] [-Days <int>] [-Start <string>]
 [-End <string>] [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>]
 [-ResultLimit <int>] [-Operation <string[]>] [-RiskyOperation] [-SignInLog] [-FreeText <string[]>]
 [-Excel <bool>] [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [<CommonParameters>]
```

## ALIASES

GetUALog, GetUALogs, UALog, UALogs

## DESCRIPTION

Queries the Microsoft 365 Unified Audit Log via Exchange Online for activity related
to one or more users, a service principal, or all users in the tenant.
Runs several
categorised queries in parallel (e.g.
SharePoint, Exchange, Teams, Azure AD) and
exports each category to a separate sheet in an Excel workbook.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.
Requires an active Exchange Online connection.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTUnifiedAuditLog
```
Queries the UAL for the last 30 days for the user in the global session.

### EXAMPLE 2

```powershell
Get-IRTUnifiedAuditLog -UserObject $User -Days 90
```
Queries 90 days of UAL activity for a specific user.

### EXAMPLE 3

```powershell
Get-IRTUnifiedAuditLog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'
```
Finds all FileDeleted events for any user during April 2026.

## PARAMETERS

### -AllUsers

Query the UAL for all users in the tenant.
Mutually exclusive with -UserObject and
-ServicePrincipal.

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

### -ChunkDays

Splits the requested date range into sub-queries of this many days each, querying
newest to oldest and merging the results.
Default: 182.
Search-UnifiedAuditLog
degrades and times out on wide ranges, so large pulls (e.g.
-AllUsers over a long
range) are broken into windows small enough to return reliably.
Pass a smaller
value to further reduce the chance of failed queries due to timeouts.

```yaml
Type: System.Int32
DefaultValue: 182
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

Seconds to pause between chunk queries.
A small pause reduces the chance of
tripping Exchange throttling limits on large multi-chunk pulls.
Default: 2.
Set to 0 to disable.
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

### -FreeText

One or more free-text search strings passed to Search-UnifiedAuditLog.

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

### -Operation

Filter results to specific UAL operation names.

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

### -ResultLimit

Maximum total records to retrieve across all queries and date chunks.
Stops at the
next 5000-record page boundary after the limit is reached.
Since queries run from
the most recent chunk backward, the most recent events are retained.
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

### -RiskyOperation

Filter to a predefined list of high-risk operations.

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

One or more service principal objects to query.
Mutually exclusive with -UserObject
and -AllUsers.

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

Filter to only UAL sign-in operations.

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

Base backoff (seconds) used when a Search-UnifiedAuditLog query fails (timeout,
throttling, or a dropped session).
Backoff grows exponentially per retry
(base, base*2, base*4...) and the token is refreshed between attempts.
The full
exception is written to the PSFramework debug log for troubleshooting.
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

### -UserObject

One or more user objects to query.
Mutually exclusive with -AllUsers and
-ServicePrincipal.
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

### -WaitOnMessageTrace

Wait for any pending message trace jobs before querying.
Intended for use when running
playbook.
(running functions in parallel) Default: $false.

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

Version: 1.9.0
1.9.0 - Exposed -ChunkDays to control date-chunk size, added per-chunk token
refresh so long multi-chunk runs don't outlive the token's refresh window, an
inter-chunk delay (-ChunkDelaySeconds), and retry-with-backoff
(-ThrottleDelaySeconds) on failed queries, with full exceptions logged to debug.
A query that still fails after all retries now raises an error and inserts a
visible "DATA MISSING" marker row into the results so incomplete pulls are
obvious in the exported workbook, rather than silently returning partial data.
1.8.0 - Added date chunking for ranges over 182 days; ResultLimit now caps total
records across all queries rather than per-query.
1.7.0 - Added -ResultLimit to cap records pulled per query before paging stops.
1.6.0 - Added profile tags to allow generating specific sheets in Show-IRTUnifiedAuditLog.
1.5.1 - Added function name to all output.
1.5.0 - Added -AllUsers option, added test timers.
1.4.0 - Updating to add metadata object, use shorter file names.
1.3.0 - Updated to output objects.


## RELATED LINKS

{{ Fill in the related links here }}
