function Get-TenantOidc {
    <#
    .SYNOPSIS
    Probes Microsoft cloud OIDC discovery endpoints to identify a tenant's cloud
    environment and return the full discovery document.

    .DESCRIPTION
    Queries the public OpenID Connect discovery endpoints for the Commercial,
    US Government, and China clouds to locate the given tenant. Returns the complete
    OIDC discovery document from whichever cloud responds, supplemented with three
    context properties:

        Cloud       - The cloud name that hosts the tenant (Commercial, USGov, China).
        Environment - Human-readable environment label derived from tenant_region_scope
                      and tenant_region_sub_scope (e.g. Commercial, GCC, GCC High, DoD).
        LoginHost   - The login authority hostname used for the successful probe.

    All raw OIDC fields (token_endpoint, authorization_endpoint, msgraph_host, issuer,
    jwks_uri, etc.) are preserved as returned by the discovery endpoint.

    Returns $null when the tenant GUID is not found in any supported cloud.

    This function is unauthenticated and makes no Graph API calls.

    .PARAMETER TenantId
    The Entra ID tenant GUID to probe.

    .EXAMPLE
    Get-TenantOidc -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

    .EXAMPLE
    $oidc = Get-TenantOidc -TenantId $tid
    Write-Host "Environment: $( $oidc.Environment ) | Graph: $( $oidc.msgraph_host )"

    .OUTPUTS
    PSCustomObject (augmented OIDC discovery document), or $null if not found.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter( Mandatory, Position = 0 )]
        [string] $TenantId
    )

    foreach ($cloud in $Global:IRT_CloudEnvironments.GetEnumerator()) {

        $Url = "$( $cloud.Value.LoginHost )/$TenantId/v2.0/.well-known/openid-configuration"
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

        return $oidc
    }

    return $null
}
