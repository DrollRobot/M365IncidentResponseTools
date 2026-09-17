---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Receive-IRTGraphUAL
---

# Receive-IRTGraphUAL

## SYNOPSIS

Downloads the records from finished audit search jobs and exports them.

## SYNTAX

### Group (Default)

```
Receive-IRTGraphUAL [-Group] <string[]> [-Excel <bool>] [-Xml <bool>] [-Cached] [-PassThru]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

### Id

```
Receive-IRTGraphUAL -Id <string[]> [-Excel <bool>] [-Xml <bool>] [-Cached] [-PassThru] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Retrieves every record from one or more finished Graph audit search jobs, merges them,
and hands the result to Show-IRTUnifiedAuditLog so the output is the same workbook
Get-IRTUnifiedAuditLog produces.

Records are deduplicated by id and sorted newest first.
The API returns each record
once per job and does not sort them, and a group normally contains overlapping jobs,
such as a keyword search on a user principal name alongside one on their object id, so
both steps matter.

Jobs that failed have a DATA MISSING marker inserted in their place, so an incomplete
export is visible in the workbook rather than looking like a quiet period.

Finished searches cannot be removed from the tenant.
The API has no delete, so they
stay listed until Purview expires them after about thirty days.
To make that
manageable, the exported file is named after the search that produced it, carrying the
same creation stamp and group id, so a file on disk can be matched by eye to a search
in the listing.
Downloading the same group twice overwrites the same file rather than
producing a second one.

## EXAMPLES

### EXAMPLE 1

```powershell
Receive-IRTGraphUAL -Group '3f9a1c2b'
```
Downloads a group and exports the workbook.

### EXAMPLE 2

```powershell
$Records = Receive-IRTGraphUAL -Group '3f9a1c2b' -Excel $false -PassThru
```
Returns the records in memory without writing files.

## PARAMETERS

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

### -Excel

Export to an Excel workbook.
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

### -Group

One or more group ids to download, as returned by Start-IRTGraphUAL.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- GroupId
ParameterSets:
- Name: Group
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Id

One or more individual job ids, for collecting a single job rather than a group.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- JobId
ParameterSets:
- Name: Id
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Emit the record collection instead of only exporting it.

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

Export the raw records to XML as well.
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

### None by default. With -PassThru

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

## NOTES

Version: 1.1.0
1.1.0 - Removed -ResultLimit.
It only existed because of Search-UnifiedAuditLog's
paging model; a Graph download ends on its own, and every record is kept.


## RELATED LINKS

{{ Fill in the related links here }}
