---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTEmailSearch
---

# Get-IRTEmailSearch

## SYNOPSIS

Interactive manager for existing email searches: start, wait, view
results, purge matched email, or delete the search.

## SYNTAX

```
Get-IRTEmailSearch [[-Name] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Lists the tenant's email searches and lets you pick one, then loops an action
menu against it:

  - Start         Starts a not-yet-started search (Start-ComplianceSearch).
  - Wait          Polls until the search completes, then plays a sound.
  - Results       Shows the per-mailbox hit summary (mailbox, item count, size) from
                  the search's SearchStatistics, with an Excel export.
This uses only
                  ordinary Compliance Search permissions - no eDiscovery Preview role -
                  so only aggregate data is available, not per-message detail or folder.
  - Purge email   Soft- or hard-deletes the matched email (New-ComplianceSearchAction
                  -Purge).
Exchange purges at most ~10 items per mailbox per action.
  - Delete search Removes the email search definition (Remove-ComplianceSearch).

Requires a live IPPS (Security & Compliance) connection.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTEmailSearch
```
Lists searches and launches the interactive action menu.

### EXAMPLE 2

```powershell
Get-IRTEmailSearch -Name 'From:sus@hacker.com'
```
Skips the picker and opens the action menu for the named search.

## PARAMETERS

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

### -Name

Identity of an email search to act on directly, skipping the picker.

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

### None. Drives an interactive console workflow.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
