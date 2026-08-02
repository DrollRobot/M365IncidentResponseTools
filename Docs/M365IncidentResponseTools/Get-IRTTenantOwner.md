---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTTenantOwner
---

# Get-IRTTenantOwner

## SYNOPSIS

Resolves a tenant GUID to its organization name, default domain, and cloud environment.

## SYNTAX

```
Get-IRTTenantOwner [-TenantId] <string[]> [-SkipGraph] [-Cached] [-Quiet] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Looks up a Microsoft 365 / Entra ID tenant by GUID and returns its display name,
default domain, and environment details.

The display name and default domain come from the Graph cross-tenant information
API, which is the only endpoint that maps a tenant GUID to its org identity.
This
requires an active Graph connection (from any tenant) with the
CrossTenantInformation.ReadBasic.All scope.

An unauthenticated OIDC discovery lookup supplements the Graph data with cloud
environment, region, and endpoint information.
When -SkipGraph is used (or no
Graph session exists), OIDC can still confirm the tenant exists and identify its
cloud, but the display name and domain will be unavailable.

Results are cached in $Global:IRT_TenantInfoTable, pre-loaded at module import from:
    $env:APPDATA\<ModuleName>\TenantOwnerInfo.csv

By default this function always queries live endpoints and updates the cache.
Pass
-Cached to return the in-memory entry when available, skipping live lookups.
New
results are appended to the CSV on a best-effort basis (silently skipped if the file
is busy).
Call Import-ReferenceData to reload the CSV into the global table without
reimporting the module.

## EXAMPLES

### EXAMPLE 1

Get-IRTTenantOwner -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id

### EXAMPLE 2

$guids | Get-IRTTenantOwner

### EXAMPLE 3

Get-IRTTenantOwner $tid -SkipGraph

## PARAMETERS

### -Cached

Return from the in-memory cache when available instead of querying live endpoints.
Falls through to a live query if the tenant is not yet cached.

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

### -Quiet

Suppress warnings about cross-cloud mismatches, Graph lookup failures, and
tenants not found.
Useful when calling in bulk where partial results are expected.

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

### -SkipGraph

Skip the authenticated Graph lookup and use only OIDC endpoints.
Useful when you don't have a Graph session or lack the required scope.

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

### -TenantId

One or more Entra ID tenant GUIDs to look up.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- TenantIds
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

## NOTES

The Graph lookup requires the CrossTenantInformation.ReadBasic.All scope.

Version: 1.2.0


## RELATED LINKS

{{ Fill in the related links here }}
