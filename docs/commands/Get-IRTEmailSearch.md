---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTEmailSearch

## SYNOPSIS
Interactive manager for existing email searches: start, wait, view
results, purge matched email, or delete the search.

## SYNTAX

```
Get-IRTEmailSearch [[-Name] <String>] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

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
```
Get-IRTEmailSearch
Lists searches and launches the interactive action menu.
```

### EXAMPLE 2
```
Get-IRTEmailSearch -Name 'From:sus@hacker.com'
Skips the picker and opens the action menu for the named search.
```

## PARAMETERS

### -Name
Identity of an email search to act on directly, skipping the picker.

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

### None. Drives an interactive console workflow.
## NOTES
Version: 1.0.0

## RELATED LINKS
