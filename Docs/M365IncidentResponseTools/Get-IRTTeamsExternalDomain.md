---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTTeamsExternalDomain
---

# Get-IRTTeamsExternalDomain

## SYNOPSIS

Pulls the Unified Audit Log records that reveal which external domains and
tenants the organisation communicates with over Microsoft Teams.

## SYNTAX

```
Get-IRTTeamsExternalDomain [[-Days] <int>] [[-Start] <string>] [[-End] <string>] [[-Week] <int[]>]
 [[-Path] <string>] [[-ResultLimit] <int>] [-Force] [<CommonParameters>]
```

## ALIASES

GetTeamsExtDomain, GetTeamsExtDomains

## DESCRIPTION

Queries the Unified Audit Log for the Teams operations whose audit records
carry the identity of the remote party in a chat, channel post, meeting, or
call.
Collating these records shows which outside organisations tenant users
actually talk to, which is the starting point for scoping a compromise that
spread through Teams federation or guest access.

The requested date range is split into calendar weeks running Sunday through
Saturday, and each week is queried and exported separately as a CLIXML file
named for the Sunday that begins the week.
Splitting the pull this way keeps
each Search-UnifiedAuditLog window small enough to return reliably, and lets
an interrupted run resume: weeks that already have a file on disk are skipped
unless -Force is passed.
To retry particular weeks, such as ones that reported
DATA MISSING markers, pass their numbers to -Week.

A file is written for every week that is queried, including weeks with no
matching activity.
An empty file therefore means "queried, nothing found",
which is a different and much more useful statement than a missing file.

Weeks are queried newest first, so the most recent activity lands on disk
soonest.

Operations queried:

    MessageSent              - chat and channel messages
    MessageCreatedHasLink    - messages containing a link
    MessageUpdated           - message edits
    MessageEditedHasLink     - edits to messages containing a link
    ChatCreated              - new chat threads
    MemberAdded              - members joining a chat or team
    MeetingParticipantDetail - meeting attendees, including guests
    CallParticipantDetail    - call participants
    ReactedToMessage         - message reactions (remote tenant ID only)
    UserAccepted             - external user accepted (remote tenant ID only)
    UserBlocked              - external user blocked (remote tenant ID only)

The last three record the remote party's tenant GUID but not its domain name,
so they still identify the external organisation - just not by a name a human
can read without resolving the GUID.

Guest accounts appear under this tenant's ID, with the guest's home domain
encoded in the UPN before #EXT# (jane_contoso.com#EXT#@tenant.onmicrosoft.com).

Requires an active Exchange Online connection, and a Microsoft Graph
connection for the tenant domain used in file names.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTTeamsExternalDomain
```
Pulls the last 180 days, writing one CLIXML file per Sunday-Saturday week
into the current directory.

### EXAMPLE 2

```powershell
Get-IRTTeamsExternalDomain -Days 30 -Path 'C:\Cases\Contoso'
```
Pulls the last 30 days into a specific folder.

### EXAMPLE 3

```powershell
Get-IRTTeamsExternalDomain -Start '2026-01-01' -End '2026-03-31' -Force
```
Pulls an absolute range, re-querying weeks that already have files.

### EXAMPLE 4

```powershell
Get-IRTTeamsExternalDomain -Start '2026-01-01' -End '2026-03-31' -Week 4, 9
```
Re-queries only weeks 4 and 9 of that range, for example after they reported
DATA MISSING markers. Their existing files are overwritten.

## PARAMETERS

### -Days

Number of days back to search.
Cannot be used with -Start / -End.
Default: 180.

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
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

### -End

End of date range (parseable date string).
Used with -Start for an absolute
range.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Re-query and overwrite weeks that already have a file in -Path.
Without it,
existing weekly files are left alone so an interrupted run can be resumed
without repeating completed work.

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

### -Path

Directory to write the weekly CLIXML files into.
Default: current directory.

```yaml
Type: System.String
DefaultValue: (Get-Location).Path
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResultLimit

Maximum records to retrieve per weekly chunk.
Stops at the next 5000-record
page boundary after the limit is reached.
A week that hits the limit gets a DATA
MISSING marker in its file; re-query it with -Week and a higher -ResultLimit.
Default: 50000.

```yaml
Type: System.Int32
DefaultValue: 50000
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
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
Used with -End for an absolute
range.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Week

One or more week numbers to query, as shown in the "Week N of M" console
label.
Weeks are numbered newest first, so week 1 is the most recent.
Only the
named weeks are queried, and each is re-queried even if its file already
exists, since a failed query still writes a file holding DATA MISSING markers.

The numbers only point at the same weeks if the range resolves the same way as
the original run, so retry with the same -Start / -End.
With -Days (or the
default), every week's number goes up by one each time a Sunday passes; check
the dates in the console label before trusting a retry.

```yaml
Type: System.Int32[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
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

### None. Writes one CLIXML file per queried week into -Path.

## NOTES

Version: 1.3.0
1.3.0 - Removed -ChunkDelaySeconds, which never took effect, and
-ThrottleDelaySeconds.
Retry backoff now uses the Get-IRTUnifiedAuditLog default.
A week cut short by -ResultLimit now carries a DATA MISSING marker.
1.2.0 - Added MeetingParticipantDetail, UserAccepted, and UserBlocked.
CallParticipantDetail moved to the domain group.
1.1.0 - Added -Week to re-query specific weeks.
No longer emits a FileInfo
object for each file written.


## RELATED LINKS

{{ Fill in the related links here }}
