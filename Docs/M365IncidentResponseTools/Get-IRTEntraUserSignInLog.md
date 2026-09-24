---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTEntraUserSignInLog
---

# Get-IRTEntraUserSignInLog

## SYNOPSIS

Downloads user sign-in logs.

## SYNTAX

### UserObject (Default)

```
Get-IRTEntraUserSignInLog [[-UserObject] <psobject[]>] [-Days <int>] [-Start <string>]
 [-End <string>] [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>]
 [-NonInteractive] [-DeviceCode] [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>]
 [-Xml <bool>] [<CommonParameters>]
```

### AllUsers

```
Get-IRTEntraUserSignInLog [-AllUsers] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-NonInteractive]
 [-DeviceCode] [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>] [-Xml <bool>]
 [<CommonParameters>]
```

### IpAddress

```
Get-IRTEntraUserSignInLog [-IpAddress <string[]>] [-Days <int>] [-Start <string>] [-End <string>]
 [-ChunkDays <int>] [-ChunkDelaySeconds <int>] [-ThrottleDelaySeconds <int>] [-NonInteractive]
 [-DeviceCode] [-Beta <bool>] [-Excel <bool>] [-IpInfo <bool>] [-Open <bool>] [-Xml <bool>]
 [<CommonParameters>]
```

## ALIASES

GetSILog, GetSILogs, SILog, SILogs

## DESCRIPTION

Retrieves Entra ID user sign-in logs via Microsoft Graph for one or more users, a set
of IP addresses, or all users in the tenant.
Enriches each log entry with IP
geolocation data and human-readable Entra error descriptions, then exports results to
an Excel workbook.

A thin wrapper that resolves the target users, builds the user-specific filter and
naming, and hands off to the shared Invoke-IRTSignInLogQuery engine (chunking,
throttle/retry, export).
For service principal sign-ins, see Get-IRTEntraSPSignInLog.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTEntraUserSignInLog
```
Downloads the last 30 days of sign-in logs for the user in the global session.

### EXAMPLE 2

```powershell
Get-IRTEntraUserSignInLog -UserObject $User -Days 7
```
Downloads 7 days of sign-in logs for a specific user.

### EXAMPLE 3

```powershell
Get-IRTEntraUserSignInLog -IpAddress '203.0.113.5' -Days 14
```
Finds all sign-ins from a specific IP over the last 14 days.

### EXAMPLE 4

```powershell
Get-IRTEntraUserSignInLog -NonInteractive
```
Downloads interactive and non-interactive sign-ins (3-day default) for the global user.

## PARAMETERS

### -AllUsers

Retrieve sign-in logs for all users in the tenant.
Mutually exclusive with -UserObject
and -IpAddress.

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
Default: 30 (a default 30-day pull is a
single chunk).
Graph applies its 300-second HttpClient timeout per request, so very
large pulls (e.g.
-AllUsers over a wide range) can time out while the server computes
a single page.
Pass a smaller value (e.g.
-ChunkDays 1) to break the request into
windows small enough to return in time.

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

Seconds to pause between chunk queries.
A small pause reduces the chance of
tripping Graph throttling limits on large multi-chunk pulls.
Default: 2.
Set to 0 to disable.

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

### -DeviceCode

Limit results to device code sign-ins: the redemption leg (authenticationProtocol)
and the downstream token use Entra carries forward on originalTransferMethod.

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

### -IpAddress

One or more IP addresses to filter sign-in logs by source IP.
Mutually exclusive with
-UserObject and -AllUsers.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: IpAddress
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

### -NonInteractive

Include non-interactive sign-ins alongside the interactive ones.
By default Graph
returns only interactive sign-ins; with this switch the pull covers both types
(use the SignInEventTypes column to tell them apart).
Because non-interactive
sign-ins are far more numerous, the default date range drops to 3 days.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- NI
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
Backoff grows exponentially per retry (base, base*2, base*4...).
When Graph does return Retry-After, that value is honored and printed instead.
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

One or more user objects whose sign-in logs to retrieve.
Mutually exclusive with
-AllUsers and -IpAddress.
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
2.0.0 - Renamed from Get-IRTEntraSignInLog.
The query/chunk/throttle/export engine
        was extracted into the shared private Invoke-IRTSignInLogQuery; this function
        is now a user-specific wrapper around it (parallel to Get-IRTEntraSPSignInLog).
1.5.0 - -NonInteractive now returns BOTH interactive and non-interactive sign-ins
        (previously non-interactive only).
The SignInEventTypes column (surfaced
        by Show-IRTEntraUserSignInLog) distinguishes them.
The 3-day default range
        still applies whenever non-interactive logs are included.
1.4.0 - -DeviceCode now also matches originalTransferMethod, which Entra carries
        forward onto the downstream token use that follows a device code
        redemption, via a server-side OR filter.
1.3.0 - File names now start with EntraSignInLog plus short filter flags
        (_NI_ non-interactive, _DC_ device code) and a clearer subject token
        (user / AllUsers / IP); the redundant domain section was dropped.
        Titles spell out scope, device code, and an absolute "start to end"
        or relative "N days from start" date range.
1.2.3 - Fixed -DeviceCode filter referencing an undefined variable, so the
        authenticationProtocol filter never applied.
1.2.2 - Fixed chunk-boundary off-by-one that produced a degenerate zero-width
        trailing chunk when the date range was an exact multiple of ChunkDays.
1.2.1 - Throttle handling: honor and print Retry-After, exponential backoff
        when absent, and an inter-chunk delay to avoid tripping limits.
1.2.0 - Added -ChunkDays to split large queries into smaller date windows,
        with per-chunk token refresh and retry on timeout/throttle, to work
        around the Graph 300s per-request HttpClient timeout.
1.1.2 - Added graceful exit when no logs are found.
1.1.1 - Added test timers.


## RELATED LINKS

{{ Fill in the related links here }}
