---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Start-IRTPlaybook

## SYNOPSIS
Runs multiple functions to assist in investigating a user's activity.

## SYNTAX

```
Start-IRTPlaybook [[-UserObject] <PSObject[]>] [-Ticket <String>] [-NoFolder] [-NewTab] [-MaxRunspaces <Int32>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
The incident response playbook is the primary investigation entry point.
It accepts one
or more Entra ID user objects and launches up to 13 data-collection steps in parallel
using a runspace pool, then writes each result set to the investigation folder.

Steps include: license report, user info, app assignments, mailbox details, admin roles,
risky applications, MFA state, message trace, inbox rules, Entra audit log, sign-in logs,
non-interactive sign-in logs, and Unified Audit Log (UAL).

If -UserObject is omitted the function falls back to $Global:IRT_UserObjects populated
by Find-GraphUser or Get-IRTUserObject.
A Graph connection is required; Exchange Online
is required for mailbox and inbox rule steps.

## EXAMPLES

### EXAMPLE 1
```
Find-GraphUser 'jsmith@contoso.com'
Start-IRTPlaybook
Look up a user, then run the full playbook using the global user object.
```

### EXAMPLE 2
```
Start-IRTPlaybook -UserObject $User -Ticket 'INC-1234'
Run the playbook for an already-resolved user object and name the output folder INC-1234.
```

### EXAMPLE 3
```
Start-IRTPlaybook -UserObject $User -NoFolder -MaxRunspaces 5
Run without writing files, using a limited runspace pool.
```

## PARAMETERS

### -UserObject
One or more Entra ID user objects to investigate.
Accepts the objects returned by
Find-GraphUser or Get-IRTUserObject.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Ticket
Ticket or case number string.
Used to name the investigation folder when -NoFolder is
not specified.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoFolder
Skip creating an investigation output folder.
Results are still displayed in the console
but not written to disk.

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

### -NewTab
{{ Fill NewTab Description }}

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

### -MaxRunspaces
Maximum number of parallel runspaces.
Default: 15.
Reduce if the host machine has
limited memory or Graph throttling is a concern.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 15
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

### None. All output is written to the investigation folder or displayed in the console.
## NOTES
Version: 2.2.0
2.2.0 - Added license report, added error handling to close runspaces when script exits.
2.1.0 - Added ability to run parallel exchange runspaces using exchange access token.
2.0.0 - Added ability to run mulitple operations in parallel using runspaces.

## RELATED LINKS
