---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Start-IRTPlaybook
---

# Start-IRTPlaybook

## SYNOPSIS

Runs multiple functions to assist in investigating a user's activity.

## SYNTAX

```
Start-IRTPlaybook [[-UserObject] <psobject[]>] [-Ticket <string>] [-NoFolder] [-NewTab]
 [-MaxRunspaces <int>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

Playbook

## DESCRIPTION

The incident response playbook is the primary investigation entry point.
It accepts one or more Entra ID user objects and launches ~15 investigation steps in
parallel, then saves output files to the investigation folder.

Steps include: license report, user info, app assignments, mailbox details, admin roles,
risky applications, MFA state, message trace, inbox rules, Entra audit log, sign-in logs,
non-interactive sign-in logs, Entra registered/joined devices, and Unified Audit Log (UAL).

If -UserObject is omitted the function falls back to $Global:IRT_UserObjects populated
by Find-User.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-GraphUser 'jsmith@contoso.com'
Start-IRTPlaybook
```
Look up a user, then run the full playbook using the global user object.

### EXAMPLE 2

```powershell
Start-IRTPlaybook -UserObject $User -Ticket 'INC-1234'
```
Run the playbook for an already-resolved user object and name the output folder INC-1234.

### EXAMPLE 3

```powershell
Start-IRTPlaybook -UserObject $User -NoFolder -MaxRunspaces 5
```
Run without writing files, using a limited runspace pool.

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

### -MaxRunspaces

Maximum number of parallel runspaces.
Default: 15.
Reduce if the host machine has
limited memory or Graph throttling is a concern.

```yaml
Type: System.Int32
DefaultValue: 15
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

### -NewTab

{{ Fill NewTab Description }}

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

### -NoFolder

Skip creating an investigation output folder.
Results are still displayed in the console
but not written to disk.

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

### -Ticket

Ticket or case number string.
Used to name the investigation folder when -NoFolder is
not specified.

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

### -UserObject

One or more Entra ID user objects to investigate.
Accepts the objects returned by
Find-GraphUser or Get-GlobalUserObject.
Falls back to global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObjects
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

### None. All output is written to the investigation folder or displayed in the console.

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
