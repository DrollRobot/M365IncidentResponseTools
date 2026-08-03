---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Import-IRTConfig
---

# Import-IRTConfig

## SYNOPSIS

Loads the current IRT configuration.

## SYNTAX

```
Import-IRTConfig [-Force] [<CommonParameters>]
```

## ALIASES

ImportConfig, IRTConfig

## DESCRIPTION

Reads the user configuration from $env:APPDATA\<ModuleName>\config.json.
If the file does not exist, copies the template from the module root and loads it.
The parsed config is cached in $Global:IRT_Config.

## EXAMPLES

## PARAMETERS

### -Force

Re-read the config file even if $Global:IRT_Config is already populated.

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

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
