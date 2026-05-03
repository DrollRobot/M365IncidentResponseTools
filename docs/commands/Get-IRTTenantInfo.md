---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTTenantInfo

## SYNOPSIS
Resolves a tenant GUID to its organization name, default domain, and cloud environment.

## SYNTAX

```
Get-IRTTenantInfo [-TenantId] <String[]> [-SkipGraph] [-NoCache] [-ForceRefresh]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
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

Results are cached locally at:
    $env:APPDATA\\\<ModuleName\>\tenant_owner_info.csv

Where \<ModuleName\> is resolved at runtime from the module that contains this function.

Cached entries are returned immediately on subsequent calls, skipping all network
lookups.
Use -ForceRefresh to re-query a tenant and update its cache entry, or
-NoCache to bypass the cache entirely for a single call.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTTenantInfo -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id
```

### EXAMPLE 2
```
$guids | Get-IRTTenantInfo
```

### EXAMPLE 3
```
Get-IRTTenantInfo $tid -SkipGraph
```

### EXAMPLE 4
```
Get-IRTTenantInfo $tid -ForceRefresh
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

### -NoCache
Bypass the local cache entirely - neither reads from it nor writes to it.

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

### -ForceRefresh
Re-query even if the tenant is already cached, and overwrite the cached entry
with the fresh result.

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
