---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Disable-IRTAdUser
---

# Disable-IRTAdUser

## SYNOPSIS

Disable on-premises AD user account(s).

## SYNTAX

```
Disable-IRTAdUser [[-UserObject] <psobject[]>] [<CommonParameters>]
```

## ALIASES

Disable-IRTAdUsers, Disable-AdUser, Disable-AdUsers, DisableIRTAdUser, DisableIRTAdUsers, DisableAdUser, DisableAdUsers, Lock-IRTAdUser, Lock-IRTAdUsers, Lock-AdUser, Lock-AdUsers, LockIRTAdUser, LockIRTAdUsers, LockAdUser, LockAdUsers

## DESCRIPTION

Thin wrapper around Set-AdUserEnabled that sets Enabled = $false.
Disables one or
more AD user accounts, re-fetches each account to confirm the change, then triggers
AD replication and an Azure AD delta sync if the relevant services are available.

Falls back to $Global:UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1

```powershell
Disable-IRTAdUser
```
Disables the user(s) in the global session.

### EXAMPLE 2

```powershell
Disable-IRTAdUser -UserObject $AdUser
```
Disables a specific user.

## PARAMETERS

### -UserObject

One or more AD user objects to disable.
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

### None. Status is written to the console.

## NOTES

Version: 2.0.0


## RELATED LINKS

{{ Fill in the related links here }}
