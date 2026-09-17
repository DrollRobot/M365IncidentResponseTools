---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTAdAdminUser
---

# Get-IRTAdAdminUser

## SYNOPSIS

Displays a list of admin users.

## SYNTAX

```
Get-IRTAdAdminUser [-Csv] [<CommonParameters>]
```

## ALIASES

Get-IRTAdAdminUsers, Get-AdAdminUser, Get-AdAdminUsers, GetIRTAdAdminUser, GetIRTAdAdminUsers, GetAdAdminUser, GetAdAdminUsers, GetAdAdmins, AdAdmins

## DESCRIPTION

Retrieves all Active Directory users where AdminCount equals 1 (the standard AD
attribute set by SDProp for accounts that have been members of privileged groups).
Results are sorted by Enabled status then LastLogonDate descending, and include each
user's group memberships.

Use -Csv to export the results to a CSV file in C:\Temp.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTAdAdminUser
```
Displays all AdminCount=1 users in a formatted table.

### EXAMPLE 2

```powershell
Get-IRTAdAdminUser -Csv
```
Exports the list to AdAdminUsers_<domain>_<date>.csv in C:\Temp.

## PARAMETERS

### -Csv

Export results to a CSV file instead of displaying them in the console.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None (console table) by default.
CSV file when -Csv is used.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
