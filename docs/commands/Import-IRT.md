---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Import-IRT

## SYNOPSIS
Preloads the M365IncidentResponseTools module into the current session.

## SYNTAX

```
Import-IRT [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
A lightweight stub whose sole purpose is to trigger PowerShell's automatic
module loading.
Calling this function forces the full module to be imported --
dot-sourcing all domain scripts and initializing shared state -- so that
subsequent commands respond instantly instead of incurring the first-call
import penalty.

## EXAMPLES

### EXAMPLE 1
```
Import-IRT
```

Loads M365IncidentResponseTools into the current session.
Run this once at
the start of a session to warm up the module before using any IRT commands.

## PARAMETERS

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None
## NOTES
The function body is intentionally empty.
The import side-effect is produced
entirely by PowerShell's automatic module loading when any exported function
from the module is invoked.

## RELATED LINKS
