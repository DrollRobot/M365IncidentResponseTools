function Get-IRTTenantInfo {
    <#
    .SYNOPSIS
    Resolves a tenant GUID to its organization name, default domain, and cloud environment.

    .DESCRIPTION
    Looks up a Microsoft 365 / Entra ID tenant by GUID and returns its display name,
    default domain, and environment details.

    The display name and default domain come from the Graph cross-tenant information
    API, which is the only endpoint that maps a tenant GUID to its org identity. This
    requires an active Graph connection (from any tenant) with the
    CrossTenantInformation.ReadBasic.All scope.

    An unauthenticated OIDC discovery lookup supplements the Graph data with cloud
    environment, region, and endpoint information. When -SkipGraph is used (or no
    Graph session exists), OIDC can still confirm the tenant exists and identify its
    cloud, but the display name and domain will be unavailable.

    Results are cached locally at:
        $env:APPDATA\<ModuleName>\tenant_owner_info.csv

    Where <ModuleName> is resolved at runtime from the module that contains this function.

    Cached entries are returned immediately on subsequent calls, skipping all network
    lookups. Use -ForceRefresh to re-query a tenant and update its cache entry, or
    -NoCache to bypass the cache entirely for a single call.

    .PARAMETER TenantId
    One or more Entra ID tenant GUIDs to look up.

    .PARAMETER SkipGraph
    Skip the authenticated Graph lookup and use only public endpoints.
    Useful when you don't have a Graph session or lack the required scope.

    .PARAMETER NoCache
    Bypass the local cache entirely — neither reads from it nor writes to it.

    .PARAMETER ForceRefresh
    Re-query even if the tenant is already cached, and overwrite the cached entry
    with the fresh result.

    .EXAMPLE
    Get-IRTTenantInfo -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id

    .EXAMPLE
    $guids | Get-IRTTenantInfo

    .EXAMPLE
    Get-IRTTenantInfo $tid -SkipGraph

    .EXAMPLE
    Get-IRTTenantInfo $tid -ForceRefresh

    .NOTES
    The Graph lookup requires the CrossTenantInformation.ReadBasic.All scope.
    Version: 1.2.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName )]
        [Alias('Tenant', 'Tenants', 'TenantId')]
        [string[]] $TenantIds,

        [switch] $SkipGraph,

        [switch] $NoCache,

        [switch] $ForceRefresh
    )

    begin {
        # --- Cache setup ---
        $cacheTable      = @{}
        $newCacheEntries = [System.Collections.Generic.List[psobject]]::new()
        $cachePath       = $null

        if (-not $NoCache) {
            $moduleName = $MyInvocation.MyCommand.ModuleName
            $cachePath = Join-Path $env:APPDATA $moduleName 'tenant_owner_info.csv'
            $cacheDir  = Split-Path $cachePath -Parent

            if (-not (Test-Path $cacheDir)) {
                $null = New-Item -ItemType Directory -Path $cacheDir -Force
            }

            if (Test-Path $cachePath) {
                try {
                    Import-Csv -Path $cachePath | ForEach-Object {
                        $cacheTable[$_.TenantId] = $_
                    }
                    Write-Verbose "Loaded $($cacheTable.Count) cached tenant(s) from $cachePath"
                }
                catch {
                    Write-Verbose "Could not load tenant cache: $($_.Exception.Message)"
                }
            }
        }

        # --- Pre-check for an active Graph session once, not per pipeline item ---
        $graphAvailable = $false

        if (-not $SkipGraph) {
            try {
                $mgCtx = Get-MgContext -ErrorAction Stop
                if ($mgCtx) {
                    $graphAvailable = $true
                    Write-Verbose "Graph session active as $($mgCtx.Account)"
                }
            }
            catch {
                Write-Verbose 'No active Graph session; falling back to public endpoints only.'
            }
        }
    }

    process {

        foreach ($tid in $TenantIds) {

            # --- Validate GUID ---
            $guidParsed = [guid]::Empty
            if (-not [guid]::TryParse($tid, [ref] $guidParsed)) {
                Write-Error "TenantId '$tid' is not a valid GUID."
                continue
            }
            $tid = $guidParsed.ToString()

            # --- Cache lookup ---
            if (-not $NoCache -and -not $ForceRefresh -and $cacheTable.ContainsKey($tid)) {
                $cached = $cacheTable[$tid]
                Write-Verbose "Cache hit for '$tid' (cached $( $cached.CachedAt ))"
                [pscustomobject]@{
                    TenantId            = $cached.TenantId
                    Exists              = $true
                    DisplayName         = $cached.DisplayName
                    DefaultDomain       = $cached.DefaultDomain
                    FederationBrandName = $cached.FederationBrandName
                    Environment         = $cached.Environment
                    Cloud               = $cached.Cloud
                    GraphHost           = $cached.GraphHost
                    TokenEndpoint       = $cached.TokenEndpoint
                    Source              = 'Cache'
                }
                continue
            }

            $displayName   = $null
            $defaultDomain = $null
            $fedBrandName  = $null
            $graphSource   = $false

            # --- Graph Cross-Tenant Lookup ---
            # This is the only way to resolve a tenant GUID to its org name and domain.
            if ($graphAvailable) {

                $graphUri = "v1.0/tenantRelationships/findTenantInformationByTenantId(tenantId='$tid')"
                Write-Verbose "Graph lookup: $graphUri"

                try {
                    $info = Invoke-MgGraphRequest -Method GET -Uri $graphUri -ErrorAction Stop

                    $displayName   = $info.displayName
                    $defaultDomain = $info.defaultDomainName
                    $fedBrandName  = $info.federationBrandName
                    $graphSource   = $true
                }
                catch {
                    Write-Warning "Graph cross-tenant lookup failed for '$tid': $( $_.Exception.Message )"
                }
            }

            # --- OIDC Discovery (unauthenticated) ---
            # Provides cloud, region, Graph host, and confirms the tenant exists.
            $CloudEndpoints = [ordered]@{
                Commercial = 'login.microsoftonline.com'
                USGov      = 'login.microsoftonline.us'
                China      = 'login.chinacloudapi.cn'
            }

            $oidc      = $null
            $cloudName = $null

            foreach ($cloud in $CloudEndpoints.GetEnumerator()) {

                $url = "https://$( $cloud.Value )/$tid/v2.0/.well-known/openid-configuration"
                Write-Verbose "Probing $( $cloud.Key ): $url"

                try {
                    $oidc      = Invoke-RestMethod -Uri $url -ErrorAction Stop
                    $cloudName = $cloud.Key
                    break
                }
                catch {
                    Write-Verbose "Not found in $( $cloud.Key )."
                }
            }

            if (-not $oidc -and -not $graphSource) {
                Write-Warning "Tenant '$tid' was not found."
                [pscustomobject]@{ TenantId = $tid; Exists = $false }
                continue
            }

            # --- Derive environment label ---
            $environment = $null
            if ($oidc) {
                $regionScope = $oidc.tenant_region_scope
                $regionSub   = $oidc.tenant_region_sub_scope

                $environment = switch ($regionScope) {
                    'WW' {
                        if ($regionSub -eq 'GCC') { 'GCC' } else { 'Commercial' }
                    }
                    'USGov' {
                        switch ($regionSub) {
                            'DODCON' { 'GCC High' }
                            'DOD'    { 'DoD' }
                            default  { 'USGov' }
                        }
                    }
                    'USG' { 'GCC High' }
                    'DOD' { 'DoD' }
                    default { $regionScope }
                }
            }

            # --- Output ---
            [pscustomobject]@{
                TenantId            = $tid
                Exists              = $true
                DisplayName         = $displayName
                DefaultDomain       = $defaultDomain
                FederationBrandName = $fedBrandName
                Environment         = $environment
                Cloud               = $cloudName
                GraphHost           = if ($oidc) { $oidc.msgraph_host } else { $null }
                TokenEndpoint       = if ($oidc) { $oidc.token_endpoint } else { $null }
                Source              = if ($graphSource) { 'Graph' } else { 'PublicEndpoints' }
            }

            # --- Queue for cache write ---
            if (-not $NoCache) {
                $newCacheEntries.Add([pscustomobject]@{
                    TenantId            = $tid
                    DisplayName         = $displayName
                    DefaultDomain       = $defaultDomain
                    FederationBrandName = $fedBrandName
                    Environment         = $environment
                    Cloud               = $cloudName
                    GraphHost           = if ($oidc) { $oidc.msgraph_host } else { $null }
                    TokenEndpoint       = if ($oidc) { $oidc.token_endpoint } else { $null }
                    CachedAt            = (Get-Date -Format 'o')
                })
            }
        }
    }

    end {
        # --- Persist cache (single write for the entire call) ---
        if (-not $NoCache -and $newCacheEntries.Count -gt 0) {
            try {
                # Merge: keep existing entries unless we have a fresh replacement
                $refreshedIds = $newCacheEntries | Select-Object -ExpandProperty TenantId
                $merged = [System.Collections.Generic.List[psobject]]::new()

                foreach ($entry in $cacheTable.Values) {
                    if ($entry.TenantId -notin $refreshedIds) {
                        $merged.Add($entry)
                    }
                }
                foreach ($entry in $newCacheEntries) {
                    $merged.Add($entry)
                }

                $merged | Export-Csv -Path $cachePath -NoTypeInformation -Encoding UTF8
                Write-Verbose "Cache updated: $( $merged.Count ) tenant(s) written to $cachePath"
            }
            catch {
                Write-Warning "Could not update tenant cache: $( $_.Exception.Message )"
            }
        }
    }
}

function Open-IRTTenantInfoCSV {
    <#
    .SYNOPSIS
    Opens the local tenant info cache CSV in the default application.

    .DESCRIPTION
    Opens $env:APPDATA\<ModuleName>\tenant_owner_info.csv in the system default
    application (typically Excel or Notepad), where <ModuleName> is resolved at
    runtime. If the file does not exist yet, a warning is displayed.

    .EXAMPLE
    Open-IRTTenantInfoCSV

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param ()

    $moduleName = $MyInvocation.MyCommand.ModuleName
    $cachePath  = Join-Path $env:APPDATA $moduleName 'tenant_owner_info.csv'

    if (-not (Test-Path $cachePath)) {
        Write-Warning "Tenant info cache not found at '$cachePath'. Run Get-IRTTenantInfo first to populate it."
        return
    }

    Write-Verbose "Opening $cachePath"
    Start-Process $cachePath
}

# TESTING
# Get-IRTTenantInfo -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft
# Get-IRTTenantInfo -SkipGraph -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id
# Get-IRTTenantInfo -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' -ForceRefresh # re-query and update cache
# Get-IRTTenantInfo -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' -NoCache     # skip cache entirely