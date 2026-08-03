---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTMailbox
---

# Show-IRTMailbox

## SYNOPSIS

Displays mailbox properties.

## SYNTAX

```
Show-IRTMailbox [[-UserObject] <psobject[]>] [-Cached] [<CommonParameters>]
```

## ALIASES

ShowMailbox

## DESCRIPTION

Retrieves Exchange Online mailbox configuration and permissions for one or more users
and displays the results in the console.
Includes quota settings, forwarding rules,
litigation hold status, and current mailbox permissions.

Falls back to $Global:IRT_UserObjects if no -UserObject is passed.
Requires an active
Exchange Online connection.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTMailbox
```
Displays mailbox details for the user in the global session.

### EXAMPLE 2

```powershell
Show-IRTMailbox -UserObject $User
```
Displays mailbox details for a specific user.

## PARAMETERS

### -Cached

Use pre-cached Exchange data where available instead of making new API calls.

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

### -UserObject

One or more user objects to query.
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Results are displayed in the console.

## NOTES

Version: 1.1.0


## RELATED LINKS

{{ Fill in the related links here }}
