---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTAdOus
---

# Show-IRTAdOus

## SYNOPSIS

Shows a list of all OUs with a count of users and devices.

## SYNTAX

```
Show-IRTAdOus [<CommonParameters>]
```

## ALIASES

Show-IRTAdOu, Show-AdOu, Show-AdOus, ShowIRTAdOu, ShowIRTAdOus, ShowAdOu, ShowAdOus, AdOus

## DESCRIPTION

Lists all Organizational Units in the current AD domain, sorted by CanonicalName.
For each OU, counts users and computers directly inside it (OneLevel scope) and
displays the results in a formatted table.

Output objects use the custom type 'ShowAdOus' with a DefaultDisplayPropertySet
so Format-Table shows CanonicalName, Name, Users, Computers, and DistinguishedName
by default.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTAdOus
```
Lists all OUs with user and computer counts.

### EXAMPLE 2

```powershell
Show-IRTAdOus | Where-Object { $_.Users -gt 0 }
```
Returns only OUs that contain at least one user.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### PSCustomObject[] (type: ShowAdOus)

## NOTES

Version: 1.0.1


## RELATED LINKS

{{ Fill in the related links here }}
