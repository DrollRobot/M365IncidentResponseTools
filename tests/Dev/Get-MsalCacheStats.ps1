#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

function Get-MsalCacheStats {
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
    . (Join-Path $PSScriptRoot 'Find-ModuleRoot.ps1')
    $HostModuleName = (Find-ModuleRoot -Path $PSScriptRoot).Name

    # import modules
    Import-Module $HostModuleName
    Import-Module Microsoft.Graph.Authentication
    $HostModule = Get-Module $HostModuleName

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
    $Now       = [System.DateTime]::UtcNow
    $CacheFile = Get-Item -Path $CachePath -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '=== IRT MSAL Token Cache ===' -ForegroundColor Cyan
    Write-Host "  Now (UTC)  : $($Now.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Cache path : $CachePath"
    if ($CacheFile) {
        $SizeKB  = [Math]::Round($CacheFile.Length / 1KB, 2)
        $ModTime = $CacheFile.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss')
        $AgeDays = [Math]::Round(($Now - $CacheFile.LastWriteTimeUtc).TotalDays, 1)
        Write-Host "  Size       : $SizeKB KB"
        Write-Host "  Modified   : $ModTime UTC ($AgeDays days ago)"
    } else {
        Write-Host '  EXISTS     : NO - run Connect-IRT first' -ForegroundColor Yellow
        return @()
    }

    # ---- Prerequisite checks ----
    $MsalAssembly = & $HostModule.NewBoundScriptBlock({ Import-MsalAssembly })
    Write-Trace "MSAL assembly: $($MsalAssembly.FullName)"

    Write-Host "  MSAL ver   : $($MsalAssembly.GetName().Version)"

    $ModVerStr = if ($HostModule) { $HostModule.Version.ToString() } else {
        'not loaded (persistent cache registration disabled)'
    }
    Write-Host "  IRT module : $ModVerStr"

    # ---- Service definitions ----
    # Exchange and IPPS share client ID fb78d390 but use different resource scopes.
    $Services = [ordered]@{
        Graph    = @{
            ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Graph CLI Tools
            Scopes   = @{
                'login.microsoftonline.com'        = 'https://graph.microsoft.com/User.Read'
                'login.microsoftonline.us'         = 'https://graph.microsoft.us/User.Read'
                'login.partner.microsoftonline.cn' = (
                    'https://microsoftgraph.chinacloudapi.cn/User.Read')
            }
        }
        Exchange = @{
            ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO first-party app
            Scopes   = @{
                'login.microsoftonline.com'        = 'https://outlook.office365.com/.default'
                'login.microsoftonline.us'         = 'https://outlook.office365.us/.default'
                'login.partner.microsoftonline.cn' = 'https://partner.outlook.cn/.default'
            }
        }
        IPPS     = @{
            ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # same app as Exchange
            Scopes   = @{
                'login.microsoftonline.com'        = (
                    'https://dataservice.o365filtering.com/.default')
                'login.microsoftonline.us'         = (
                    'https://dataservice.o365filtering.com/.default')
                'login.partner.microsoftonline.cn' = $null  # IPPS unavailable in China
            }
        }
    }

    $CloudNames = @{
        'login.microsoftonline.com'        = 'Commercial'
        'login.microsoftonline.us'         = 'USGov/USGovDoD'
        'login.partner.microsoftonline.cn' = 'China'
    }

    # ---- Build one MSAL PublicClientApp per unique ClientId ----
    # Uses 'common' authority so GetAccountsAsync returns accounts for all tenants.
    # Persistent cache is registered via Register-MsalCache, reached
    # with NewBoundScriptBlock so private module functions are in scope.
    $AppByClientId = @{}
    $PcaBuilder    = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
    $UniqueClientIds = $Services.Values | Select-Object -ExpandProperty ClientId -Unique

    foreach ($Cid in $UniqueClientIds) {
        Write-Trace "Building MSAL app: ClientId=$Cid"
        try {
            $NewApp = $PcaBuilder::Create($Cid).
                WithAuthority('https://login.microsoftonline.com/common').
                WithRedirectUri('http://localhost').
                Build()

            if ($HostModule) {
                $RegSb = $HostModule.NewBoundScriptBlock({
                    param($App, $Path)
                    Register-MsalCache -App $App -CachePath $Path
                })
                & $RegSb $NewApp $CachePath
                Write-Trace "Persistent cache registered for $Cid"
            } else {
                Write-Trace "Skipping cache registration (IRT module not loaded)"
            }

            $AppByClientId[$Cid] = $NewApp
        } catch {
            Write-Warning "Failed to initialize MSAL app (ClientId $Cid): $_"
        }
    }

    # ---- Enumerate accounts and test tokens per service ----
    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $SvcNum  = 0

    foreach ($SvcName in $Services.Keys) {
        $SvcNum++
        $Svc = $Services[$SvcName]
        $App = $AppByClientId[$Svc.ClientId]
        if (-not $App) { continue }

        Write-Host ''
        $ShortId = $Svc.ClientId.Substring(0, 8)
        Write-Host "[$SvcNum/3] $SvcName  (clientId: $ShortId...)" -ForegroundColor White

        try {
            $Accounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
        } catch {
            Write-Warning "GetAccountsAsync failed for ${SvcName}: $_"
            continue
        }
        Write-Trace "${SvcName}: $($Accounts.Count) account(s) in cache"

        if ($Accounts.Count -eq 0) {
            Write-Host '    (no accounts cached for this client ID)' -ForegroundColor DarkGray
            continue
        }

        foreach ($Acct in $Accounts) {
            $Tid       = $Acct.HomeAccountId.TenantId
            $Oid       = $Acct.HomeAccountId.ObjectId
            $Env       = $Acct.Environment
            $Cloud     = if ($CloudNames[$Env]) { $CloudNames[$Env] } else { $Env }
            $TestScope = $Svc.Scopes[$Env]

            Write-Host "    $($Acct.Username)  [$Cloud]  tid=$Tid" -ForegroundColor Gray

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
                if (-not $TestScope) {
                    $Row.RefreshTokenValid = $false
                    $Row.FailureReason = "No test scope defined for cloud: $Cloud"
                } else {
                    Write-Trace "AcquireTokenSilent: svc=$SvcName env=$Env tid=$Tid"
                    try {
                        $SilentResult = $App.AcquireTokenSilent(
                            [string[]]@($TestScope), $Acct).
                            WithAuthority("https://$Env/$Tid").
                            WithForceRefresh($true).
                            ExecuteAsync().GetAwaiter().GetResult()

                        $Row.RefreshTokenValid = $true
                        $Row.TokenExpiry       = $SilentResult.ExpiresOn.UtcDateTime
                        $Row.ExtendedExpiry    = $SilentResult.ExtendedExpiresOn.UtcDateTime
                        $Row.TokenScopes       = ($SilentResult.Scopes -join ' ')

                        $Claims = Expand-Jwt -Token $SilentResult.AccessToken
                        $Row.TokenAudience = $Claims?.aud
                        $Row.TokenIssuer   = $Claims?.iss
                        if ($Claims?.iat) {
                            $Iat = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$Claims.iat)
                            $Row.TokenIssuedAt = $Iat.UtcDateTime
                        }

                        $Ttl    = [Math]::Round(($Row.TokenExpiry - $Now).TotalMinutes, 1)
                        $ExpStr = $Row.TokenExpiry.ToString('HH:mm')
                        $OkMsg  = "      VALID - expires $ExpStr UTC (in $Ttl min)"
                        Write-Host $OkMsg -ForegroundColor Green
                    } catch {
                        $Inner = $_.Exception.InnerException?.Message
                        $Row.RefreshTokenValid = $false
                        $Row.FailureReason = $Inner ?? $_.Exception.Message
                        Write-Host "      FAILED - $($Row.FailureReason)" -ForegroundColor Red
                        Write-Trace "AcquireTokenSilent exception: $_"
                    }
                }
            }

            $Results.Add($Row)
        }
    }

    # ---- Summary table ----
    if ($Results.Count -gt 0) {
        Write-Host ''
        Write-Host '=== Summary ===' -ForegroundColor Cyan
        $ExpiryCol = @{
            N = 'TokenExpiry'
            E = {
                if ($_.TokenExpiry) { $_.TokenExpiry.ToString('yyyy-MM-dd HH:mm') }
                else { '-' }
            }
        }
        $Results | Format-Table -Property 'Service', 'Username', 'Cloud', 'TenantId',
            'RefreshTokenValid', $ExpiryCol -AutoSize
    }

    Write-Host ''
    return $Results
}
