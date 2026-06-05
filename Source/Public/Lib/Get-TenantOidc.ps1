function Get-TenantOidc {
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
        Cloud       - The cloud that hosts the tenant, determined from the OIDC region
                      fields. One of the cloud table keys (Commercial, USGov, USGovDoD,
                      China). This is the key every Connect-IRT* command uses to select
                      endpoints.
        LoginHost   - The login authority hostname used for the successful probe.
        CloudConfig - The full endpoint record for the tenant's cloud (the same object
                      returned by Get-TenantOidc -CloudTable for that key). Callers can
                      store this in the session and use it directly without re-indexing.
    All raw OIDC fields (token_endpoint, authorization_endpoint, msgraph_host, issuer,
    jwks_uri, etc.) are preserved as returned by the discovery endpoint.
    Returns $null when the tenant is not found in any supported cloud.
    This function is unauthenticated and makes no Graph API calls.

    Note that a verified domain belongs to exactly one tenant, so a domain lookup
    resolves a single tenant. An organization that runs multiple tenants will have
    distinct domains per tenant; enumerate those separately to cover its full footprint.

    Use -CloudTable to retrieve the ordered endpoint table without performing a probe.
    The table is the data this function owns; it is the authoritative source of
    Microsoft cloud endpoint metadata for the module.

    .PARAMETER TenantId
    The tenant to probe, given as either an Entra ID tenant GUID or a verified
    domain name. Accepts the aliases 'Tenant' and 'Domain'.

    .PARAMETER CloudTable
    When specified, returns the ordered endpoint hashtable (Commercial, USGov,
    USGovDoD, China) without performing any network probe. Use this to resolve a
    known cloud key to its endpoint record.

    .EXAMPLE
    Get-TenantOidc -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

    .EXAMPLE
    Get-TenantOidc -Domain 'contoso.com'

    .EXAMPLE
    $oidc = Get-TenantOidc -TenantId $value
    Write-Host (
        "TenantId: $( $oidc.TenantId ) | Cloud: $( $oidc.Cloud ) | " +
        "Graph: $( $oidc.msgraph_host )")

    .EXAMPLE
    # Resolve a known cloud key to its endpoints without probing.
    $endpoints = (Get-TenantOidc -CloudTable)['USGov']
    $endpoints.Graph   # https://graph.microsoft.us

    .EXAMPLE
    # List all supported cloud keys.
    (Get-TenantOidc -CloudTable).Keys

    .EXAMPLE
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

    .OUTPUTS
    PSCustomObject (augmented OIDC discovery document), or $null if not found.
    System.Collections.Specialized.OrderedDictionary when -CloudTable is specified.

    .NOTES
    Version: 1.2.0
    #>
    [CmdletBinding(DefaultParameterSetName = 'Probe')]
    [OutputType([pscustomobject], ParameterSetName = 'Probe')]
    [OutputType([System.Collections.Specialized.OrderedDictionary],
        ParameterSetName = 'CloudTable')]
    param (
        [Parameter( Mandatory, Position = 0, ParameterSetName = 'Probe' )]
        [Alias( 'Tenant', 'Domain' )]
        [string] $TenantId,

        [Parameter( Mandatory, ParameterSetName = 'CloudTable' )]
        [switch] $CloudTable,

        [switch] $Trace
    )

    # debug output
    if ($Trace) { $InformationPreference = 'Continue' }
    function Write-Trace {
        param([Parameter(Mandatory)][string]$Message)
        Write-Information $Message -Tags 'Trace'
    }

    # Cloud endpoint definitions. Ordered so OIDC probing tries Commercial first,
    # then USGov, then USGovDoD, then China.
    $CloudEnvironments = [ordered]@{
        Commercial = @{
            LoginHost      = 'https://login.microsoftonline.com'
            Graph          = 'https://graph.microsoft.com'
            GraphEnv       = 'Global'
            Exchange       = 'https://outlook.office365.com/.default'
            ExchangeEnv    = 'O365Default'
            IPPS           = 'https://ps.compliance.protection.outlook.com/powershell-liveid/'
            IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
        }
        USGov      = @{
            LoginHost      = 'https://login.microsoftonline.us'
            Graph          = 'https://graph.microsoft.us'
            GraphEnv       = 'USGov'
            Exchange       = 'https://outlook.office365.us/.default'
            ExchangeEnv    = 'O365USGovGCCHigh'
            IPPS           = 'https://ps.compliance.protection.office365.us/powershell-liveid/'
            IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
        }
        USGovDoD   = @{
            LoginHost      = 'https://login.microsoftonline.us'
            Graph          = 'https://dod-graph.microsoft.us'
            GraphEnv       = 'USGovDoD'
            Exchange       = 'https://outlook-dod.office365.us/.default'
            ExchangeEnv    = 'O365USGovDoD'
            IPPS           = 'https://l5.ps.compliance.protection.office365.us/powershell-liveid/'
            # maybe this instead? microsoft docs inconsistent:
            # https://compliance.dod.microsoft.com/powershell-liveid
            IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
        }
        China      = @{
            LoginHost      = 'https://login.chinacloudapi.cn'
            Graph          = 'https://microsoftgraph.chinacloudapi.cn'
            GraphEnv       = 'China'
            Exchange       = 'https://partner.outlook.cn/.default'
            ExchangeEnv    = 'O365China'
            IPPS           = 'https://ps.compliance.protection.partner.outlook.cn/powershell-liveid'
            IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
        }
    }

    if ($CloudTable) { return $CloudEnvironments }

    foreach ($cloud in $CloudEnvironments.GetEnumerator()) {

        $Url = "$( $cloud.Value.LoginHost )/$TenantId/v2.0/.well-known/openid-configuration"
        Write-Trace "Get-TenantOidc: Probing $( $cloud.Key ): $Url"

        try {
            $Oidc = Invoke-RestMethod -Uri $Url -ErrorAction Stop
        }
        catch {
            Write-Trace "Get-TenantOidc: Tenant not found in $( $cloud.Key )."
            continue
        }

        $RegionScope = $Oidc.tenant_region_scope
        $RegionSubScope = $Oidc.tenant_region_sub_scope

        # Determine the cloud directly from the OIDC region fields. The cloud is a
        # cloud table key and the only value the Connect-IRT* commands need. It must
        # not come from which probe answered: the Commercial endpoint also responds for
        # GCC High/DoD tenants (returning tenant_region_scope=USGov), so $cloud.Key
        # would wrongly be 'Commercial' and yield the wrong authority (AADSTS900384).
        # GCC is commercial-hosted, so WW maps to Commercial.
        $cloudKey = switch ($RegionScope) {
            'WW' { 'Commercial' }                                       # incl. GCC
            'USGov' { if ($RegionSubScope -eq 'DOD') { 'USGovDoD' } else { 'USGov' } }
            'USG' { 'USGov' }                                            # GCC High
            'DOD' { 'USGovDoD' }
            default { $cloud.Key }                                         # China, etc.
        }

        $Oidc | Add-Member -NotePropertyName 'Cloud' -NotePropertyValue $cloudKey
        $Oidc | Add-Member -NotePropertyName 'LoginHost' -NotePropertyValue $cloud.Value.LoginHost
        $CloudConfigValue = $CloudEnvironments[$cloudKey]
        $Oidc | Add-Member -NotePropertyName 'CloudConfig' -NotePropertyValue $CloudConfigValue

        # issuer is https://login.microsoftonline.<tld>/{tenant-guid}/v2.0
        # Extract the canonical GUID so a domain-based lookup still returns the tenant ID.
        $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $tenantId = if ($Oidc.issuer -match $guidPattern) { $Matches[0] } else { $null }

        $Oidc | Add-Member -NotePropertyName 'TenantId' -NotePropertyValue $tenantId

        return $Oidc
    }

    return $null
}
