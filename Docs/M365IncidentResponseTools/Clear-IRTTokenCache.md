---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Clear-IRTTokenCache
---

# Clear-IRTTokenCache

## SYNOPSIS

Removes the persistent IRT MSAL token cache and signs out all in-process accounts.

## SYNTAX

```
Clear-IRTTokenCache [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

ClearIRTTokenCache

## DESCRIPTION

When the persistent token cache is enabled (config: EnableTokenCache),
MSAL writes refresh tokens to disk so the user is not re-prompted in every
new PowerShell session.
This command:

  1.
Removes every account from each PublicClientApplication currently held
     in $Global:IRT_Session.Apps.
Removal also strips their tokens from the
     on-disk cache via the registered cache helper.
  2.
Clears the sticky per-client account memory so the next acquisition
     starts fresh.
  3.
Deletes the on-disk cache file as a belt-and-suspenders measure in
     case no MSAL app is currently registered against it.

Use this after a credential rotation, when sharing a workstation, or to
force the next Connect-IRT to prompt interactively.

## EXAMPLES

### EXAMPLE 1

```powershell
Clear-IRTTokenCache
```
Wipes the cache. The next Connect-IRT call will require interactive sign-in.

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

### None.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
