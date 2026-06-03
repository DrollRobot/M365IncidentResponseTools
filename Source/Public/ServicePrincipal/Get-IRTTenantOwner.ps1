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

    By default this function always queries live endpoints and updates the cache. Pass
    -Cached to return the in-memory entry when available, skipping live lookups. New
    results are appended to the CSV on a best-effort basis (silently skipped if the file
    is busy). Call Import-ReferenceData to reload the CSV into the global table without
    reimporting the module.

    .PARAMETER TenantId
    One or more Entra ID tenant GUIDs to look up.

    .PARAMETER SkipGraph
    Skip the authenticated Graph lookup and use only OIDC endpoints.
    Useful when you don't have a Graph session or lack the required scope.

    .PARAMETER Cached
    Return from the in-memory cache when available instead of querying live endpoints.
    Falls through to a live query if the tenant is not yet cached.

    .PARAMETER Quiet
    Suppress warnings about cross-cloud mismatches, Graph lookup failures, and
    tenants not found. Useful when calling in bulk where partial results are expected.

    .EXAMPLE
    Get-IRTTenantOwner -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' # Microsoft tenant id

    .EXAMPLE
    $guids | Get-IRTTenantOwner

    .EXAMPLE
    Get-IRTTenantOwner $tid -SkipGraph

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

        [switch] $Cached,

        [switch] $Quiet
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $NewCacheEntries = [System.Collections.Generic.List[psobject]]::new()
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

        # --- Pre-check for an active Graph session once, not per pipeline item ---
        $GraphAvailable = $false

        if (-not $SkipGraph) {
            try {
                $MgContext = Get-MgContext -ErrorAction Stop
                if ($MgContext) {
                    $GraphAvailable = $true
                    Write-PSFMessage -Level 8 -Message (
                        "Graph session active as $($MgContext.Account) " +
                        "(tenant: $($MgContext.TenantId))")
                }
            }
            catch {
                Write-PSFMessage -Level 8 -Message (
                    'No active Graph session; falling back to public endpoints only.')
            }
        }

        Write-PSFMessage -Level 8 -Message (
            "Get-IRTTenantOwner: SkipGraph=$SkipGraph, Cached=$Cached, " +
            "Quiet=$Quiet, GraphAvailable=$GraphAvailable")
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
            if ($Cached -and $Global:IRT_TenantInfoTable.ContainsKey($Tid)) {
                $cached = $Global:IRT_TenantInfoTable[$Tid]
                Write-PSFMessage -Level 8 -Message (
                    "Cache hit for '$Tid' (cached $($cached.CachedAt), " +
                    "DisplayName='$($cached.DisplayName)')")
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

            Write-PSFMessage -Level 8 -Message "Processing tenant '$Tid' via live query."

            # --- OIDC Discovery ---
            # Done first so we know the target cloud before attempting Graph.
            # Provides cloud, region, Graph host, and confirms the tenant exists.
            $Oidc = Get-IRTTenantOidc -TenantId $Tid
            $cloudName = ($Oidc)?.Cloud

            Write-PSFMessage -Level 8 -Message (
                "OIDC result for '$Tid': " +
                "Found=$([bool]$Oidc), Cloud=$cloudName, " +
                "LoginHost=$(($Oidc)?.LoginHost)")

            # --- Cross-cloud guard ---
            # The Graph cross-tenant endpoint only works within the same cloud. If the
            # target tenant is in a different cloud than the active session, skip Graph
            # and rely on public endpoints only.
            $UseGraph = $GraphAvailable
            if ($UseGraph -and $Oidc -and ($Global:IRT_Session)?.Cloud -and
                $cloudName -ne $Global:IRT_Session.Cloud) {
                if (-not $Quiet) {
                    $Msg = "Tenant '$Tid' is in the $cloudName cloud but the active " +
                        "Graph session is $( $Global:IRT_Session.Cloud ). " +
                        "Skipping Graph query."
                    Write-IRT $Msg -Level Warn
                }
                $UseGraph = $false
            }

            Write-PSFMessage -Level 8 -Message (
                "UseGraph=$UseGraph " +
                "(session cloud: $($Global:IRT_Session.Cloud), tenant cloud: $cloudName)")

            $displayName = $null
            $defaultDomain = $null
            $fedBrandName = $null
            $graphSource = $false

            # --- Graph Cross-Tenant Lookup ---
            # This is the only way to resolve a tenant GUID to its org name and domain.
            if ($UseGraph) {

                $GraphUri = "v1.0/tenantRelationships/" +
                "findTenantInformationByTenantId(tenantId='$Tid')"
                Write-PSFMessage -Level 8 -Message "Graph lookup: $GraphUri"

                try {
                    $info = Invoke-MgGraphRequest -Method GET -Uri $GraphUri -ErrorAction Stop

                    $displayName = $info.displayName
                    $defaultDomain = $info.defaultDomainName
                    $fedBrandName = $info.federationBrandName
                    $graphSource = $true

                    Write-PSFMessage -Level 8 -Message (
                        "Graph lookup succeeded for '$Tid': " +
                        "DisplayName='$displayName', Domain='$defaultDomain'")
                }
                catch {
                    $Msg = "Graph cross-tenant lookup failed for '$Tid': " +
                    "$( $_.Exception.Message )"
                    Write-PSFMessage -Level 8 -Message $Msg
                    if (-not $Quiet) { Write-IRT $Msg -Level Warn }
                }
            }

            if (-not $Oidc -and -not $graphSource) {
                Write-PSFMessage -Level 8 -Message "Tenant '$Tid' was not found in any cloud."
                if (-not $Quiet) { Write-IRT "Tenant '$Tid' was not found." -Level Warn }
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
                GraphHost           = ($Oidc)?.msgraph_host
                TokenEndpoint       = ($Oidc)?.token_endpoint
                Source              = if ($graphSource) { 'Graph' } else { 'PublicEndpoints' }
            }

            # --- Update global table and queue for cache write ---
            # Only cache when Graph returned owner data; partial OIDC-only results are not cached.
            if ($graphSource) {
                $cacheEntry = [pscustomobject]@{
                    TenantId            = $tid
                    DisplayName         = $displayName
                    DefaultDomain       = $defaultDomain
                    FederationBrandName = $fedBrandName
                    Cloud               = $cloudName
                    GraphHost           = ($Oidc)?.msgraph_host
                    TokenEndpoint       = ($Oidc)?.token_endpoint
                    CachedAt            = (Get-Date -Format 'o')
                }
                $Global:IRT_TenantInfoTable[$tid] = $cacheEntry
                $newCacheEntries.Add($cacheEntry)
                Write-PSFMessage -Level 8 -Message (
                    "Cached result for '$tid' " +
                    "(DisplayName='$displayName', Cloud=$cloudName)")
            }
        }
    }

    end {
        # Best-effort append; silently skip if the file is busy or inaccessible.
        # The global table is already updated - a failed write only affects persistence.
        if ($newCacheEntries.Count -gt 0) {
            try {
                $ExportParams = @{
                    Path              = $cachePath
                    Append            = $true
                    NoTypeInformation = $true
                    Encoding          = 'UTF8'
                }
                $newCacheEntries | Export-Csv @ExportParams
                Write-PSFMessage -Level 8 -Message (
                    "Appended $($newCacheEntries.Count) tenant(s) to $cachePath")
            }
            catch {}
        }
    }
}
