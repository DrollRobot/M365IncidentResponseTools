---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: New-IRTInvestigationFolder
---

# New-IRTInvestigationFolder

## SYNOPSIS

Makes a new directory based on client and user info.

## SYNTAX

```
New-IRTInvestigationFolder [[-UserObject] <psobject[]>] [-Ticket <string>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## ALIASES

NewDir, NewFolder

## DESCRIPTION

Creates a timestamped investigation output folder in the current working directory.
The folder name is built from the tenant's default domain, an optional ticket number,
and the display names of the users under investigation.

If the Graph context is not available the function prompts for a client name
interactively.
Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1

New-IRTInvestigationFolder
Creates a folder like: investigation_contoso_jsmith_26-05-03_14-30

### EXAMPLE 2

New-IRTInvestigationFolder -Ticket 'INC-1234' -UserObject $User
Creates a folder that includes the ticket number and user name.

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -Ticket

Optional ticket or case number to include in the folder name.

```yaml
Type: System.String
DefaultValue: ''
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

### -UserObject

One or more user objects whose names are included in the folder name.
Falls back to
global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObjects
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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

### System.IO.DirectoryInfo

## NOTES

Version: 1.0.2


## RELATED LINKS

{{ Fill in the related links here }}
