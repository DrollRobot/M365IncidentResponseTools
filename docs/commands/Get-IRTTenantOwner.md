---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTTenantOwner

## SYNOPSIS
Resolves a tenant GUID to its organization name, default domain, and cloud environment.

## SYNTAX

```
Get-IRTTenantOwner [-TenantId] <String[]> [-SkipGraph] [-Cached] [-Quiet] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

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
    $env:APPDATA\\\<ModuleName\>\TenantOwnerInfo.csv

New results are added to the in-memory table immediately and appended to the CSV on
a best-effort basis (silently skipped if the file is busy).
Use -ForceRefresh to
re-query a tenant and update its cache entry, or -NoCache to bypass the cache
entirely for a single call.
Call Import-ReferenceData to reload the CSV into the
global table without reimporting the module.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTTenantOwner -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id
```

### EXAMPLE 2
```
$guids | Get-IRTTenantOwner
```

### EXAMPLE 3
```
Get-IRTTenantOwner $tid -SkipGraph
```

### EXAMPLE 4
```
Get-IRTTenantOwner $tid -ForceRefresh
```

## PARAMETERS

### -TenantId
One or more Entra ID tenant GUIDs to look up.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: TenantIds

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -SkipGraph
Skip the authenticated Graph lookup and use only public endpoints.
Useful when you don't have a Graph session or lack the required scope.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Cached
Return from the in-memory cache when available instead of querying live endpoints.
Falls through to a live query if the tenant is not yet cached.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Quiet
Suppress warnings about cross-cloud mismatches, Graph lookup failures, and
tenants not found. Useful when calling in bulk where partial results are expected.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
The Graph lookup requires the CrossTenantInformation.ReadBasic.All scope.
Version: 1.2.0

## RELATED LINKS
