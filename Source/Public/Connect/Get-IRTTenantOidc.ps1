function Get-IRTTenantOidc {
    <#
    .SYNOPSIS
    Probes Microsoft cloud OIDC discovery endpoints to identify a tenant's cloud
    environment and return the full discovery document, including its tenant ID.

    .DESCRIPTION
    Queries the public OpenID Connect discovery endpoints for the Commercial,
    US Government, and China clouds to locate the given tenant. Accepts either a
    tenant GUID or any verified domain (a custom domain such as 'contoso.com' or
    the '.onmicrosoft.com' default), since the discovery endpoint resolves both
    forms in the authority path. Returns the complete OIDC discovery document from
    whichever cloud responds, supplemented with three context properties:
        TenantId  - The canonical tenant GUID, extracted from the issuer claim.
                    Populated even when the lookup was performed by domain.
        Cloud     - The cloud that hosts the tenant, determined from the OIDC region
                    fields. One of the $Global:IRT_CloudEnvironments keys (Commercial,
                    USGov, USGovDoD, China). This is the key every Connect-IRT* command
                    uses to select endpoints.
        LoginHost - The login authority hostname used for the successful probe.
    All raw OIDC fields (token_endpoint, authorization_endpoint, msgraph_host, issuer,
    jwks_uri, etc.) are preserved as returned by the discovery endpoint.
    Returns $null when the tenant is not found in any supported cloud.
    This function is unauthenticated and makes no Graph API calls.

    Note that a verified domain belongs to exactly one tenant, so a domain lookup
    resolves a single tenant. An organization that runs multiple tenants will have
    distinct domains per tenant; enumerate those separately to cover its full footprint.

    .PARAMETER Tenant
    The tenant to probe, given as either an Entra ID tenant GUID or a verified
    domain name. Accepts the aliases 'TenantId' and 'Domain'.

    .EXAMPLE
    Get-IRTTenantOidc -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

    .EXAMPLE
    Get-IRTTenantOidc -Domain 'contoso.com'

    .EXAMPLE
    $oidc = Get-IRTTenantOidc -TenantId $value
    Write-Host (
        "TenantId: $( $oidc.TenantId ) | Cloud: $( $oidc.Cloud ) | " +
        "Graph: $( $oidc.msgraph_host )")

    .OUTPUTS
    PSCustomObject (augmented OIDC discovery document), or $null if not found.

    .NOTES
    Version: 1.1.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter( Mandatory, Position = 0 )]
        [Alias( 'Tenant', 'Domain' )]
        [string] $TenantId
    )

    foreach ($cloud in $Global:IRT_CloudEnvironments.GetEnumerator()) {

        $Url = "$( $cloud.Value.LoginHost )/$TenantId/v2.0/.well-known/openid-configuration"
        Write-PSFMessage -Level 8 -Message "Get-IRTTenantOidc: Probing $( $cloud.Key ): $Url"

        try {
            $Oidc = Invoke-RestMethod -Uri $Url -ErrorAction Stop
        }
        catch {
            Write-PSFMessage -Level 8 -Message "Get-IRTTenantOidc: Not found in $( $cloud.Key )."
            continue
        }

        $RegionScope = $Oidc.tenant_region_scope
        $RegionSubScope = $Oidc.tenant_region_sub_scope

        # Determine the cloud directly from the OIDC region fields. The cloud is a
        # $Global:IRT_CloudEnvironments key and the only value the Connect-IRT* commands
        # need. It must not come from which probe answered: the Commercial endpoint also
        # responds for GCC High/DoD tenants (returning tenant_region_scope=USGov), so
        # $cloud.Key would wrongly be 'Commercial' and yield the wrong authority
        # (AADSTS900384). GCC is commercial-hosted, so WW maps to Commercial.
        $cloudKey = switch ($RegionScope) {
            'WW' { 'Commercial' }                                       # incl. GCC
            'USGov' { if ($RegionSubScope -eq 'DOD') { 'USGovDoD' } else { 'USGov' } }
            'USG' { 'USGov' }                                            # GCC High
            'DOD' { 'USGovDoD' }
            default { $cloud.Key }                                         # China, etc.
        }

        $Oidc | Add-Member -NotePropertyName 'Cloud'     -NotePropertyValue $cloudKey
        $Oidc | Add-Member -NotePropertyName 'LoginHost' -NotePropertyValue $cloud.Value.LoginHost

        # issuer is https://login.microsoftonline.<tld>/{tenant-guid}/v2.0
        # Extract the canonical GUID so a domain-based lookup still returns the tenant ID.
        $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $tenantId = if ($Oidc.issuer -match $guidPattern) { $Matches[0] } else { $null }

        $Oidc | Add-Member -NotePropertyName 'TenantId' -NotePropertyValue $tenantId

        return $Oidc
    }

    return $null
}
