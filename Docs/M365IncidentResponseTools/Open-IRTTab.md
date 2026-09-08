---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Open-IRTTab
---

# Open-IRTTab

## SYNOPSIS

Opens a new Windows Terminal tab and loads the module.

## SYNTAX

```
Open-IRTTab [[-Title] <string>] [-Quiet] [<CommonParameters>]
```

## ALIASES

OpenIRTTab, Open-Tab, OpenTab, NewIRTTab, New-Tab, NewTab, IRTTab

## DESCRIPTION

Opens a new tab in the current Windows Terminal window and imports
M365IncidentResponseTools.
If an active IRT session exists, also calls
Connect-IRT to connect to the same tenant.

Must be run from within Windows Terminal; detected via the WT_SESSION
environment variable set by Windows Terminal in every hosted session.

## EXAMPLES

### EXAMPLE 1

```powershell
Open-IRTTab
```
Opens a new tab. Connects to the current tenant if a session is active.

### EXAMPLE 2

```powershell
Open-IRTTab -Quiet
```
Opens a new tab if in Windows Terminal; silently does nothing otherwise.

### EXAMPLE 3

```powershell
Open-IRTTab -Title '[IRT] Secondary'
```
Opens a new tab with a custom title.

## PARAMETERS

### -Quiet

When set, silently returns without error if the current console is not
Windows Terminal.
Useful when calling from a profile or script that may
run in multiple console hosts.

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

### -Title

Title for the new terminal tab.
Defaults to '[IRT]'.

```yaml
Type: System.String
DefaultValue: '[IRT]'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
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

### System.Void

## NOTES

Version: 1.1.0
1.1.0 - Requires Windows Terminal host.
Opens without connecting when no
        active session exists.


## RELATED LINKS

{{ Fill in the related links here }}
