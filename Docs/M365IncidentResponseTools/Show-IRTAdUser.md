---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTAdUser
---

# Show-IRTAdUser

## SYNOPSIS

Displays AD user properties.

## SYNTAX

```
Show-IRTAdUser [[-UserObjects] <psobject[]>] [<CommonParameters>]
```

## ALIASES

Show-IRTAdUsers, Show-AdUser, Show-AdUsers, ShowIRTAdUser, ShowIRTAdUsers, ShowAdUser, ShowAdUsers

## DESCRIPTION

Retrieves all properties of an on-premises AD user object, converts every DateTime
value to local time, and displays the result with Format-Tree.
Falls back to
$Global:IRT_UserObject (via Get-AdGlobalUserObject) if no -UserObjects is passed.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTAdUser
```
Displays info for the user(s) in the global session.

### EXAMPLE 2

```powershell
Show-IRTAdUser -UserObjects $AdUser
```
Displays info for a specific AD user object.

## PARAMETERS

### -UserObjects

One or more AD user objects to display.
Falls back to global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObject
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
1.2.0 - Switched to Format-Tree with dynamic DateTime conversion.
1.1.2 - Added pwdLastSet


## RELATED LINKS

{{ Fill in the related links here }}
