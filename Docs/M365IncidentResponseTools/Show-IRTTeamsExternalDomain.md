---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTTeamsExternalDomain
---

# Show-IRTTeamsExternalDomain

## SYNOPSIS

Summarises the outside domains in Get-IRTTeamsExternalDomain output as a spreadsheet,
with a record count and last-seen date for each.

## SYNTAX

```
Show-IRTTeamsExternalDomain [[-Path] <string>] [[-TenantIdChunkSize] <int>] [[-Open] <bool>]
 [[-TableStyle] <string>] [[-Font] <string>] [<CommonParameters>]
```

## ALIASES

ShowTeamsExtDomain, ShowTeamsExtDomains

## DESCRIPTION

Reads every .xml file in -Path, which is expected to hold the weekly files written by
Get-IRTTeamsExternalDomain, and writes one worksheet listing each outside
organisation that tenant users had Teams contact with:

    Domain           - the organisation's domain, or its tenant ID when no domain
                       could be found for it
    Count            - how many audit records name it
    LastDate         - the most recent of those records, in local time
    allow_TRUE_FALSE - FALSE on every row.
A reviewer sets it to TRUE for each
                       organisation that should be allowed.
The cells are native
                       Excel booleans.

Each record is handed to a dedicated parser for its operation (for example
Get-MessageSentParty for MessageSent), which returns every domain and tenant ID the
record names.
Records from operations with no parser are skipped with a warning, so
other exports in the same folder do no harm.
A Write-Progress bar tracks the files as
they are read.

The investigated tenant's own parties are removed.
Its tenant ID is each record's
OrganizationId, and its domains are learned from the records themselves: any domain
paired with that tenant ID (a user's UPN next to their OrganizationId, or a SIP
domain entry) belongs to it.

Many records name a tenant ID with no domain, such as reactions and accepted or
blocked external users.
Those tenant IDs are resolved to the tenant's default domain
with Get-IRTTenantOwner, which needs a Graph connection.
When there is no connection,
or a lookup fails, a warning is shown and the tenant ID is listed in place of the
domain.
A tenant ID that the same record already pairs with a domain is not looked
up.

Lookups run in chunks of -TenantIdChunkSize tenant IDs, tracked by a Write-Progress
bar.
A chunk that fails leaves only its own tenant IDs unresolved.

Counting:
    - A record adds one to each organisation it names, however often it names it.
    - A record found in more than one file is counted once.
    - DATA MISSING markers from Get-IRTUnifiedAuditLog are reported, since they mean
      the counts and dates are incomplete.

Guest accounts are counted under their home domain, decoded from the #EXT# guest UPN.

The workbook is written into -Path as TeamsExternalDomainSummary_<date>.xlsx.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTTeamsExternalDomain
```
Summarises the .xml files in the current directory and opens the workbook.

### EXAMPLE 2

```powershell
Get-IRTTeamsExternalDomain -Days 90 -Path 'C:\Cases\Contoso'
Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso'
```
Pulls 90 days of Teams external contact records, then summarises them.

### EXAMPLE 3

```powershell
Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso' -TenantIdChunkSize 25
```
Looks up tenant IDs 25 at a time, for when larger lookups fail.

### EXAMPLE 4

```powershell
Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso' -Open $false
```
Writes the workbook without opening it.

## PARAMETERS

### -Font

Worksheet font.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelFont
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

### -Open

Open the workbook after export.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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

### -Path

Folder containing the .xml files to read.
Subfolders are not searched.
Default: current directory.

```yaml
Type: System.String
DefaultValue: (Get-Location).Path
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

### -TableStyle

Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelTableStyle
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

### -TenantIdChunkSize

Number of tenant IDs sent to Get-IRTTenantOwner per call.
A failed call leaves only
its own chunk unresolved, so lower this if lookups fail in bulk.
Default: 100.

```yaml
Type: System.Int32
DefaultValue: 100
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Writes an Excel workbook into -Path.

## NOTES

Version: 1.1.1
1.1.1 - Progress is shown with Write-Progress instead of a console line for each file
and each lookup chunk.
1.1.0 - Tenant IDs are looked up in chunks of -TenantIdChunkSize, so one failed
lookup no longer loses every tenant ID.
Progress is shown per file and per chunk.


## RELATED LINKS

{{ Fill in the related links here }}
