---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Wait-IRTGraphUAL
---

# Wait-IRTGraphUAL

## SYNOPSIS

Waits for audit search jobs to finish, then downloads them.

## SYNTAX

```
Wait-IRTGraphUAL [[-Group] <string[]>] [[-PollSeconds] <int>] [[-TimeoutMinutes] <int>]
 [[-Audio] <bool>] [[-Excel] <bool>] [[-Xml] <bool>] [-All] [-NoReceive] [-Cached]
 [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Polls the Graph audit search jobs until every focused group has finished, then hands
each one to Receive-IRTGraphUAL and plays a sound.

The service schedules these jobs in batches, so expect roughly 35 minutes regardless
of how large the search is.
Polling is deliberately unhurried for the same reason:
every 30 seconds for the first five minutes, then every minute.

Ctrl+C is safe.
The jobs run server-side and keep going, and re-running this command
picks them back up.
Nothing is lost by stopping the wait.

Each tick reprints the status of every group being watched.
Groups that are not
focused are still listed, dimmed, so a long wait does not hide other work in progress.

## EXAMPLES

### EXAMPLE 1

```powershell
Wait-IRTGraphUAL
```
Waits for every outstanding search, then downloads them.

### EXAMPLE 2

```powershell
Wait-IRTGraphUAL -Group '3f9a1c2b'
```
Waits for one group.

### EXAMPLE 3

```powershell
Wait-IRTGraphUAL -All
```
Also lists searches created outside this module, for context.

### EXAMPLE 4

```powershell
Wait-IRTGraphUAL -TimeoutMinutes 60 -Audio $false
```
Waits up to an hour without a completion sound.

## PARAMETERS

### -All

Also list audit searches this module did not create, such as ones made in the Purview
portal.
They appear in the status table for context but cannot be waited on or
downloaded, since there is no way to know how to rebuild their output.

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

### -Audio

Play a sound when the wait ends.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Group

One or more group ids to wait for.
With none given, a single outstanding search is
followed automatically and several produce a menu to choose from, including an option
to follow all of them.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- GroupId
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

### -NoReceive

Report completion without downloading anything.

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

### -PollSeconds

Override the poll interval, in seconds.
By default the interval starts at 30 seconds
and rises to 60 after the first five minutes.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -TimeoutMinutes

Give up waiting after this many minutes.
Zero, the default, waits indefinitely.
Whatever has finished is still downloaded.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -Xml

Export raw records to XML.
Defaults to IRT_Config.ExportXml.

```yaml
Type: System.Boolean
DefaultValue: $Global:IRT_Config.ExportXml
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Results are exported by Receive-IRTGraphUAL.

## NOTES

Version: 1.1.0
1.1.0 - Removed -ResultLimit, along with the download cap it passed on.


## RELATED LINKS

{{ Fill in the related links here }}
