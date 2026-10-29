---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/29/2026
PlatyPS schema version: 2024-05-01
title: Disable-IRTServicePrincipal
---

# Disable-IRTServicePrincipal

## SYNOPSIS

Disables service principals (enterprise apps), so Entra stops issuing tokens for them.

## SYNTAX

```
Disable-IRTServicePrincipal [[-ServicePrincipalObject] <psobject[]>] [<CommonParameters>]
```

## ALIASES

Disable-IRTServicePrincipals, Disable-ServicePrincipal, Disable-ServicePrincipals, DisableIRTServicePrincipal, DisableIRTServicePrincipals, DisableServicePrincipal, DisableServicePrincipals, Disable-IRTSP, Disable-IRTSPs, Disable-SP, Disable-SPs, DisableIRTSP, DisableIRTSPs, DisableSP, DisableSPs, Disable-IRTEnterpriseApplication, Disable-IRTEnterpriseApplications, Disable-EnterpriseApplication, Disable-EnterpriseApplications, DisableIRTEnterpriseApplication, DisableIRTEnterpriseApplications, DisableEnterpriseApplication, DisableEnterpriseApplications

## DESCRIPTION

Sets accountEnabled to false on each service principal.
Users can no longer sign in to
the app, and the app can no longer get tokens of its own.
Tokens already issued stay
valid until they expire.
Use Enable-IRTServicePrincipal to reverse.

Falls back to the service principals selected with Find-IRTServicePrincipal, in
$Global:IRT_ServicePrincipalObjects, when no -ServicePrincipalObject is passed.

Needs the Application.ReadWrite.All Graph permission, which Connect-IRT requests, and
the Application Administrator or Cloud Application Administrator role.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTServicePrincipal MyApp
Disable-IRTServicePrincipal
```
Two-step workflow: find then disable.

### EXAMPLE 2

```powershell
Disable-IRTServicePrincipal -ServicePrincipalObject $SP
```
Disable a specific service principal object passed directly.

## PARAMETERS

### -ServicePrincipalObject

One or more service principal objects, as returned by Find-IRTServicePrincipal.
Falls
back to $Global:IRT_ServicePrincipalObjects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- ServicePrincipalObjects
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

### None. Output is written to the console.

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
