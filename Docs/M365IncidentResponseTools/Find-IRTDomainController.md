---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTDomainController
---

# Find-IRTDomainController

## SYNOPSIS

Lists the names of all domain controllers in the current AD domain.

## SYNTAX

```
Find-IRTDomainController
```

## ALIASES

FindIRTDomainController, Find-IRTDomainControllers, FindIRTDomainControllers, Find-DomainController, FindDomainController, Find-DomainControllers, FindDomainControllers, Find-DC, FindDC, Find-DCs, FindDCs, DC, DCs

## DESCRIPTION

Queries Active Directory for all domain controllers via Get-ADDomainController
and returns their computer names.
Requires the ActiveDirectory RSAT module and
a reachable domain controller; exits with an error if AD is unavailable.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTDomainController
```
Returns the Name of every domain controller in the domain.

### EXAMPLE 2

```powershell
$DCs = Find-IRTDomainController
```
Captures the list of DC names for use in a loop or downstream command.

## PARAMETERS

## INPUTS

## OUTPUTS

### Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
