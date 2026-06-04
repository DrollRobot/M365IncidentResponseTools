function Connect-IRTGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph with default incident response scopes.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, USGovDoD, China.
    Mandatory - Connect-IRT resolves this via OIDC discovery and passes it in.

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Browser
    Browser to use for URL opening. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the Microsoft Graph CLI Tools
    first-party app (14d82eec-204b-4c2f-b7e8-296a70dab67e).

    .PARAMETER MsalCachePath
    Override the path for the persistent MSAL token cache file. Defaults to
    $Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

    .NOTES
    Version: 3.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [Parameter(Mandatory)]
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,
        [Alias('AdditionalScopes')]
        [string[]] $AdditionalScope,

        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',  # Microsoft Graph CLI Tools

        [string] $MsalCachePath = $Global:IRT_Config.MsalCachePath
    )

    begin {
        #region BEGIN
        $DefaultScopes = @(
            'Application.ReadWrite.All'
            'AuditLog.Read.All'
            'AuditLogsQuery.Read.All'
            'BitLockerKey.Read.All'
            'CrossTenantInformation.ReadBasic.All'
            'DelegatedPermissionGrant.ReadWrite.All'
            'Device.ReadWrite.All'
            'DeviceLocalCredential.Read.All'
            'DeviceManagementApps.ReadWrite.All'
            'DeviceManagementConfiguration.ReadWrite.All'
            'DeviceManagementManagedDevices.ReadWrite.All'
            'DeviceManagementServiceConfig.ReadWrite.All'
            'Directory.AccessAsUser.All'
            'Directory.ReadWrite.All'
            'Domain.Read.All'
            'Group.ReadWrite.All'
            'GroupMember.ReadWrite.All'
            'IdentityRiskEvent.ReadWrite.All'
            'IdentityRiskyServicePrincipal.ReadWrite.All'
            'IdentityRiskyUser.ReadWrite.All'
            'Mail.ReadBasic.Shared'
            'Organization.Read.All'
            'Policy.Read.All'
            'Policy.Read.ConditionalAccess'
            'Policy.ReadWrite.Authorization'
            'RoleManagement.ReadWrite.Directory'
            'SecurityEvents.ReadWrite.All'
            'SecurityIncident.ReadWrite.All'
            'User-Mail.ReadWrite.All'
            'User-PasswordProfile.ReadWrite.All'
            'User-Phone.ReadWrite.All'
            'User.EnableDisableAccount.All'
            'User.ManageIdentities.All'
            'User.ReadWrite.All'
            'User.RevokeSessions.All'
            'UserAuthenticationMethod.ReadWrite'
            'UserAuthenticationMethod.ReadWrite.All'
            'UserAuthMethod-Passkey.ReadWrite.All'
        )
        $Scopes = if ($AdditionalScope) {
            $DefaultScopes + $AdditionalScope | Select-Object -Unique
        } else {
            $DefaultScopes
        }

        $CloudConfig = $Global:IRT_Session.CloudConfig
        $GraphBaseUrl = $CloudConfig.Graph
        $Authority = "$($CloudConfig.LoginHost)/$TenantId"
        # Bare login host (no scheme) used to match cached MSAL accounts and token issuers
        # to the cloud we're connecting to.
        $ExpectedLoginHost = $CloudConfig.LoginHost.Replace('https://', '')

        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTGraph: TenantId=$TenantId, Cloud=$Cloud, " +
            "Authority=$Authority, Scopes=$($Scopes.Count), " +
            "Force=$Force, Silent=$Silent")
    }

    process {

        # ---------- Setup: MSAL app, token-acquisition helper ----------

        # Ensure Microsoft.Graph.Authentication is loaded
        $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
        if (-not $GraphModule) {
            try {
                $Params = @{
                    Name        = 'Microsoft.Graph.Authentication'
                    Force       = $true
                    Scope       = 'Global'
                    ErrorAction = 'Stop'
                }
                Import-Module @Params
                $GraphModule = Get-Module Microsoft.Graph.Authentication
            } catch {
                throw "Failed to import Microsoft.Graph.Authentication. Error: $_"
            }
        }
        Write-PSFMessage -Level 8 -Message (
            "Microsoft.Graph.Authentication version: " +
            "$($GraphModule.Version)")

        # Ensure MSAL.NET is loaded
        $MsalAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }

        # if not, load it
        if (-not $MsalAssembly) {
            $MsalDllParams = @{
                Path                = $GraphModule.ModuleBase
                ChildPath           = 'Dependencies'
                AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
            }
            $MsalDll = Join-Path @MsalDllParams
            Write-PSFMessage -Level 8 -Message "Loading MSAL assembly from: $MsalDll"
            Add-Type -Path $MsalDll
        } else {
            Write-PSFMessage -Level 8 -Message (
                "MSAL assembly already loaded: " +
                "$($MsalAssembly.FullName)")
        }

        # build scopes urls
        $MsalScopes = [string[]]($Scopes | ForEach-Object { "$GraphBaseUrl/$_" })

        # test whether there's already a valid client. if not create one
        $SameClient =
        $Global:IRT_Session -and
        $Global:IRT_Session.Graph -and
        $Global:IRT_Session.Graph.PublicClientApplication -and
        $Global:IRT_Session.TenantId -eq $TenantId -and
        $Global:IRT_Session.Graph.PublicClientApplication.AppConfig.ClientId -eq $ClientId
        if ($SameClient) {
            Write-PSFMessage -Level 8 -Message (
                "Reusing existing MSAL public client app " +
                "(ClientId: $ClientId).")
            $App = $Global:IRT_Session.Graph.PublicClientApplication
        } else {
            Write-PSFMessage -Level 8 -Message (
                "Building new MSAL public client app " +
                "(ClientId: $ClientId, Authority: $Authority).")
            $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
            $NewApp = $PcaBuilder::Create($ClientId).WithAuthority($Authority).
            WithRedirectUri('http://localhost').Build()
            if ($Global:IRT_Config.EnableTokenCache) {
                try {
                    Register-MsalCache -App $NewApp -CachePath $MsalCachePath
                    Write-PSFMessage -Level 8 -Message (
                        "MSAL persistent token cache " +
                        "registered at: $MsalCachePath")
                }
                catch {
                    Write-IRT "Persistent token cache unavailable: $_" -Level Warn
                }
            }
            $App = $NewApp
        }

        # Local helper - reads $App, $MsalScopes, and $Silent from the enclosing scope.
        # Tries silent refresh first, then interactive auth.
        # -RequireConsent skips the silent path and forces a consent prompt.
        function Get-GraphToken {
            param(
                [switch] $RequireConsent,
                [Microsoft.Identity.Client.IAccount] $Account
            )
            if (-not $RequireConsent) {
                $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
                Write-PSFMessage -Level 8 -Message "MSAL cached accounts: $($Cached.Count)"
                # Select the account that belongs to the cloud we're connecting to. The
                # shared persistent cache can hold accounts for several clouds, so picking
                # by environment keeps silent acquisition cloud-correct without mutating the
                # cache. AcquireTokenSilent handles access-token expiry/refresh internally.
                $Match = $Cached |
                    Where-Object { $_.Environment -eq $ExpectedLoginHost } |
                    Select-Object -First 1
                if ($Match) {
                    try {
                        Write-PSFMessage -Level 8 -Message (
                            "Attempting silent token acquisition for: " +
                            "$($Match.Username) " +
                            "(env: $($Match.Environment))")
                        $Result = $App.AcquireTokenSilent($MsalScopes, $Match).
                        ExecuteAsync().GetAwaiter().GetResult()
                        Write-PSFMessage -Level 8 -Message (
                            'Silent token acquisition succeeded. ' +
                            "Expiry: $($Result.ExpiresOn)")
                        return $Result
                    } catch {
                        Write-PSFMessage -Level 8 -Message "Silent token acquisition failed: $_"
                    }
                } else {
                    Write-PSFMessage -Level 8 -Message (
                        "No cached account matches expected environment " +
                        "'$ExpectedLoginHost'; " +
                        'will authenticate interactively.')
                }
            }

            if ($Silent) {
                throw ('Silent Graph token refresh failed and ' +
                    'interactive auth is not allowed (-Silent).')
            }

            $Msg = 'A browser window has been opened for interactive sign-in. ' +
            'Please complete authentication to continue.'
            Write-IRT $Msg -Level Warn
            try {
                $Builder = $App.AcquireTokenInteractive($MsalScopes)
                if ($RequireConsent) {
                    $Builder = $Builder.WithPrompt([Microsoft.Identity.Client.Prompt]::Consent)
                }
                if ($Account) {
                    $Builder = $Builder.WithAccount($Account)
                }
                $Cts = [System.Threading.CancellationTokenSource]::new()
                $Task = $Builder.ExecuteAsync($Cts.Token)
                try {
                    while (-not $Task.IsCompleted) { Start-Sleep -Milliseconds 250 }
                } finally {
                    $Cts.Cancel()
                    $Cts.Dispose()
                }
                $Result = $Task.GetAwaiter().GetResult()
                Write-PSFMessage -Level 8 -Message (
                    'Interactive token acquisition succeeded. ' +
                    "Account: $($Result.Account.Username), " +
                    "Expiry: $($Result.ExpiresOn)")
                return $Result
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        # ---------- Phase 1: token ----------
        # Use cached if: not forced, same tenant, not expired, has all requested scopes.
        # Otherwise acquire a new one (silent refresh inside the helper if possible).
        # Cloud validation happens in Phase 1b below, after the token is in hand - that
        # way it covers BOTH the session token and one pulled from the MSAL cache.

        $NeedNewToken = $true

        if (-not $Force -and
            $Global:IRT_Session -and
            $Global:IRT_Session.Graph -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $Global:IRT_Session.Graph.Token -and
            -not (Test-TokenExpired -Token $Global:IRT_Session.Graph.Token)) {

            # Verify cached token covers all requested scopes via MgContext.
            $Ctx = Get-MgContext -ErrorAction SilentlyContinue
            $TokenScopeMissing = if ($Ctx -and $Ctx.TenantId -eq $TenantId) {
                $Scopes | Where-Object { $Ctx.Scopes -notcontains $_ }
            } else {
                $Scopes
            }

            if (-not $TokenScopeMissing) {
                $NeedNewToken = $false
                $Token = $Global:IRT_Session.Graph.Token
                $Account = $Global:IRT_Session.Graph.Account
                Write-PSFMessage -Level 8 -Message (
                    'Using cached Graph token from session ' +
                    "(cloud: $Cloud, account: $Account).")
            } else {
                Write-PSFMessage -Level 8 -Message (
                    "Cached token missing scopes " +
                    "($($TokenScopeMissing.Count)): " +
                    "$($TokenScopeMissing -join ', ')")
            }
        } else {
            $TokenExpiredStatus = if ($Global:IRT_Session.Graph.Token) {
                Test-TokenExpired -Token $Global:IRT_Session.Graph.Token
            } else {
                'n/a'
            }
            Write-PSFMessage -Level 8 -Message (
                'Session cache check skipped - ' +
                "Force=$Force, " +
                "SessionExists=$([bool]$Global:IRT_Session), " +
                "TokenExpired=$TokenExpiredStatus")
        }

        if ($NeedNewToken) {
            if ($Global:IRT_Session -and
                $Global:IRT_Session.Graph -and
                $Global:IRT_Session.Graph.Token
            ) {
                Write-IRT "Refreshing expired Graph token for tenant $TenantId." -Level Warn
            }
            # Pulls from the MSAL persistent cache (silent) first, then interactive.
            Write-PSFMessage -Level 8 -Message (
                'Acquiring Graph token (silent from MSAL ' +
                'cache, else interactive).')
            $TokenResult = Get-GraphToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Graph access token.'
            }
            $Token = $TokenResult.AccessToken
            $Account = $TokenResult.Account.Username
            Write-PSFMessage -Level 8 -Message "Token acquired for account: $Account"
        }

        # ---------- Phase 1b: cloud validation ----------
        # Confirm the token's audience (aud) is the Graph endpoint for the cloud we're
        # connecting to. aud is the resource the token was minted for - e.g.
        # https://graph.microsoft.us for USGov vs https://graph.microsoft.com for
        # Commercial - so it's the authoritative cloud signal. (The iss claim is NOT:
        # v1.0 Graph access tokens use https://sts.windows.net/{tenant}/ in every cloud.)
        #
        # A wrong-cloud token passes expiry/scope checks but fails at the Graph API with
        # InvalidCloudInstance / 401. Get-GraphToken already selects cached accounts by
        # environment, so silent acquisition can't hand back a wrong-cloud token; this
        # guards the session-token path and acts as a final assertion. On mismatch, a
        # clean re-acquire falls through to interactive sign-in for the correct cloud.
        $TokenAud = (Get-TokenPayload -Token $Token).aud
        Write-PSFMessage -Level 8 -Message "Token audience: $TokenAud | expected: $GraphBaseUrl"

        if (-not $TokenAud) {
            # Couldn't parse the token - don't punish an unparseable-but-valid token with
            # a forced interactive loop. Only a positively-wrong audience triggers a re-auth.
            Write-PSFMessage -Level 8 -Message (
                'Could not decode token audience; ' +
                'skipping cloud validation.')
        }
        elseif ($TokenAud -notlike 'http*') {
            # aud is a resource GUID (the same across clouds) rather than a URL, so it
            # can't distinguish cloud - skip rather than risk a false positive.
            Write-PSFMessage -Level 8 -Message (
                "Token audience is not a URL ('$TokenAud'); " +
                'skipping cloud validation.')
        }
        elseif ($TokenAud.TrimEnd('/') -ne $GraphBaseUrl.TrimEnd('/')) {
            Write-IRT ("Graph token audience '$TokenAud' does not match the expected " +
                "endpoint '$GraphBaseUrl'. Re-authenticating for the correct cloud.") -Level Warn

            $TokenResult = Get-GraphToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Graph access token after cloud mismatch.'
            }
            $Token = $TokenResult.AccessToken
            $Account = $TokenResult.Account.Username
            $NeedNewToken = $true  # force Phase 2 to reconnect with the corrected token

            # Re-validate. If it's still wrong, the authority itself is misconfigured.
            $TokenAud = (Get-TokenPayload -Token $Token).aud
            if ($TokenAud.TrimEnd('/') -ne $GraphBaseUrl.TrimEnd('/')) {
                throw ("Acquired Graph token audience '$TokenAud' still does not match " +
                    "'$GraphBaseUrl'. Verify -Cloud '$Cloud' is correct for tenant $TenantId.")
            }
            Write-PSFMessage -Level 8 -Message (
                'Re-acquired token audience now ' +
                'matches expected cloud.')
        }

        # ---------- Phase 2: Connect-MgGraph ----------
        # Connect if no context, wrong tenant, wrong cloud, missing scopes, or we just
        # acquired a fresh token (the existing MgContext is still bound to the old one).

        $Ctx = Get-MgContext -ErrorAction SilentlyContinue
        Write-PSFMessage -Level 8 -Message (
            'Preconnect MgContext - ' +
            "TenantId: $($Ctx.TenantId), " +
            "Environment: $($Ctx.Environment) " +
            "(expected: $($CloudConfig.GraphEnv)), " +
            "Account: $($Ctx.Account)")

        $NeedConnect = $NeedNewToken -or
        (-not $Ctx) -or # not connected
        ($Ctx.TenantId -ne $TenantId) -or # wrong tenant
        ($Ctx.Environment -ne $CloudConfig.GraphEnv) -or # wrong cloud
        [bool]($Scopes | Where-Object { $Ctx.Scopes -notcontains $_ }) # missing scopes

        Write-PSFMessage -Level 8 -Message (
            "NeedNewToken: $NeedNewToken | " +
            "NeedConnect: $NeedConnect (pre-verify)")

        # Trust but verify: the metadata checks above can all pass while the connection is
        # actually dead (e.g. a token the API rejects). Confirm with a real, lightweight
        # Graph call. The URI is RELATIVE so it follows the current context's cloud
        # endpoint - an absolute URI is what causes cross-cloud breakage. On failure, fall
        # through to the reconnect block below instead of returning a dead session.
        if (-not $NeedConnect) {
            try {
                $VerifyRequest = @{
                    Method      = 'GET'
                    Uri         = 'v1.0/organization?$select=id&$top=1'
                    ErrorAction = 'Stop'
                }
                $null = Invoke-MgGraphRequest @VerifyRequest
                Write-PSFMessage -Level 8 -Message (
                    'Live Graph verification succeeded; ' +
                    'existing connection is healthy.')
            } catch {
                Write-PSFMessage -Level 8 -Message (
                    'Metadata looked connected but a live Graph ' +
                    "call failed; forcing reconnect. Error: $_")
                $NeedConnect = $true
            }
        }

        if ($NeedConnect) {
            if ($Ctx) {
                Write-PSFMessage -Level 8 -Message (
                    'Disconnecting existing MgGraph ' +
                    'context before reconnect.')
                $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
            }
            $Secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
            $Params = @{
                AccessToken = $Secure
                NoWelcome   = $true
                Environment = $CloudConfig.GraphEnv
            }
            Write-PSFMessage -Level 8 -Message (
                'Calling Connect-MgGraph ' +
                "(Environment: $($CloudConfig.GraphEnv)).")
            $null = Connect-MgGraph @Params
        }

        # ---------- Phase 3: admin consent ----------
        # Verify tenant-wide consent. The token may have all scopes via per-user
        # consent while admin consent is missing, so this is independent of
        # MgContext.Scopes. Drive the dedicated /adminconsent endpoint if anything
        # is missing - that flow has no checkbox to miss, so consent persists
        # tenant-wide reliably.

        try {
            $MissingAdminScopes = Test-GraphAdminConsent -RequestedScope $Scopes
            Write-PSFMessage -Level 8 -Message (
                'Admin consent check: ' +
                "$($MissingAdminScopes.Count) scope(s) missing.")
        } catch {
            Write-PSFMessage -Level Warning -Message (
                'Admin consent check failed - skipping consent ' +
                'verification. Re-run Connect-IRT to retry. ' +
                "Error: $_")
            $MissingAdminScopes = @()
        }

        if ($MissingAdminScopes) {
            $ScopeCount = $MissingAdminScopes.Count
            Write-IRT "Admin consent missing tenant-wide for $ScopeCount scope(s):" -Level Warn
            Write-IRT "  $($MissingAdminScopes -join ', ')" -Level Warn

            $ConsentParams = @{
                TenantId    = $TenantId
                ClientId    = $ClientId
                Scope       = $MissingAdminScopes
                ResourceUri = $GraphBaseUrl
                Browser     = $Browser
            }
            if ($Cloud) { $ConsentParams['Cloud'] = $Cloud }
            if ($Private) { $ConsentParams['Private'] = $true }

            $null = Invoke-AdminConsent @ConsentParams

            # Verify the grant landed. Brief retry window for replication.
            $StillMissing = $Scopes
            for ($Attempt = 1; $Attempt -le 5 -and $StillMissing; $Attempt++) {
                Start-Sleep -Seconds 2
                try {
                    $StillMissing = Test-GraphAdminConsent -RequestedScope $Scopes
                } catch {
                    $StillMissing = $Scopes
                }
                Write-PSFMessage -Level 8 -Message (
                    "Consent replication check attempt $Attempt/5: " +
                    "$($StillMissing.Count) scope(s) still missing.")
            }

            if ($StillMissing) {
                $AllMissing = $StillMissing -join ', '
                Write-PSFMessage -Level Warning -Message (
                    "Tenant-wide grant not yet visible for: $AllMissing")
                Write-PSFMessage -Level Warning -Message (
                    'Replication may still be in flight; ' +
                    're-run Connect-IRT shortly to confirm.')
            } else {
                Write-IRT 'Admin consent granted tenant-wide.'
            }
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Graph for tenant $TenantId." -Level Warn
        }

        $Result = [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            Account                 = $Account
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTGraph complete. Account: $Account, " +
            "TokenExpiry: $($Result.TokenExpiry)")
        return $Result
    }
}
