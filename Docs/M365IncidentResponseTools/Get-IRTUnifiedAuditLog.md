---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
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
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-HighCompleteness]
 [-ResultLimit <int>] [-ExhaustedPageQueries <int>] [-Operation <string[]>] [-RiskyOperation]
 [-SignInLog] [-FreeText <string[]>] [-RecordType <string[]>] [-Excel <bool>]
 [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [-PassThru] [<CommonParameters>]
```

### AllUsers

```
Get-IRTUnifiedAuditLog [-AllUsers] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-HighCompleteness]
 [-ResultLimit <int>] [-ExhaustedPageQueries <int>] [-Operation <string[]>] [-RiskyOperation]
 [-SignInLog] [-FreeText <string[]>] [-RecordType <string[]>] [-Excel <bool>]
 [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [-PassThru] [<CommonParameters>]
```

### ServicePrincipal

```
Get-IRTUnifiedAuditLog [[-ServicePrincipal] <psobject[]>] [-Days <int>] [-Start <string>]
 [-End <string>] [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>]
 [-HighCompleteness] [-ResultLimit <int>] [-ExhaustedPageQueries <int>] [-Operation <string[]>]
 [-RiskyOperation] [-SignInLog] [-FreeText <string[]>] [-RecordType <string[]>] [-Excel <bool>]
 [-WaitOnMessageTrace <bool>] [-Xml <bool>] [-Cached] [-PassThru] [<CommonParameters>]
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

### EXAMPLE 4

```powershell
Get-IRTUnifiedAuditLog -UserObject $User -Days 30 -RecordType 'MicrosoftTeams'
```
Pulls only Microsoft Teams records for the user over the last 30 days.

### EXAMPLE 5

```powershell
$Logs = Get-IRTUnifiedAuditLog -AllUsers -Days 7 -Excel $false -Xml $false -PassThru
```
Returns the records in memory without writing any files.

### EXAMPLE 6

```powershell
Get-IRTUnifiedAuditLog -UserObject $User -Days 7 -HighCompleteness -ChunkDays 1
```
Runs the slower high-completeness search, one day per chunk to keep each query
inside the service's timeout. Use when a default search returns suspiciously
little and the gap has to be ruled out.

### EXAMPLE 7

```powershell
Get-IRTUnifiedAuditLog -AllUsers -Days 7 -ExhaustedPageQueries 3
```
Keeps paging each query until three full pages in a row add no new records. Compare
the 'Total retrieved' count against a default run to see whether stopping at the
first page of duplicates misses records.

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

### -ExhaustedPageQueries

Number of full pages in a row that must add no new records before a query stops
paging.
An exhausted search keeps returning full 5000-record pages of records it has
already served, so a page of nothing new is the end-of-set signal.
A page that does
add records resets the count.
Raise it to test whether the service still returns
new records after a page of duplicates; each extra page costs another request.
Default: 1.

```yaml
Type: System.Int32
DefaultValue: 1
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

### -HighCompleteness

Run the search on Exchange's high-completeness path.
Without it the service
prioritises speed and may silently return an incomplete result set.
Searches are
slower with it, which on wide date ranges raises the chance of a timeout or an
expired search session, so it is off by default.
Pair it with a smaller -ChunkDays.
The switch is only sent to Search-UnifiedAuditLog when specified, so older
ExchangeOnlineManagement builds that lack the parameter still work by default.

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

### -PassThru

Emit the retrieved records to the pipeline in addition to any configured
exports.
One collection is emitted per queried object (user, service
principal, or the single 'AllUsers' pseudo-object), and each collection
carries the same metadata object at index 0 that the XML export writes.
Intended for callers that post-process results in memory rather than
reading the exported files back off disk.

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

### -RecordType

Filter results to one or more UAL record types (e.g.
MicrosoftTeams,
ExchangeItem, AzureActiveDirectoryStsLogon).
Search-UnifiedAuditLog accepts a
single record type per call, so every query is run once per record type given.

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

### -ResultLimit

Maximum total records to retrieve across all queries and date chunks.
Counts
deduplicated records, so overlapping pages and overlapping queries do not spend the
limit on repeats.
Stops at the next 5000-record page boundary after the limit is
reached.
Since queries run from the most recent chunk backward, the most recent
events are retained.
When the limit stops a pull early, a DATA MISSING marker row
(RecordType IRT_RESULT_LIMIT) is added to the results, so the truncation shows in
the exported data and not only in the console.
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
Default: 30.

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

### None by default. Results are exported to an Excel workbook. With -PassThru

## NOTES

Version: 1.16.0
1.16.0 - A pull stopped early by -ResultLimit now gets a DATA MISSING marker row
(RecordType IRT_RESULT_LIMIT), so truncated results are visible in the output.
1.15.0 - Added -ExhaustedPageQueries to set how many all-duplicate pages in a row end a
query's paging.
The default of 1 keeps the 1.13.0 behaviour.
1.14.0 - Added -HighCompleteness (off by default).
Retry backoff now starts at 30s
instead of 60s.
1.13.0 - Paging now stops when the result set is exhausted.
Search-UnifiedAuditLog
keeps returning full 5000-record pages of already-served records instead of a short
page, so the old page-size-only loop ran until ResultLimit or a session timeout.
Paging now ends when a full page adds no records the query has not already served.
Records are also deduplicated as pages arrive rather than at the end, so
-ResultLimit counts real records instead of repeats, and the console reports both
the deduplicated and raw record counts.
1.12.0 - Added -PassThru so callers can post-process records in memory
instead of reading the exported files back off disk.
1.11.0 - Added a data-gap marker for queries that fail after all retries.
1.10.0 - Added -RecordType to filter queries by UAL record type.
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
