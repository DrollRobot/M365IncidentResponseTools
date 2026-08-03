---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTAdOu
---

# Find-IRTAdOu

## SYNOPSIS

Makes finding specific OUs easier.

## SYNTAX

```
Find-IRTAdOu [-Search] <string> [-Script] [<CommonParameters>]
```

## ALIASES

Find-IRTAdOus, Find-AdOu, Find-AdOus, FindIRTAdOu, FindIRTAdOus, FindAdOu, FindAdOus

## DESCRIPTION

Searches all Active Directory Organizational Units for entries matching the -Search
string.
The search is applied against Name (regex), CanonicalName (exact), and
DistinguishedName (exact).
If exactly one match is found it is stored in
$Global:OuObject and displayed; multiple or zero results produce a warning.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTAdOu 'Workstations'
```
Finds all OUs with 'Workstations' in their name and sets $Global:OuObject if exactly one match.

### EXAMPLE 2

```powershell
$Ou = Find-IRTAdOu -Search 'contoso.com/Workstations' -Script
```
Returns the OU object directly for use in a script.

## PARAMETERS

### -Script

Return the matching OU object directly instead of printing it and setting the global
variable.
Useful when calling from scripts.

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

### -Search

String to search for.
Tested as a regex against Name and as an exact match against
CanonicalName and DistinguishedName.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

### None by default (sets $Global:OuObject and writes to console).
Microsoft.ActiveDirectory.Management.ADOrganizationalUnit when -Script is used.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
