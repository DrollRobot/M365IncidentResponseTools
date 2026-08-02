---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Test-IRTConnection
---

# Test-IRTConnection

## SYNOPSIS

Shows which IRT services are connected and to which tenant.

## SYNTAX

```
Test-IRTConnection [-Quiet] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Checks the current Graph and Exchange Online connections and displays
the connected domain for each.
Useful for confirming which tenant you
are working against before running incident response commands.

## EXAMPLES

### EXAMPLE 1

Test-IRTConnection
Displays connection status for Graph and Exchange.

### EXAMPLE 2

if (-not (Test-IRTConnection -Quiet)) { throw 'Not fully connected.' }
Silently asserts that both services are connected to the same tenant.

## PARAMETERS

### -Quiet

Returns $true if both Graph and Exchange are connected to the same
tenant (matched by TenantId), $false otherwise.
Suppresses all output.

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

### System.Boolean

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
