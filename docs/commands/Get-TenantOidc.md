---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-TenantOidc

## SYNOPSIS
Probes Microsoft cloud OIDC discovery endpoints to identify a tenant's cloud
environment and return the full discovery document, including its tenant ID.

## SYNTAX

### Probe (Default)
```
Get-TenantOidc [-TenantId] <String> [-Trace] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### CloudTable
```
Get-TenantOidc [-CloudTable] [-Trace] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Queries the public OpenID Connect discovery endpoints for the Commercial,
US Government, and China clouds to locate the given tenant.
Accepts either a
tenant GUID or any verified domain (a custom domain such as 'contoso.com' or
the '.onmicrosoft.com' default), since the discovery endpoint resolves both
forms in the authority path.
Returns the complete OIDC discovery document from
whichever cloud responds, supplemented with four context properties:
    TenantId    - The canonical tenant GUID, extracted from the issuer claim.
                  Populated even when the lookup was performed by domain.
    Cloud       - The cloud that hosts the tenant, determined from the OIDC region
                  fields.
One of the cloud table keys (Commercial, USGov, USGovDoD,
                  China).
This is the key every Connect-IRT* command uses to select
                  endpoints.
    LoginHost   - The login authority hostname used for the successful probe.
    CloudConfig - The full endpoint record for the tenant's cloud (the same object
                  returned by Get-TenantOidc -CloudTable for that key).
Callers can
                  store this in the session and use it directly without re-indexing.
All raw OIDC fields (token_endpoint, authorization_endpoint, msgraph_host, issuer,
jwks_uri, etc.) are preserved as returned by the discovery endpoint.
Returns $null when the tenant is not found in any supported cloud.
This function is unauthenticated and makes no Graph API calls.

Note that a verified domain belongs to exactly one tenant, so a domain lookup
resolves a single tenant.
An organization that runs multiple tenants will have
distinct domains per tenant; enumerate those separately to cover its full footprint.

Use -CloudTable to retrieve the ordered endpoint table without performing a probe.
The table is the data this function owns; it is the authoritative source of
Microsoft cloud endpoint metadata for the module.

## EXAMPLES

### EXAMPLE 1
```
Get-TenantOidc -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
```

### EXAMPLE 2
```
Get-TenantOidc -Domain 'contoso.com'
```

### EXAMPLE 3
```
$oidc = Get-TenantOidc -TenantId $value
Write-Host (
    "TenantId: $( $oidc.TenantId ) | Cloud: $( $oidc.Cloud ) | " +
    "Graph: $( $oidc.msgraph_host )")
```

### EXAMPLE 4
```
# Resolve a known cloud key to its endpoints without probing.
$endpoints = (Get-TenantOidc -CloudTable)['USGov']
$endpoints.Graph   # https://graph.microsoft.us
```

### EXAMPLE 5
```
# List all supported cloud keys.
(Get-TenantOidc -CloudTable).Keys
```

### EXAMPLE 6
```
# Shape of the CloudConfig object (also returned as $oidc.CloudConfig after a probe).
# All keys present on every cloud entry:
#
#   LoginHost      - https://login.microsoftonline.com
#   Graph          - https://graph.microsoft.com          (Graph API base URL)
#   GraphEnv       - Global                               (Connect-MgGraph -Environment)
#   Exchange       - https://outlook.office365.com/.default
#   ExchangeEnv    - O365Default    (Connect-ExchangeOnline -ExchangeEnvironmentName)
#   IPPS           - https://ps.compliance.protection.outlook.com/powershell-liveid/
#   IPPSSearchOnly - https://dataservice.o365filtering.com/.default
$cc = (Get-TenantOidc -CloudTable)['Commercial']
$cc.GraphEnv        # Global
$cc.ExchangeEnv     # O365Default
```

## PARAMETERS

### -TenantId
The tenant to probe, given as either an Entra ID tenant GUID or a verified
domain name.
Accepts the aliases 'Tenant' and 'Domain'.

```yaml
Type: String
Parameter Sets: Probe
Aliases: Tenant, Domain

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -CloudTable
When specified, returns the ordered endpoint hashtable (Commercial, USGov,
USGovDoD, China) without performing any network probe.
Use this to resolve a
known cloud key to its endpoint record.

```yaml
Type: SwitchParameter
Parameter Sets: CloudTable
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Trace
{{ Fill Trace Description }}

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

### PSCustomObject (augmented OIDC discovery document), or $null if not found.
### System.Collections.Specialized.OrderedDictionary when -CloudTable is specified.
## NOTES
Version: 1.2.0

## RELATED LINKS
