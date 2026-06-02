function Get-IRTTenantOwner {
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

    Results are cached in $Global:IRT_TenantInfoTable, pre-loaded at module import from:
        $env:APPDATA\<ModuleName>\TenantOwnerInfo.csv

    New results are added to the in-memory table immediately and appended to the CSV on
    a best-effort basis (silently skipped if the file is busy). Use -ForceRefresh to
    re-query a tenant and update its cache entry, or -NoCache to bypass the cache
    entirely for a single call. Call Import-ReferenceData to reload the CSV into the
    global table without reimporting the module.

    .PARAMETER TenantId
    One or more Entra ID tenant GUIDs to look up.

    .PARAMETER SkipGraph
    Skip the authenticated Graph lookup and use only public endpoints.
    Useful when you don't have a Graph session or lack the required scope.

    .PARAMETER NoCache
    Bypass the local cache entirely - neither reads from it nor writes to it.

    .PARAMETER ForceRefresh
    Re-query even if the tenant is already cached, and overwrite the cached entry
    with the fresh result.

    .EXAMPLE
    Get-IRTTenantOwner -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id

    .EXAMPLE
    $guids | Get-IRTTenantOwner

    .EXAMPLE
    Get-IRTTenantOwner $tid -SkipGraph

    .EXAMPLE
    Get-IRTTenantOwner $tid -ForceRefresh

    .NOTES
    The Graph lookup requires the CrossTenantInformation.ReadBasic.All scope.

    # FIXME Should probably separate this from the OIDC lookup. one task per function

    Version: 1.2.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName )]
        [Alias('TenantIds')]
        [string[]] $TenantId,

        [switch] $SkipGraph,

        [switch] $NoCache,

        [switch] $ForceRefresh
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $NewCacheEntries = [System.Collections.Generic.List[psobject]]::new()
        $CachePath = $null

        if (-not $NoCache) {
            $ModuleName = $MyInvocation.MyCommand.ModuleName
            $JpParams = @{
                Path                = $env:APPDATA
                ChildPath           = $ModuleName
                AdditionalChildPath = 'TenantOwnerInfo.csv'
            }
            $CachePath = Join-Path @JpParams
            $CacheDir = Split-Path $CachePath -Parent
            if (-not (Test-Path $CacheDir)) {
                $null = New-Item -ItemType Directory -Path $CacheDir -Force
            }
        }

        # --- Pre-check for an active Graph session once, not per pipeline item ---
        $GraphAvailable = $false

        if (-not $SkipGraph) {
            try {
                $MgContext = Get-MgContext -ErrorAction Stop
                if ($MgContext) {
                    $GraphAvailable = $true
                    Write-Verbose "Graph session active as $($MgContext.Account)"
                }
            }
            catch {
                Write-Verbose 'No active Graph session; falling back to public endpoints only.'
            }
        }
    }

    process {

        foreach ($Tid in $TenantId) {

            # --- Validate GUID ---
            $guidParsed = [guid]::Empty
            if (-not [guid]::TryParse($Tid, [ref] $guidParsed)) {
                Write-Error "TenantId '$Tid' is not a valid GUID."
                continue
            }
            $Tid = $guidParsed.ToString()

            # --- Cache lookup ---
            if (-not $NoCache -and -not $ForceRefresh -and
                $Global:IRT_TenantInfoTable.ContainsKey($Tid)) {
                $cached = $Global:IRT_TenantInfoTable[$Tid]
                Write-Verbose "Cache hit for '$Tid' (cached $( $cached.CachedAt ))"
                [pscustomobject]@{
                    TenantId            = $cached.TenantId
                    Exists              = $true
                    DisplayName         = $cached.DisplayName
                    DefaultDomain       = $cached.DefaultDomain
                    FederationBrandName = $cached.FederationBrandName
                    Cloud               = $cached.Cloud
                    GraphHost           = $cached.GraphHost
                    TokenEndpoint       = $cached.TokenEndpoint
                    Source              = 'Cache'
                }
                continue
            }

            $displayName = $null
            $defaultDomain = $null
            $fedBrandName = $null
            $graphSource = $false

            # --- Graph Cross-Tenant Lookup ---
            # This is the only way to resolve a tenant GUID to its org name and domain.
            if ($GraphAvailable) {

                $GraphUri = "v1.0/tenantRelationships/" +
                "findTenantInformationByTenantId(tenantId='$Tid')"
                Write-Verbose "Graph lookup: $GraphUri"

                try {
                    $info = Invoke-MgGraphRequest -Method GET -Uri $GraphUri -ErrorAction Stop

                    $displayName = $info.displayName
                    $defaultDomain = $info.defaultDomainName
                    $fedBrandName = $info.federationBrandName
                    $graphSource = $true
                }
                catch {
                    $Msg = "Graph cross-tenant lookup failed for '$Tid': " +
                    "$( $_.Exception.Message )"
                    Write-Warning $Msg
                }
            }

            # --- OIDC Discovery ---
            # Provides cloud, region, Graph host, and confirms the tenant exists.
            $Oidc = Get-IRTTenantOidc -TenantId $Tid
            $cloudName = $Oidc?.Cloud

            if (-not $Oidc -and -not $graphSource) {
                Write-Warning "Tenant '$Tid' was not found."
                [pscustomobject]@{ TenantId = $Tid; Exists = $false }
                continue
            }

            # --- Output ---
            [pscustomobject]@{
                TenantId            = $tid
                Exists              = $true
                DisplayName         = $displayName
                DefaultDomain       = $defaultDomain
                FederationBrandName = $fedBrandName
                Cloud               = $cloudName
                GraphHost           = $Oidc?.msgraph_host
                TokenEndpoint       = $Oidc?.token_endpoint
                Source              = if ($graphSource) { 'Graph' } else { 'PublicEndpoints' }
            }

            # --- Update global table and queue for cache write ---
            if (-not $NoCache) {
                $cacheEntry = [pscustomobject]@{
                    TenantId            = $tid
                    DisplayName         = $displayName
                    DefaultDomain       = $defaultDomain
                    FederationBrandName = $fedBrandName
                    Cloud               = $cloudName
                    GraphHost           = $Oidc?.msgraph_host
                    TokenEndpoint       = $Oidc?.token_endpoint
                    CachedAt            = (Get-Date -Format 'o')
                }
                $Global:IRT_TenantInfoTable[$tid] = $cacheEntry
                $newCacheEntries.Add($cacheEntry)
            }
        }
    }

    end {
        # Best-effort append; silently skip if the file is busy or inaccessible.
        # The global table is already updated - a failed write only affects persistence.
        if (-not $NoCache -and $newCacheEntries.Count -gt 0) {
            try {
                $ExportParams = @{
                    Path              = $cachePath
                    Append            = $true
                    NoTypeInformation = $true
                    Encoding          = 'UTF8'
                }
                $newCacheEntries | Export-Csv @ExportParams
                Write-Verbose "Appended $( $newCacheEntries.Count ) tenant(s) to $cachePath"
            }
            catch {}
        }
    }
}
