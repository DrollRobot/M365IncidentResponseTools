---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTServicePrincipal
---

# Show-IRTServicePrincipal

## SYNOPSIS

Displays detailed service principal properties for objects produced by Find-ServicePrincipal.

## SYNTAX

```
Show-IRTServicePrincipal [[-ServicePrincipalObject] <psobject[]>] [-Cached] [<CommonParameters>]
```

## ALIASES

Show-IRTServicePrincipals, Show-ServicePrincipal, ShowIRTServicePrincipal, ShowIRTServicePrincipals, ShowServicePrincipal, ShowServicePrincipals, ShowSP, ShowSPs, ShowApp, ShowApps, ShowApplication, ShowApplications, ShowEnterpriseApp, ShowEnterpriseApps, ShowEnterpriseApplication, ShowEnterpriseApplications

## DESCRIPTION

Retrieves the full Graph service principal object using a curated property list and
displays it as a formatted tree in the console via Show-GraphServicePrincipalTree.

Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
passed.
This lets you run Find-ServicePrincipal first to select a target, then run
Show-IRTServicePrincipal with no arguments to display it.

Properties retrieved include credentials (key and password certificates), OAuth2
permission scopes, app roles, reply URLs, SSO settings, publisher verification,
and all standard identity fields.

After the property tree, four additional tables are displayed:
- OAuth2 Permission Grants: delegated permissions the SP has been granted (user or
  admin consent), with the resource display name resolved from the resource ID.
- App Role Assignments: application permissions (admin-consented app roles) assigned
  to the SP, with the role GUID resolved to the human-readable permission value.
- Directory Role Memberships: Entra admin roles (e.g.
Cloud Application Administrator)
  the SP has been assigned to.
Uses the IRT_DirectoryRoles cache if populated.
- App Role Assigned To: users, groups, and SPs that have been granted access to this app.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-ServicePrincipal MyApp
Show-IRTServicePrincipal
```
Two-step workflow: find then display.

### EXAMPLE 2

```powershell
Show-IRTServicePrincipal
```
Display info for the service principal already stored in the global session.

### EXAMPLE 3

```powershell
Show-IRTServicePrincipal -ServicePrincipalObject $SP
```
Display info for a specific service principal object passed directly.

## PARAMETERS

### -Cached

Pass -Cached to all Request-* calls so previously fetched Graph data is reused
instead of making new API calls.
Without this switch, each Request-* call fetches
fresh data from Graph.

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

### -ServicePrincipalObject

One or more service principal objects to display.
Falls back to
$Global:IRT_ServicePrincipalObjects if omitted.

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

Version: 1.3.0


## RELATED LINKS

{{ Fill in the related links here }}
