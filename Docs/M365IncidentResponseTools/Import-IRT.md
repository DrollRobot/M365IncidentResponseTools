---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Import-IRT
---

# Import-IRT

## SYNOPSIS

Preloads the M365IncidentResponseTools module into the current session.

## SYNTAX

```
Import-IRT [<CommonParameters>]
```

## ALIASES

ImportIRT, LoadIRT, IRT

## DESCRIPTION

A lightweight stub whose sole purpose is to trigger PowerShell's automatic
module loading.
Calling this function forces the full module to be imported --
dot-sourcing all domain scripts and initializing shared state -- so that
subsequent commands respond instantly instead of incurring the first-call
import penalty.

## EXAMPLES

### EXAMPLE 1

```powershell
Import-IRT
```

Loads M365IncidentResponseTools into the current session.
Run this once at
the start of a session to warm up the module before using any IRT commands.

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Void

## NOTES

The function body is intentionally empty.
The import side-effect is produced
entirely by PowerShell's automatic module loading when any exported function
from the module is invoked.


## RELATED LINKS

{{ Fill in the related links here }}
