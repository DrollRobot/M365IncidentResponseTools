function Connect-IRTExchange {
    <#
    .SYNOPSIS
    Connects to Exchange Online.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER UserPrincipalName
    Optional. The UserPrincipalName (Email) for the user account. When provided
    with -AccessToken (e.g. in runspace re-connections), this value is passed to
    Connect-ExchangeOnline. For interactive flows the UPN is derived from the
    MSAL token result automatically.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, USGovDoD, China.
    Mandatory - Connect-IRT resolves this via OIDC discovery and passes it in.

    .PARAMETER AccessToken
    A pre-existing access token to use for connection. Intended for use within
    runspaces where interactive authentication is not possible.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the EXO first-party app
    (fb78d390-0c51-40cd-8e17-fdbfab77341b).

    .PARAMETER MsalCachePath
    Override the path for the persistent MSAL token cache file. Defaults to
    $Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

    .NOTES
    Version: 3.0.0
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

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b',  # EXO first-party app

        [string] $MsalCachePath = $Global:IRT_Config.MsalCachePath
    )

    begin {
        $CloudConfig = $Global:IRT_CloudEnvironments[$Cloud]
        $ExchangeScope = $CloudConfig.Exchange
        $Authority = "$($CloudConfig.LoginHost)/$TenantId"
        $Scopes = [string[]]@($ExchangeScope)

        # Bare login host (no scheme) used to match cached MSAL accounts to this cloud.
        $ExpectedLoginHost = $CloudConfig.LoginHost.Replace('https://', '')
        # Expected token audience host (the Exchange resource for this cloud, e.g.
        # outlook.office365.us). Used to confirm a token is for the right cloud.
        $ExpectedExchangeHost = ([uri]($ExchangeScope -replace '/\.default$', '')).Host

        $ExoClientId = $ClientId
        $App = $null  # built lazily; not needed when -AccessToken provided

        Write-PSFMessage -Level 8 -Message "Connect-IRTExchange: TenantId=$TenantId, Cloud=$Cloud, Authority=$Authority, Force=$Force, Silent=$Silent"
    }

    process {

        # ---------- Setup: scope, authority ----------

        # Local helper - reads $App, $Scopes, $Silent, and $ExpectedLoginHost from the
        # enclosing scope. Tries silent refresh first, then interactive auth.
        function Get-ExchangeToken {
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
                    Write-PSFMessage -Level 8 -Message "Attempting silent Exchange token acquisition for: $($Match.Username) (env: $($Match.Environment))"
                    return $App.AcquireTokenSilent($Scopes, $Match).
                        ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    Write-PSFMessage -Level 8 -Message "Silent Exchange token acquisition failed: $_"
                }
            } else {
                Write-PSFMessage -Level 8 -Message "No cached account matches expected environment '$ExpectedLoginHost'; will authenticate interactively."
            }

            if ($Silent) {
                throw ('Silent Exchange token refresh failed and ' +
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
                Write-PSFMessage -Level 8 -Message "Interactive Exchange token acquisition succeeded. Account: $($Result.Account.Username), Expiry: $($Result.ExpiresOn)"
                return $Result
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        # ---------- Phase 1: token ----------
        # Three sources, in priority order:
        #   1. -AccessToken parameter (caller already has one - runspace reconnect)
        #   2. cached session token (if not forced, same tenant, not expired)
        #   3. fresh acquisition (silent refresh inside the helper if possible)

        $NeedNewToken = $false

        if ($AccessToken) {
            Write-PSFMessage -Level 8 -Message "Using caller-supplied Exchange access token."
            $Token = $AccessToken
            $Upn = $UserPrincipalName
        } elseif (-not $Force -and
            $Global:IRT_Session -and
            $Global:IRT_Session.Exchange -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $Global:IRT_Session.Exchange.Token -and
            -not (Test-TokenExpired -Token $Global:IRT_Session.Exchange.Token)) {
            $Token = $Global:IRT_Session.Exchange.Token
            $Upn = $Global:IRT_Session.Exchange.UserPrincipalName
            $App = $Global:IRT_Session.Exchange.PublicClientApplication
            Write-PSFMessage -Level 8 -Message "Using cached Exchange token from session (account: $Upn)."
        } else {
            # MSAL setup, only needed when we actually have to acquire.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            if (-not $GraphModule) {
                throw 'Microsoft.Graph.Authentication must be imported' +
                ' before acquiring an Exchange token.'
            }
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

            $AppClientId = $Global:IRT_Session.Exchange.PublicClientApplication?.AppConfig?.ClientId
            $SameClient =
            $Global:IRT_Session -and
            $Global:IRT_Session.Exchange -and
            $Global:IRT_Session.Exchange.PublicClientApplication -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $AppClientId -eq $ClientId
            if ($SameClient) {
                Write-PSFMessage -Level 8 -Message "Reusing existing MSAL public client app (ClientId: $ClientId)."
                $App = $Global:IRT_Session.Exchange.PublicClientApplication
            } else {
                Write-PSFMessage -Level 8 -Message "Building new MSAL public client app (ClientId: $ExoClientId, Authority: $Authority)."
                $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
                $NewApp = $PcaBuilder::Create($ExoClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
                if ($Global:IRT_Config.EnableTokenCache) {
                    try {
                        Register-MsalCache -App $NewApp -CachePath $MsalCachePath
                        Write-PSFMessage -Level 8 -Message "MSAL persistent token cache registered at: $MsalCachePath"
                    }
                    catch { Write-IRT "Persistent token cache unavailable: $_" -Level Warn }
                }
                $App = $NewApp
            }

            if (
                -not $AccessToken -and
                $Global:IRT_Session -and
                $Global:IRT_Session.Exchange -and
                $Global:IRT_Session.Exchange.Token
            ) {
                Write-IRT "Refreshing expired Exchange token for tenant $TenantId..." -Level Warn
            }
            Write-PSFMessage -Level 8 -Message "Acquiring Exchange token (silent from MSAL cache, else interactive)."
            $TokenResult = Get-ExchangeToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Exchange access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $NeedNewToken = $true
            Write-PSFMessage -Level 8 -Message "Exchange token acquired for account: $Upn"
        }

        # ---------- Phase 1b: cloud validation ----------
        # Confirm the token's audience (aud) is the Exchange endpoint for this cloud (e.g.
        # outlook.office365.us for USGov). A wrong-cloud token passes expiry checks but is
        # rejected at use time. Env-filtered silent selection already prevents the MSAL
        # cache from returning a wrong-cloud token; this guards the caller-supplied and
        # session-cached paths.
        $TokenAud = (Get-TokenPayload -Token $Token).aud
        Write-PSFMessage -Level 8 -Message "Exchange token audience: $TokenAud | expected host: $ExpectedExchangeHost"

        if (-not $TokenAud) {
            Write-PSFMessage -Level 8 -Message "Could not decode token audience; skipping cloud validation."
        }
        elseif ($TokenAud -notlike 'http*') {
            Write-PSFMessage -Level 8 -Message "Token audience is not a URL ('$TokenAud'); skipping cloud validation."
        }
        elseif (([uri]$TokenAud).Host -ne $ExpectedExchangeHost) {
            if (-not $App) {
                # Caller-supplied token (runspace reconnect) - we can't re-acquire here.
                throw ("Exchange token audience '$TokenAud' does not match expected host " +
                    "'$ExpectedExchangeHost' for cloud '$Cloud'.")
            }
            Write-IRT ("Exchange token audience '$TokenAud' does not match the expected " +
                "host '$ExpectedExchangeHost'. Re-authenticating for the correct cloud.") -Level Warn
            $TokenResult = Get-ExchangeToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Exchange access token after cloud mismatch.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $NeedNewToken = $true
            $TokenAud = (Get-TokenPayload -Token $Token).aud
            if (([uri]$TokenAud).Host -ne $ExpectedExchangeHost) {
                throw ("Acquired Exchange token audience '$TokenAud' still does not match " +
                    "'$ExpectedExchangeHost'. Verify -Cloud '$Cloud' is correct for tenant $TenantId.")
            }
            Write-PSFMessage -Level 8 -Message "Re-acquired Exchange token audience now matches expected cloud."
        }

        # ---------- Phase 2: Connect-ExchangeOnline ----------
        # Connect if no existing connection, wrong tenant, or -Force.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' -and $_.TenantID -eq $TenantId }

        $NeedConnect = $Force -or -not $ExistingConnection
        Write-PSFMessage -Level 8 -Message "NeedNewToken: $NeedNewToken | NeedConnect: $NeedConnect (pre-verify)"

        # Trust but verify: Get-ConnectionInformation reflects local session state, which
        # can report "Connected" while the session is actually dead. If we think we're
        # connected, confirm with a cheap live call before trusting it.
        if (-not $NeedConnect) {
            try {
                $null = Get-OrganizationConfig -ErrorAction Stop
                Write-PSFMessage -Level 8 -Message "Live Exchange verification succeeded; existing connection is healthy."
            } catch {
                Write-PSFMessage -Level 8 -Message "Exchange session looked connected but a live call failed; forcing reconnect. Error: $_"
                $NeedConnect = $true
            }
        }

        if ($NeedConnect) {
            if ($ExistingConnection) {
                Write-PSFMessage -Level 8 -Message "Disconnecting existing Exchange connection before reconnect."
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            }
            $Params = @{
                AccessToken       = $Token
                UserPrincipalName = $Upn
                ShowBanner        = $false
            }
            $Params['ExchangeEnvironmentName'] = $CloudConfig.ExchangeEnv
            Write-PSFMessage -Level 8 -Message "Calling Connect-ExchangeOnline (ExchangeEnvironmentName: $($CloudConfig.ExchangeEnv))."
            Connect-ExchangeOnline @Params
            Write-PSFMessage -Level 8 -Message "Connect-ExchangeOnline completed."
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Exchange Online for tenant $TenantId." -Level Warn
        }

        $Result = [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
        Write-PSFMessage -Level 8 -Message "Connect-IRTExchange complete. Account: $Upn, TokenExpiry: $($Result.TokenExpiry)"
        return $Result
    }
}