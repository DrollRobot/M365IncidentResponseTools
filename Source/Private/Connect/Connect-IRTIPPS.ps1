function Connect-IRTIPPS {
    <#
    .SYNOPSIS
    Connects to Security & Compliance PowerShell (IPPS).

    .DESCRIPTION
    Acquires a portable access token via MSAL using EXO's first-party client ID
    and the IPPS audience, then passes it to Connect-IPPSSession via -AccessToken.
    This bypasses IPPS's internal MSAL token-acquisition path, which fails with
    an assembly version mismatch when the Microsoft.Graph.Authentication MSAL
    has been pre-loaded.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, USGovDoD, China.
    Mandatory - Connect-IRT resolves this via OIDC discovery and passes it in.

    .PARAMETER SearchOnly
    Use the search-only audience (https://dataservice.o365filtering.com) and
    pass -EnableSearchOnlySession to Connect-IPPSSession. Required for newer
    eDiscovery and retention cmdlets (New-ComplianceSearchAction,
    Set-RetentionCompliancePolicy, etc.). Defaults to $true.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the EXO/IPPS first-party app
    (fb78d390-0c51-40cd-8e17-fdbfab77341b).

    .PARAMETER MsalCachePath
    Override the path for the persistent MSAL token cache file. Defaults to
    $Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

    .NOTES
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [string] $UserPrincipalName,
        [Parameter(Mandatory)]
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,
        [string] $AccessToken,

        [bool]   $SearchOnly = $true,

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b',  # EXO/IPPS first-party app

        [string] $MsalCachePath = $Global:IRT_Config.MsalCachePath
    )

    begin {
        #region BEGIN

        # import modules
        $Imports = @(
            'ExchangeOnlineManagement'
            'Microsoft.Graph.Authentication'
            'PSFramework'
        )
        Import-IRTModule -Name $Imports

        $CloudConfig = $Global:IRT_Session.CloudConfig
        $IPPSScope = ($SearchOnly ? $CloudConfig.IPPSSearchOnly : $CloudConfig.Exchange)
        $Authority = "$($CloudConfig.LoginHost)/$TenantId"
        $Scopes = [string[]]@($IPPSScope)

        # Bare login host (no scheme) used to match cached MSAL accounts to this cloud.
        $ExpectedLoginHost = $CloudConfig.LoginHost.Replace('https://', '')

        $ExoClientId = $ClientId
        $App = $null  # built lazily; not needed when -AccessToken provided

        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTIPPS: TenantId=$TenantId, Cloud=$Cloud, " +
            "Authority=$Authority, SearchOnly=$SearchOnly, " +
            "Force=$Force, Silent=$Silent")
    }

    process {

        # ---------- Setup: scope, authority ----------

        # Local helper - reads $App, $Scopes, $Silent, and $ExpectedLoginHost from the
        # enclosing scope. Tries silent refresh first, then interactive auth.
        function Get-IppsToken {
            [OutputType('Microsoft.Identity.Client.AuthenticationResult')]
            param()
            $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
            Write-PSFMessage -Level 8 -Message "MSAL cached accounts: $($Cached.Count)"
            # Select the account that belongs to the cloud we're connecting to. The shared
            # persistent cache can hold accounts for several clouds; picking by environment
            # keeps silent acquisition cloud-correct. MSAL handles expiry/refresh.
            $Match = $Cached |
                Where-Object { $_.Environment -eq $ExpectedLoginHost } |
                Select-Object -First 1
            if ($Match) {
                try {
                    Write-PSFMessage -Level 8 -Message (
                        "Attempting silent IPPS token acquisition for: " +
                        "$($Match.Username) (env: $($Match.Environment))")
                    return $App.AcquireTokenSilent($Scopes, $Match).
                    ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    Write-PSFMessage -Level 8 -Message "Silent IPPS token acquisition failed: $_"
                }
            } else {
                Write-PSFMessage -Level 8 -Message (
                    "No cached account matches expected environment " +
                    "'$ExpectedLoginHost'; will authenticate interactively.")
            }

            if ($Silent) {
                throw ('Silent IPPS token refresh failed and ' +
                    'interactive auth is not allowed (-Silent).')
            }

            $Msg = 'A browser window has been opened for interactive sign-in. ' +
            'Please complete authentication to continue.'
            Write-IRT $Msg -Level Warn
            try {
                $Cts = [System.Threading.CancellationTokenSource]::new()
                $Task = $App.AcquireTokenInteractive($Scopes).ExecuteAsync($Cts.Token)
                try {
                    while (-not $Task.IsCompleted) { Start-Sleep -Milliseconds 250 }
                } finally {
                    $Cts.Cancel()
                    $Cts.Dispose()
                }
                $Result = $Task.GetAwaiter().GetResult()
                Write-PSFMessage -Level 8 -Message (
                    'Interactive IPPS token acquisition succeeded. ' +
                    "Account: $($Result.Account.Username), " +
                    "Expiry: $($Result.ExpiresOn)")
                return $Result
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        # ---------- Phase 1: token ----------
        # Three sources, in priority order:
        #   1. -AccessToken parameter (caller already has one - runspace reconnect)
        #   2. cached session token (same tenant, same SearchOnly mode, not expired)
        #   3. fresh acquisition (silent refresh inside the helper if possible -
        #      reuses EXO's MSAL cache when present, swapping audience silently)
        #
        # The SearchOnly check on the cached path matters: a token issued for
        # the search-only audience won't authenticate against the full audience
        # and vice versa.
        #
        # Note: there is no Phase 1b cloud (aud) validation here as in Graph/Exchange.
        # The search-only audience (dataservice.o365filtering.com) is identical across
        # all clouds, so aud can't distinguish cloud. Cloud-correctness is enforced by
        # the environment-filtered account selection in Get-IppsToken instead.

        $NeedNewToken = $false

        if ($AccessToken) {
            Write-PSFMessage -Level 8 -Message "Using caller-supplied IPPS access token."
            $Token = $AccessToken
            $Upn = $UserPrincipalName
        }
        elseif (
            -not $Force -and
            $Global:IRT_Session -and
            $Global:IRT_Session.IPPS -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $Global:IRT_Session.IPPS.SearchOnly -eq $SearchOnly -and
            $Global:IRT_Session.IPPS.Token -and
            -not (Test-TokenExpired -Token $Global:IRT_Session.IPPS.Token)
        ) {
            $Token = $Global:IRT_Session.IPPS.Token
            $Upn = $Global:IRT_Session.IPPS.UserPrincipalName
            $App = $Global:IRT_Session.IPPS.PublicClientApplication
            Write-PSFMessage -Level 8 -Message (
                "Using cached IPPS token from session (account: $Upn).")
        }
        else {
            # MSAL setup, only needed when we actually have to acquire.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            # if (-not $GraphModule) { # FIXME not needed now that we're explicitly importing?
            #     throw 'Microsoft.Graph.Authentication must be imported' +
            #     ' before acquiring an IPPS token.'
            # }
            $MsalDllParams = @{
                Path                = $GraphModule.ModuleBase
                ChildPath           = 'Dependencies'
                AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
            }
            $MsalDll = Join-Path @MsalDllParams
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                        Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
                Write-PSFMessage -Level 8 -Message "Loading MSAL assembly from: $MsalDll"
                Add-Type -Path $MsalDll
            }

            # Prefer EXO's MSAL app if available - same client ID = same token
            # cache = silent audience swap with no prompt. Fall back to IPPS's
            # cached app, then build a new one.
            $AppClientId = $Global:IRT_Session.Exchange.PublicClientApplication?.AppConfig?.ClientId
            $UseExoApp =
            $Global:IRT_Session -and
            $Global:IRT_Session.Exchange -and
            $Global:IRT_Session.Exchange.PublicClientApplication -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $AppClientId -eq $ClientId
            $UseIppsApp =
            $Global:IRT_Session -and
            $Global:IRT_Session.IPPS -and
            $Global:IRT_Session.IPPS.PublicClientApplication -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $Global:IRT_Session.IPPS.PublicClientApplication.AppConfig.ClientId -eq $ClientId
            $App = if ($UseExoApp) {
                Write-PSFMessage -Level 8 -Message (
                    'Reusing Exchange MSAL app for ' +
                    'silent IPPS audience swap.')
                $Global:IRT_Session.Exchange.PublicClientApplication
            } elseif ($UseIppsApp) {
                Write-PSFMessage -Level 8 -Message (
                    "Reusing existing IPPS MSAL app " +
                    "(ClientId: $ClientId).")
                $Global:IRT_Session.IPPS.PublicClientApplication
            } else {
                Write-PSFMessage -Level 8 -Message (
                    "Building new MSAL public client app " +
                    "(ClientId: $ExoClientId, Authority: $Authority).")
                $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
                $NewApp = $PcaBuilder::Create($ExoClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
                if ($Global:IRT_Config.EnableTokenCache) {
                    try {
                        Register-MsalCache -App $NewApp -CachePath $MsalCachePath
                        Write-PSFMessage -Level 8 -Message (
                            "MSAL persistent token cache " +
                            "registered at: $MsalCachePath")
                    }
                    catch { Write-IRT "Persistent token cache unavailable: $_" -Level Warn }
                }
                $NewApp
            }

            if (
                -not $AccessToken -and
                $Global:IRT_Session -and
                $Global:IRT_Session.IPPS -and
                $Global:IRT_Session.IPPS.Token
            ) {
                Write-IRT "Refreshing expired IPPS token for tenant $TenantId..." -Level Warn
            }
            Write-PSFMessage -Level 8 -Message (
                'Acquiring IPPS token (silent from MSAL ' +
                'cache, else interactive).')
            $TokenResult = Get-IppsToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire IPPS access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $NeedNewToken = $true
            Write-PSFMessage -Level 8 -Message "IPPS token acquired for account: $Upn"
        }

        # ---------- Phase 2: Connect-IPPSSession ----------
        # IPPS connections show up in Get-ConnectionInformation alongside EXO.
        # Distinguish by ConnectionUri matching the compliance endpoint - which differs
        # per cloud (outlook.com commercial, office365.us for USGov/DoD), so match both.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Connected' -and
                $_.TenantID -eq $TenantId -and
                $_.ConnectionUri -match 'compliance\.protection\.(outlook\.com|office365\.us)'
            }

        $NeedConnect = $Force -or -not $ExistingConnection
        Write-PSFMessage -Level 8 -Message "NeedNewToken: $NeedNewToken | NeedConnect: $NeedConnect"

        if ($NeedConnect) {
            if ($ExistingConnection) {
                Write-PSFMessage -Level 8 -Message (
                    'Disconnecting existing IPPS ' +
                    'connection before reconnect.')
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            }
            $Params = @{
                AccessToken       = $Token
                UserPrincipalName = $Upn
                ShowBanner        = $false
            }
            if ($SearchOnly) {
                $Params['EnableSearchOnlySession'] = $true
            }
            $Params['ConnectionUri'] = $CloudConfig.IPPS
            Write-PSFMessage -Level 8 -Message (
                'Calling Connect-IPPSSession ' +
                "(ConnectionUri: $($CloudConfig.IPPS), " +
                "SearchOnly: $SearchOnly).")
            Connect-IPPSSession @Params
            Write-PSFMessage -Level 8 -Message "Connect-IPPSSession completed."
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to IPPS for tenant $TenantId." -Level Warn
        }

        $Result = [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
            SearchOnly              = [bool]$SearchOnly
        }
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTIPPS complete. Account: $Upn, " +
            "TokenExpiry: $($Result.TokenExpiry)")
        return $Result
    }
}
