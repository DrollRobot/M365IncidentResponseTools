---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-AllDomainController

## SYNOPSIS
Lists the names of all domain controllers in the current AD domain.

## SYNTAX

```
Find-AllDomainController
```

## DESCRIPTION
Queries Active Directory for all domain controllers via Get-ADDomainController
and returns their computer names.
Requires the ActiveDirectory RSAT module and
a reachable domain controller; exits with an error if AD is unavailable.

## EXAMPLES

### EXAMPLE 1
```
Find-AllDomainController
Returns the Name of every domain controller in the domain.
```

### EXAMPLE 2
```
$DCs = Find-AllDomainController
Captures the list of DC names for use in a loop or downstream command.
```

## PARAMETERS

## INPUTS

## OUTPUTS

### Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
## NOTES

## RELATED LINKS
