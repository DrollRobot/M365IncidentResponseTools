---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTUser
---

# Show-IRTUser

## SYNOPSIS

Displays user properties.

## SYNTAX

```
Show-IRTUser [[-UserObject] <MicrosoftGraphUser[]>] [<CommonParameters>]
```

## ALIASES

Show-IRTUsers, Show-User, Show-Users, ShowIRTUser, ShowIRTUsers, ShowUser, ShowUsers

## DESCRIPTION

Retrieves the full Graph user object (all available properties) and displays it as a
formatted tree in the console.
Also updates $Global:IRT_UserObjects with the enriched
object so downstream playbook steps receive complete data.

Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1

Show-IRTUser
Displays info for the user stored in the global session.

### EXAMPLE 2

Show-IRTUser -UserObject $User
Displays info for a specific user object.

## PARAMETERS

### -UserObject

One or more Microsoft Graph user objects to display.
Falls back to global session
objects if omitted.

```yaml
Type: Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]
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

### None. Output is written to the console.

## NOTES

Version: 1.2.0
1.2.0 - Switched to Format-Tree, Show-GraphUserTree


## RELATED LINKS

{{ Fill in the related links here }}
