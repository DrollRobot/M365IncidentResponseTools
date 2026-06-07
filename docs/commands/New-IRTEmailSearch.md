---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# New-IRTEmailSearch

## SYNOPSIS
Builds, creates, and starts an Exchange compliance search for email.

## SYNTAX

```
New-IRTEmailSearch [[-Start] <String>] [[-End] <String>] [[-From] <String[]>] [[-To] <String[]>]
 [[-Participants] <String[]>] [[-Recipients] <String[]>] [[-Subject] <String[]>] [[-Body] <String[]>]
 [[-AttachmentName] <String[]>] [[-Name] <String>] [[-ExchangeLocation] <String[]>] [-Force]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

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
```
New-IRTEmailSearch
Launches the interactive query builder.
```

### EXAMPLE 2
```
New-IRTEmailSearch -From 'sus@hacker.com' -Subject 'Payroll' -Start '5/28/26'
Builds a search for mail from a sender on or after the start date.
```

### EXAMPLE 3
```
New-IRTEmailSearch -Subject 'invoice' -Start '5/28/26' -End '5/29/26'
Builds a search over an absolute date range.
```

## PARAMETERS

### -Start
Absolute start of the Received date range (any Get-Date-parseable value).
Required.
Stored as UTC.
In interactive mode a relative duration shortcut is also offered.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -End
Absolute end of the Received date range (any Get-Date-parseable value).
Optional.
Stored as UTC.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -From
One or more sender addresses (KeyQL From).
Multiple values are combined with OR.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -To
One or more To recipients (KeyQL To).
Multiple values are combined with OR.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Participants
One or more parties in any of From/To/Cc/Bcc (KeyQL Participants).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Recipients
One or more recipients in any of To/Cc/Bcc (KeyQL Recipients).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Subject
One or more subject keywords (KeyQL Subject, partial match).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Body
One or more body keywords (KeyQL Body).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 8
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AttachmentName
One or more attachment file names (KeyQL AttachmentNames).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 9
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Name
Override the auto-generated search name.
By default the name is built from the
recipient and keyword criteria (dates excluded).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 10
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExchangeLocation
Mailboxes to search.
Default: All.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 11
Default value: All
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Overwrite an existing search of the same name without prompting.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### [pscustomobject] describing the search (including a Started flag). Also appended to
### $Global:IRT_EmailSearch.
## NOTES
Version: 1.1.0
1.1.0 - Create and start when connected to IPPS; when offline, save criteria and warn.

## RELATED LINKS
