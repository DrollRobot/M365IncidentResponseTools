---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: New-IRTEmailSearch
---

# New-IRTEmailSearch

## SYNOPSIS

Builds, creates, and starts an email search.

## SYNTAX

```
New-IRTEmailSearch [[-Start] <string>] [[-End] <string>] [[-From] <string[]>] [[-To] <string[]>]
 [[-Participants] <string[]>] [[-Recipients] <string[]>] [[-Subject] <string[]>]
 [[-Body] <string[]>] [[-AttachmentName] <string[]>] [[-Name] <string>] [[-NamePrefix] <string>]
 [[-ExchangeLocation] <string[]>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Assembles a Keyword Query Language (KeyQL) ContentMatchQuery from recipient, keyword,
and date criteria.

Two modes:
  - Parameter mode: supply any of the criteria parameters and the query is built
    non-interactively.
  - Interactive mode: call with no criteria parameters to launch a console builder
    that shows the live query and lets you edit each field before accepting.

On creation, a result object is appended to $Global:IRT_EmailSearch containing the
criteria, the generated name, the built query, and the New-ComplianceSearch return
object.

## EXAMPLES

### EXAMPLE 1

```powershell
New-IRTEmailSearch
```
Launches the interactive query builder.

### EXAMPLE 2

```powershell
New-IRTEmailSearch -From 'sus@hacker.com' -Subject 'Payroll' -Start '5/28/26'
```
Builds a search for mail from a sender on or after the start date.

### EXAMPLE 3

```powershell
New-IRTEmailSearch -Subject 'invoice' -Start '5/28/26' -End '5/29/26'
```
Builds a search over an absolute date range.

## PARAMETERS

### -AttachmentName

One or more attachment file names (KeyQL AttachmentNames).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Body

One or more body keywords (KeyQL Body).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
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

### -End

Absolute end of the Received date range (any Get-Date-parseable value).
Optional.
Stored as UTC.

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

### -ExchangeLocation

Mailboxes to search.
Default: All.

```yaml
Type: System.String[]
DefaultValue: All
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

On a name collision, automatically use the next available 'Name N' instead of
prompting.
Never overwrites an existing search.

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

### -From

One or more sender addresses (KeyQL From).
Multiple values are combined with OR.

```yaml
Type: System.String[]
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

### -Name

Override the auto-generated search name.
By default the name is built from the
recipient and keyword criteria (dates excluded).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NamePrefix

String prepended to the search name (whether auto-generated or supplied via -Name).
Defaults to IRT_Config.EmailSearchNamePrefix ('IRT: ').
The prefix is not re-applied
if the resolved name already starts with it.
Pass '' to omit the prefix.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.EmailSearchNamePrefix
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Participants

One or more parties in any of From/To/Cc/Bcc (KeyQL Participants).

```yaml
Type: System.String[]
DefaultValue: ''
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

### -Recipients

One or more recipients in any of To/Cc/Bcc (KeyQL Recipients).

```yaml
Type: System.String[]
DefaultValue: ''
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

Absolute start of the Received date range (any Get-Date-parseable value).
Required.
Stored as UTC.
In interactive mode a relative duration shortcut is also offered.

```yaml
Type: System.String
DefaultValue: ''
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

### -Subject

One or more subject keywords (KeyQL Subject, partial match).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -To

One or more To recipients (KeyQL To).
Multiple values are combined with OR.

```yaml
Type: System.String[]
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### [pscustomobject] describing the search (including a Started flag). Also appended to
$Global:IRT_EmailSearch.

### System.Management.Automation.PSObject

## NOTES

Version: 1.2.0
1.2.0 - Prepend a configurable name prefix (IRT_Config.EmailSearchNamePrefix, default 'IRT: ').
1.1.0 - Create and start when connected to IPPS; when offline, save criteria and warn.


## RELATED LINKS

{{ Fill in the related links here }}
