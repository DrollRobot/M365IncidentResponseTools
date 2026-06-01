---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-IRTDomainController

## SYNOPSIS
Lists the names of all domain controllers in the current AD domain.

## SYNTAX

```
Find-IRTDomainController [<CommonParameters>]
```

## DESCRIPTION
Queries Active Directory for all domain controllers via Get-ADDomainController
and returns their computer names.
Requires the ActiveDirectory RSAT module and
a reachable domain controller; exits with an error if AD is unavailable.

## EXAMPLES

### EXAMPLE 1
```
Find-IRTDomainController
Returns the Name of every domain controller in the domain.
```

### EXAMPLE 2
```
$DCs = Find-IRTDomainController
Captures the list of DC names for use in a loop or downstream command.
```

## PARAMETERS

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
## NOTES

## RELATED LINKS
