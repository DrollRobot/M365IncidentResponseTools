---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/29/2026
PlatyPS schema version: 2024-05-01
title: Enable-IRTServicePrincipal
---

# Enable-IRTServicePrincipal

## SYNOPSIS

Enables service principals (enterprise apps) that Disable-IRTServicePrincipal disabled.

## SYNTAX

```
Enable-IRTServicePrincipal [[-ServicePrincipalObject] <psobject[]>] [<CommonParameters>]
```

## ALIASES

Enable-IRTServicePrincipals, Enable-ServicePrincipal, Enable-ServicePrincipals, EnableIRTServicePrincipal, EnableIRTServicePrincipals, EnableServicePrincipal, EnableServicePrincipals, Enable-IRTSP, Enable-IRTSPs, Enable-SP, Enable-SPs, EnableIRTSP, EnableIRTSPs, EnableSP, EnableSPs, Enable-IRTEnterpriseApplication, Enable-IRTEnterpriseApplications, Enable-EnterpriseApplication, Enable-EnterpriseApplications, EnableIRTEnterpriseApplication, EnableIRTEnterpriseApplications, EnableEnterpriseApplication, EnableEnterpriseApplications

## DESCRIPTION

Sets accountEnabled to true on each service principal, so Entra issues tokens for it
again.

Falls back to the service principals selected with Find-IRTServicePrincipal, in
$Global:IRT_ServicePrincipalObjects, when no -ServicePrincipalObject is passed.

Needs the Application.ReadWrite.All Graph permission, which Connect-IRT requests, and
the Application Administrator or Cloud Application Administrator role.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTServicePrincipal MyApp
Enable-IRTServicePrincipal
```
Two-step workflow: find then enable.

### EXAMPLE 2

```powershell
Enable-IRTServicePrincipal -ServicePrincipalObject $SP
```
Enable a specific service principal object passed directly.

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
