#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

function Get-MsalCacheStat {
    <#
    .SYNOPSIS
    Shows diagnostic statistics for the IRT persistent MSAL token cache.

    .DESCRIPTION
    Enumerates all accounts stored in the IRT persistent MSAL token cache and for
    each (Service, Account) pair attempts a silent token refresh with force-refresh
    enabled so the stored refresh token is exercised against the live token endpoint.
    This confirms whether refresh tokens are still valid without an interactive prompt.

    For each obtained access token the JWT payload is decoded and reported: audience,
    issuer, issued-at time, scopes, and expiry. Full results are returned as
    [PSCustomObject] rows suitable for Format-List or Export-Csv.

    Requires M365IncidentResponseTools to be imported. Run after Connect-IRT for
    meaningful results. Cache registration (reading the .bin file) requires the IRT
    module to be loaded so the private Register-MsalCache function is reachable via
    PSModuleInfo.NewBoundScriptBlock.

    .PARAMETER CachePath
    Override the cache file path. Defaults to $Global:IRT_Config.MsalCachePath or
    $env:LOCALAPPDATA\M365IncidentResponseTools\IRT-Cache.bin.

    .PARAMETER SkipTokenTest
    Enumerate cached accounts without attempting silent token acquisition. Avoids all
    network calls and does not validate whether refresh tokens are still usable.

    .PARAMETER Trace
    Write trace-level output for each MSAL step to aid debugging.

    .EXAMPLE
    . .\Tests\Dev\Get-MsalCacheStats.ps1
    Get-MsalCacheStats

    Enumerate cached accounts and test each service's refresh token validity.

    .EXAMPLE
    . .\Tests\Dev\Get-MsalCacheStats.ps1
    Get-MsalCacheStats -SkipTokenTest | Format-List

    List cached accounts only without making any network token requests.

    .EXAMPLE
    . .\Tests\Dev\Get-MsalCacheStats.ps1
    Get-MsalCacheStats | Export-Csv -Path .\token-report.csv -NoTypeInformation

    Export full token diagnostics to CSV.

    .OUTPUTS
    [PSCustomObject[]] One row per (Service, Account) combination.

    .NOTES
    Version: 1.0.0
    Non-domain dev script. Dot-source before calling.
    Uses PSModuleInfo.NewBoundScriptBlock to invoke the private Register-MsalCache function.
    Exchange and IPPS share the same MSAL client ID (fb78d390...); their accounts are
    identical but the test scopes differ, so each is tested separately.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string] $CachePath,
        [switch] $SkipTokenTest,
        [switch] $Trace
    )

    if ($Trace) { $InformationPreference = 'Continue' }
    function Write-Trace {
        param([Parameter(Mandatory)][string] $Message)
        Write-Information $Message -Tags 'Trace'
    }

    function Expand-Jwt {
        param([Parameter(Mandatory)][string] $Token)
        try {
            $Parts = $Token.Split('.')
            if ($Parts.Count -lt 2) { return $null }
            $Seg = $Parts[1].Replace('-', '+').Replace('_', '/')
            switch ($Seg.Length % 4) { 2 { $Seg += '==' } 3 { $Seg += '=' } }
            $Bytes = [System.Convert]::FromBase64String($Seg)
            $Json = [System.Text.Encoding]::UTF8.GetString($Bytes)
            return $Json | ConvertFrom-Json
        } catch { return $null }
    }

    # find host module name
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Find-ModuleRoot.ps1')
    $HostModuleInfo = Find-ModuleRoot -Path $PSScriptRoot

    # import modules
    $PsdName = "$($HostModuleInfo.Name).psd1"
    $SourcePath = Join-Path -Path $HostModuleInfo.Path -ChildPath "Source\$PsdName"
    Import-Module $SourcePath
    Import-Module Microsoft.Graph.Authentication
    $HostModule = Get-Module $HostModuleInfo.Name | Where-Object { $_.ModuleBase -match 'Source' }

    # ---- Resolve cache path ----
    if (-not $CachePath) {
        if ($Global:IRT_Config.MsalCachePath) {
            $CachePath = $Global:IRT_Config.MsalCachePath
        } else {
            $JpArgs = @{
                Path                = $env:LOCALAPPDATA
                ChildPath           = 'M365IncidentResponseTools'
                AdditionalChildPath = 'IRT-Cache.bin'
            }
            $CachePath = Join-Path @JpArgs
        }
    }

    # ---- Cache file summary ----
    $Now = [System.DateTime]::UtcNow
    $CacheFile = Get-Item -Path $CachePath -ErrorAction SilentlyContinue
    Write-Host '=== IRT MSAL Token Cache ===' -ForegroundColor Cyan
    Write-Host "  Now (UTC)  : $($Now.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Cache path : $CachePath"
    if ($CacheFile) {
        $SizeKB = [Math]::Round($CacheFile.Length / 1KB, 2)
        $ModTime = $CacheFile.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss')
        $AgeDays = [Math]::Round(($Now - $CacheFile.LastWriteTimeUtc).TotalDays, 1)
        Write-Host "  Size       : $SizeKB KB"
        Write-Host "  Modified   : $ModTime UTC ($AgeDays days ago)"
    } else {
        Write-Host '  EXISTS     : NO - run Connect-IRT first' -ForegroundColor Yellow
        return [PSCustomObject[]]@()
    }

    # ---- Prerequisite checks ----
    $MsalAssembly = & $HostModule { Import-MsalAssembly }
    Write-Trace "MSAL assembly: $($MsalAssembly.FullName)"

    Write-Host "  MSAL ver   : $($MsalAssembly.GetName().Version)"

    $ModVerStr = if ($HostModule) { $HostModule.Version.ToString() } else {
        'not loaded (persistent cache registration disabled)'
    }
    Write-Host "  IRT module : $ModVerStr"

    # ---- Service definitions ----
    # Exchange and IPPS share client ID fb78d390 but use different resource scopes.
    #
    # Candidates maps each login host to one or more cloud candidates. login.microsoftonline.us
    # serves BOTH GCC High (USGov) and DoD (USGovDoD): they share the token endpoint but use
    # different resource hosts (e.g. graph.microsoft.us vs dod-graph.microsoft.us). A cached
    # account's Environment can't tell the two apart, so list both and let the token test pick
    # whichever the tenant actually issues a token for - that reveals the real cloud.
    #
    # All scopes use /.default (not a specific scope like User.Read). Graph CLI Tools is a
    # dynamic-consent app: the cached refresh token is bound to the scopes Connect-IRT
    # consented. A silent force-refresh for a literal scope outside that set returns
    # AADSTS65001 (consent required) even when a superset like User.ReadWrite.All is granted,
    # because consent is evaluated per scope string. /.default reuses existing consent and
    # never prompts, keeping this a pure refresh-token validity check.
    $Services = [ordered]@{
        Graph    = @{
            ClientId   = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Graph CLI Tools
            Candidates = @{
                'login.microsoftonline.com'        = @(
                    @{ Cloud = 'Commercial'; Scope = 'https://graph.microsoft.com/.default' }
                )
                'login.microsoftonline.us'         = @(
                    @{ Cloud = 'USGov'; Scope = 'https://graph.microsoft.us/.default' }
                    @{ Cloud = 'USGovDoD'; Scope = 'https://dod-graph.microsoft.us/.default' }
                )
                'login.partner.microsoftonline.cn' = @(
                    @{ Cloud = 'China'
                        Scope = 'https://microsoftgraph.chinacloudapi.cn/.default' }
                )
            }
        }
        Exchange = @{
            ClientId   = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO first-party app
            Candidates = @{
                'login.microsoftonline.com'        = @(
                    @{ Cloud = 'Commercial'; Scope = 'https://outlook.office365.com/.default' }
                )
                'login.microsoftonline.us'         = @(
                    @{ Cloud = 'USGov'; Scope = 'https://outlook.office365.us/.default' }
                    @{ Cloud = 'USGovDoD'; Scope = 'https://outlook-dod.office365.us/.default' }
                )
                'login.partner.microsoftonline.cn' = @(
                    @{ Cloud = 'China'; Scope = 'https://partner.outlook.cn/.default' }
                )
            }
        }
        IPPS     = @{
            ClientId   = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # same app as Exchange
            Candidates = @{
                'login.microsoftonline.com'        = @(
                    @{ Cloud = 'Commercial'
                        Scope = 'https://dataservice.o365filtering.com/.default' }
                )
                # GCC High and DoD share the same IPPS resource, so one candidate covers
                # both; the token alone can't say which, hence the 'USGov/DoD' label.
                'login.microsoftonline.us'         = @(
                    @{ Cloud = 'USGov/DoD'
                        Scope = 'https://dataservice.o365filtering.com/.default' }
                )
                'login.partner.microsoftonline.cn' = @()  # IPPS unavailable in China
            }
        }
    }

    $CloudNames = @{
        'login.microsoftonline.com'        = 'Commercial'
        'login.microsoftonline.us'         = 'USGov/USGovDoD'
        'login.partner.microsoftonline.cn' = 'China'
    }

    # ---- Build one MSAL PublicClientApp per (ClientId, cloud authority) ----
    # MSAL's GetAccountsAsync only returns accounts whose Environment matches the app's
    # configured authority host (plus known aliases). A single commercial 'common' app
    # therefore hides GCC High/DoD (login.microsoftonline.us) and China
    # (login.partner.microsoftonline.cn) accounts entirely. Build one app per cloud so
    # accounts from every cloud are enumerated. Persistent cache is registered via
    # Register-MsalCache, reached with NewBoundScriptBlock so private module functions
    # are in scope. Key format: "<ClientId>|<LoginHost>".
    $LoginHosts = @(
        'login.microsoftonline.com'
        'login.microsoftonline.us'
        'login.partner.microsoftonline.cn'
    )
    $AppByClientIdCloud = @{}
    $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
    $UniqueClientIds = $Services.Values | Select-Object -ExpandProperty ClientId -Unique

    foreach ($Cid in $UniqueClientIds) {
        foreach ($LoginHost in $LoginHosts) {
            Write-Trace "Building MSAL app: ClientId=$Cid Cloud=$LoginHost"
            try {
                $NewApp = $PcaBuilder::Create($Cid).
                WithAuthority("https://$LoginHost/common").
                WithRedirectUri('http://localhost').
                Build()

                if ($HostModule) {
                    $RegSb = $HostModule.NewBoundScriptBlock({
                            param($App, $Path)
                            Register-MsalCache -App $App -CachePath $Path
                        })
                    & $RegSb $NewApp $CachePath
                    Write-Trace "Persistent cache registered for $Cid ($LoginHost)"
                } else {
                    Write-Trace "Skipping cache registration (IRT module not loaded)"
                }

                $AppByClientIdCloud["$Cid|$LoginHost"] = $NewApp
            } catch {
                Write-Warning "Failed to initialize MSAL app (ClientId $Cid, $LoginHost): $_"
            }
        }
    }

    # ---- Enumerate accounts and test tokens per service ----
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $SvcNum = 0

    foreach ($SvcName in $Services.Keys) {
        $SvcNum++
        $Svc = $Services[$SvcName]
        $ShortId = $Svc.ClientId.Substring(0, 8)
        Write-Trace "[$SvcNum/$($Services.Count)] $SvcName  (clientId: $ShortId...)"

        # One cloud-scoped app per login host; each returns only its own cloud's
        # accounts, so iterate all clouds to cover commercial + sovereign tenants.
        foreach ($LoginHost in $LoginHosts) {
            $App = $AppByClientIdCloud["$($Svc.ClientId)|$LoginHost"]
            if (-not $App) { continue }

            try {
                $Accounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
            } catch {
                Write-Warning "GetAccountsAsync failed for $SvcName ($LoginHost): $_"
                continue
            }

            if ($Accounts.Count -eq 0) {
                Write-Trace "${SvcName} [$LoginHost]: no accounts cached"
                continue
            }
            Write-Trace "${SvcName} [$LoginHost]: $($Accounts.Count) account(s) in cache"

            foreach ($Acct in $Accounts) {
                $Tid = $Acct.HomeAccountId.TenantId
                $Oid = $Acct.HomeAccountId.ObjectId
                $Env = $Acct.Environment
                $Cloud = if ($CloudNames[$Env]) { $CloudNames[$Env] } else { $Env }
                $Candidates = $Svc.Candidates[$Env]

                Write-Trace "    $($Acct.Username)  [$Cloud]  tid=$Tid"

                $Row = [PSCustomObject]@{
                    Service           = $SvcName
                    Username          = $Acct.Username
                    TenantId          = $Tid
                    AccountObjectId   = $Oid
                    CloudEnvironment  = $Env
                    Cloud             = $Cloud
                    RefreshTokenValid = $null
                    FailureReason     = $null
                    TokenExpiry       = $null
                    ExtendedExpiry    = $null
                    TokenScopes       = $null
                    TokenAudience     = $null
                    TokenIssuer       = $null
                    TokenIssuedAt     = $null
                }

                if (-not $SkipTokenTest) {
                    if (-not $Candidates -or $Candidates.Count -eq 0) {
                        $Row.RefreshTokenValid = $false
                        $Row.FailureReason = "No test scope defined for cloud: $Cloud"
                    } else {
                        # login.microsoftonline.us serves GCC High AND DoD with different
                        # resource hosts; the account Environment can't tell them apart. Try
                        # each candidate and accept the first that returns a token - that
                        # reveals the real cloud. Only one ever succeeds for a given tenant.
                        $Failures = [System.Collections.Generic.List[string]]::new()
                        foreach ($Cand in $Candidates) {
                            Write-Trace ("AcquireTokenSilent: svc=$SvcName env=$Env " +
                                "cloud=$($Cand.Cloud) tid=$Tid")
                            try {
                                $SilentResult = $App.AcquireTokenSilent(
                                    [string[]]@($Cand.Scope), $Acct).
                                WithAuthority("https://$Env/$Tid").
                                WithForceRefresh($true).
                                ExecuteAsync().GetAwaiter().GetResult()

                                $ExpiresOn = $SilentResult.ExpiresOn.UtcDateTime
                                $Row.Cloud = $Cand.Cloud
                                $Row.RefreshTokenValid = $true
                                $Row.FailureReason = $null
                                $Row.TokenExpiry = $ExpiresOn.ToString('yyyy-MM-dd HH:mm')
                                $ExtDateTime = $SilentResult.ExtendedExpiresOn.UtcDateTime
                                $Row.ExtendedExpiry = $ExtDateTime.ToString('yyyy-MM-dd HH:mm')
                                $Row.TokenScopes = ($SilentResult.Scopes -join ' ')

                                $Claims = Expand-Jwt -Token $SilentResult.AccessToken
                                if ($Claims) {
                                    $Row.TokenAudience = $Claims.aud
                                    $Row.TokenIssuer = $Claims.iss
                                    if ($Claims.iat) {
                                        $IatEpoch = [long]$Claims.iat
                                        $Iat = [DateTimeOffset]::FromUnixTimeSeconds($IatEpoch)
                                        $IatUtc = $Iat.UtcDateTime
                                        $Row.TokenIssuedAt = $IatUtc.ToString('yyyy-MM-dd HH:mm')
                                    }
                                }

                                $Ttl = [Math]::Round(($ExpiresOn - $Now).TotalMinutes, 1)
                                Write-Trace ("      VALID [$($Cand.Cloud)] - expires " +
                                    "$($ExpiresOn.ToString('HH:mm')) UTC (in $Ttl min)")
                                break
                            } catch {
                                $Inner = if ($_.Exception.InnerException) {
                                    $_.Exception.InnerException.Message
                                } else { $_.Exception.Message }
                                $Failures.Add("$($Cand.Cloud): $Inner")
                                Write-Trace "      FAILED [$($Cand.Cloud)] - $Inner"
                            }
                        }

                        if (-not $Row.RefreshTokenValid) {
                            $Row.RefreshTokenValid = $false
                            $Row.FailureReason = $Failures -join ' | '
                            Write-Trace '      FAILED all candidates (see FailureReason)'
                        }
                    }
                }

                $Results.Add($Row)
            }
        }
    }

    return $Results.ToArray()
}
