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
    whichever cloud responds, supplemented with four context properties:
        TenantId    - The canonical tenant GUID, extracted from the issuer claim.
                      Populated even when the lookup was performed by domain.
        Cloud       - The cloud name that hosts the tenant (Commercial, USGov,
                      USGovDoD, China).
        Environment - Human-readable environment label derived from tenant_region_scope
                      and tenant_region_sub_scope (e.g. Commercial, GCC, GCC High, DoD).
        LoginHost   - The login authority hostname used for the successful probe.
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
    $oidc = Get-IRTTenantOidc -Tenant $value
    Write-Host "TenantId: $( $oidc.TenantId ) | Environment: $( $oidc.Environment ) | Graph: $( $oidc.msgraph_host )"

    .OUTPUTS
    PSCustomObject (augmented OIDC discovery document), or $null if not found.
    
    .NOTES
    Version: 1.1.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter( Mandatory, Position = 0 )]
        [Alias( 'TenantId', 'Domain' )]
        [string] $Tenant
    )

    foreach ($cloud in $Global:IRT_CloudEnvironments.GetEnumerator()) {

        $Url = "$( $cloud.Value.LoginHost )/$Tenant/v2.0/.well-known/openid-configuration"
        Write-Verbose "Probing $( $cloud.Key ): $Url"

        try {
            $oidc = Invoke-RestMethod -Uri $Url -ErrorAction Stop
        }
        catch {
            Write-Verbose "Not found in $( $cloud.Key )."
            continue
        }

        $regionScope = $oidc.tenant_region_scope
        $regionSub = $oidc.tenant_region_sub_scope

        $environment = switch ($regionScope) {
            'WW' {
                if ($regionSub -eq 'GCC') { 'GCC' } else { 'Commercial' }
            }
            'USGov' {
                switch ($regionSub) {
                    'DODCON' { 'GCC High' }
                    'DOD' { 'DoD' }
                    default { 'USGov' }
                }
            }
            'USG' { 'GCC High' }
            'DOD' { 'DoD' }
            default { $regionScope }
        }

        # USGov and USGovDoD share the same LoginHost so USGov always matches first;
        # use the detected environment to select the correct key.
        $cloudKey = if ($environment -eq 'DoD') { 'USGovDoD' } else { $cloud.Key }
        $oidc | Add-Member -NotePropertyName 'Cloud'       -NotePropertyValue $cloudKey
        $oidc | Add-Member -NotePropertyName 'Environment' -NotePropertyValue $environment
        $oidc | Add-Member -NotePropertyName 'LoginHost'   -NotePropertyValue $cloud.Value.LoginHost

        # issuer is https://login.microsoftonline.<tld>/{tenant-guid}/v2.0
        # Extract the canonical GUID so a domain-based lookup still returns the tenant ID.
        $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $tenantId = if ($oidc.issuer -match $guidPattern) { $Matches[0] } else { $null }

        $oidc | Add-Member -NotePropertyName 'TenantId'    -NotePropertyValue $tenantId

        return $oidc
    }

    return $null
}
