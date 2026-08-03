---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Copy-IRTFunction
---

# Copy-IRTFunction

## SYNOPSIS

Copies IRT helper functions to the clipboard for use on remote machines.

## SYNTAX

```
Copy-IRTFunction [[-FunctionName] <string[]>] [<CommonParameters>]
```

## ALIASES

Copy-IRTFunctions, CopyIRTFunctions, CopyIRTFunction, IRTFunction, IRTFunctions

## DESCRIPTION

Retrieves function definitions from the loaded module in memory and
concatenates them into a single pasteable script, then sends the result
to the clipboard via Set-Clipboard.

A bootstrap block that initialises $Global:IRT_Config (using the current
session's color preferences as defaults) is prepended automatically.

The default set includes:
  - Write-IRT, Get-RandomPassword, Get-YesNo
  - All On-Prem AD functions

Use -FunctionName to include additional functions beyond the default set.

## EXAMPLES

### EXAMPLE 1

```powershell
Copy-IRTFunction
```

Copies the default set of IRT helper functions to the clipboard.

### EXAMPLE 2

```powershell
Copy-IRTFunction -FunctionName 'Get-IRTMessageTrace'
```

Copies the default set plus Get-IRTMessageTrace.

### EXAMPLE 3

```powershell
'Get-IRTInboxRule', 'Get-IRTMessageTrace' | Copy-IRTFunction
```

Copies the default set plus both named functions via the pipeline.

## PARAMETERS

### -FunctionName

One or more additional function names to include beyond the default set.
Accepts pipeline input.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Name
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
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

### System.String[]

{{ Fill in the Description }}

## OUTPUTS

### None. Output is sent to the clipboard.

## NOTES

Version: 2.0.0


## RELATED LINKS

{{ Fill in the related links here }}
