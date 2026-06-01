#Region '.\Prefix.ps1' -1

# ModuleBuilder Notes: Code in this file will be prepended to the built .psm1 file.
#EndRegion '.\Prefix.ps1' 2
#Region '.\Private\Connect\Connect-IRTExchange.ps1' -1

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
    Cloud to connect to. Valid values: Commercial, USGov, China.
    When omitted the cloud defaults to Commercial.

    .PARAMETER AccessToken
    A pre-existing access token to use for connection. Intended for use within
    runspaces where interactive authentication is not possible.

    .PARAMETER Browser
    Browser to use for URL opening. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the EXO first-party app
    (fb78d390-0c51-40cd-8e17-fdbfab77341b).

    .PARAMETER MsalCachePath
    Override the path for the persistent MSAL token cache file. Defaults to
    $Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

    .NOTES
    Version: 3.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Browser', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Private', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Silent', Justification = 'Used inside scriptblock')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [string] $UserPrincipalName,
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud = 'Commercial',
        [string] $AccessToken,

        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

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

        $ExoClientId = $ClientId
        $App = $null  # built lazily; not needed when -AccessToken provided
    }

    process {

        # ---------- Setup: scope, authority ----------

        # Inline helper - closes over $App, $Scopes, $Browser, $Private, $Silent.
        # Tries silent refresh first, then interactive auth.
        $AcquireToken = {
            $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
            if ($Cached) {
                try {
                    return $App.AcquireTokenSilent($Scopes, ($Cached | Select-Object -First 1)).
                    ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    Write-Verbose "Silent Exchange token refresh failed: $_"
                }
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
                return $Task.GetAwaiter().GetResult()
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
            Write-Verbose 'Using cached Exchange token.'
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
                Add-Type -Path $MsalDll
            }

            $AppClientId = $Global:IRT_Session.Exchange.PublicClientApplication?.AppConfig?.ClientId
            $SameClient =
            $Global:IRT_Session -and
            $Global:IRT_Session.Exchange -and
            $Global:IRT_Session.Exchange.PublicClientApplication -and
            $Global:IRT_Session.TenantId -eq $TenantId -and
            $AppClientId -eq $ClientId
            $App = if ($SameClient) {
                $Global:IRT_Session.Exchange.PublicClientApplication
            } else {
                $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
                $NewApp = $PcaBuilder::Create($ExoClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
                if ($Global:IRT_Config.EnableTokenCache) {
                    try { Register-MsalCache -App $NewApp -CachePath $MsalCachePath }
                    catch { Write-IRT "Persistent token cache unavailable: $_" -Level Warn }
                }
                $NewApp
            }

            if (
                -not $AccessToken -and
                $Global:IRT_Session -and
                $Global:IRT_Session.Exchange -and
                $Global:IRT_Session.Exchange.Token
            ) {
                Write-IRT "Refreshing expired Exchange token for tenant $TenantId..." -Level Warn
            }
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Exchange access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $NeedNewToken = $true
        }

        # ---------- Phase 2: Connect-ExchangeOnline ----------
        # Connect if no existing connection, wrong tenant, or -Force.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' -and $_.TenantID -eq $TenantId }

        $NeedConnect = $Force -or -not $ExistingConnection

        if ($NeedConnect) {
            if ($ExistingConnection) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            }
            $Params = @{
                AccessToken       = $Token
                UserPrincipalName = $Upn
                ShowBanner        = $false
            }
            $Params['ExchangeEnvironmentName'] = $CloudConfig.ExchangeEnv
            Connect-ExchangeOnline @Params
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Exchange Online for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
    }
}
#EndRegion '.\Private\Connect\Connect-IRTExchange.ps1' 229
#Region '.\Private\Connect\Connect-IRTGraph.ps1' -1

function Connect-IRTGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph with default incident response scopes.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, China.
    When omitted the cloud defaults to Commercial.

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
        'PSReviewUnusedParameter', 'Silent', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud = 'Commercial',
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

        $CloudConfig = $Global:IRT_CloudEnvironments[$Cloud]
        $GraphBaseUrl = $CloudConfig.Graph
        $Authority = "$($CloudConfig.LoginHost)/$TenantId"
    }

    process {

        # ---------- Setup: MSAL app, token-acquisition helper ----------

        $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
        if (-not $GraphModule) {
            throw 'Microsoft.Graph.Authentication must be imported before connecting to Graph.'
        }
        $MsalDllParams = @{
            Path                = $GraphModule.ModuleBase
            ChildPath           = 'Dependencies'
            AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
        }
        $MsalDll = Join-Path @MsalDllParams
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
            Add-Type -Path $MsalDll
        }

        $MsalScopes = [string[]]($Scopes | ForEach-Object { "$GraphBaseUrl/$_" })

        # Reuse the cached MSAL app instance to preserve its token cache (refresh token).
        $SameClient =
        $Global:IRT_Session -and
        $Global:IRT_Session.Graph -and
        $Global:IRT_Session.Graph.PublicClientApplication -and
        $Global:IRT_Session.TenantId -eq $TenantId -and
        $Global:IRT_Session.Graph.PublicClientApplication.AppConfig.ClientId -eq $ClientId
        $App = if ($SameClient) {
            $Global:IRT_Session.Graph.PublicClientApplication
        } else {
            $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
            $NewApp = $PcaBuilder::Create($ClientId).
            WithAuthority($Authority).
            WithRedirectUri('http://localhost').
            Build()
            if ($Global:IRT_Config.EnableTokenCache) {
                try { Register-MsalCache -App $NewApp -CachePath $MsalCachePath }
                catch { Write-IRT "Persistent token cache unavailable: $_" -Level Warn }
            }
            $NewApp
        }

        # Inline helper - closes over $App, $MsalScopes, $Browser, $Private.
        # Tries silent refresh first, then interactive auth.
        # -RequireConsent skips the silent path and forces a consent prompt.
        $AcquireToken = {
            param(
                [switch] $RequireConsent,
                $Account
            )
            if (-not $RequireConsent) {
                $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
                if ($Cached) {
                    try {
                        return $App.AcquireTokenSilent(
                            $MsalScopes, ($Cached | Select-Object -First 1)
                        ).ExecuteAsync().GetAwaiter().GetResult()
                    } catch {
                        Write-Verbose "Silent Graph token refresh failed: $_"
                    }
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
                return $Task.GetAwaiter().GetResult()
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        # ---------- Phase 1: token ----------
        # Use cached if: not forced, same tenant, not expired, has all requested scopes.
        # Otherwise acquire a new one (silent refresh inside the helper if possible).

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
                Write-Verbose 'Using cached Graph token.'
            } else {
                Write-Verbose "Cached token missing scopes: $($TokenScopeMissing -join ', ')"
            }
        }

        if ($NeedNewToken) {
            if ($Global:IRT_Session -and
                $Global:IRT_Session.Graph -and
                $Global:IRT_Session.Graph.Token
            ) {
                Write-IRT "Refreshing expired Graph token for tenant $TenantId." -Level Warn
            }
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Graph access token.'
            }
            $Token = $TokenResult.AccessToken
            $Account = $TokenResult.Account.Username
        }

        # ---------- Phase 2: Connect-MgGraph ----------
        # Connect if no context, wrong tenant, missing scopes, or we just acquired
        # a fresh token (the existing MgContext is still bound to the old expired one).

        $Ctx = Get-MgContext -ErrorAction SilentlyContinue
        $NeedConnect = $NeedNewToken -or
        (-not $Ctx) -or
        ($Ctx.TenantId -ne $TenantId) -or
        [bool]($Scopes | Where-Object { $Ctx.Scopes -notcontains $_ })

        if ($NeedConnect) {
            if ($Ctx) {
                $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
            }
            $Secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
            $Params = @{
                AccessToken = $Secure
                NoWelcome = $true
                Environment = $CloudConfig.GraphEnv
            }
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
        } catch {
            Write-Warning ("Admin consent check failed - skipping consent verification. " +
                "Re-run Connect-IRT to retry. Error: $_")
            $MissingAdminScopes = @()
        }

        if ($MissingAdminScopes) {
            $ScopeCount = $MissingAdminScopes.Count
            Write-IRT "Admin consent missing tenant-wide for $ScopeCount scope(s):" -Level Warn
            Write-IRT "  $($MissingAdminScopes -join ', ')" -Level Warn

            $ConsentParams = @{
                TenantId    = $TenantId
                ClientId    = $ClientId
                Scope       = $MissingAdminScopes  # only request what's actually missing
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
            }

            if ($StillMissing) {
                $AllMissing = $StillMissing -join ', '
                Write-Warning ("Tenant-wide grant not yet visible for: $AllMissing")
                Write-Warning ('Replication may still be in flight; ' +
                    're-run Connect-IRT shortly to confirm.')
            } else {
                Write-IRT 'Admin consent granted tenant-wide.'
            }
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Graph for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            Account                 = $Account
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
    }
}
#EndRegion '.\Private\Connect\Connect-IRTGraph.ps1' 339
#Region '.\Private\Connect\Connect-IRTIPPS.ps1' -1

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Browser', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Private', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Silent', Justification = 'Used inside scriptblock')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [string] $UserPrincipalName,
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud = 'Commercial',
        [string] $AccessToken,

        [bool]   $SearchOnly = $true,

        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b',  # EXO/IPPS first-party app

        [string] $MsalCachePath = $Global:IRT_Config.MsalCachePath
    )

    begin {
        $CloudConfig = $Global:IRT_CloudEnvironments[$Cloud]
        $IPPSScope = ($SearchOnly ? $CloudConfig.IPPSSearchOnly : $CloudConfig.Exchange)
        $Authority = "$($CloudConfig.LoginHost)/$TenantId"
        $Scopes = [string[]]@($IPPSScope)

        $ExoClientId = $ClientId
        $App = $null  # built lazily; not needed when -AccessToken provided
    }

    process {

        # ---------- Setup: scope, authority ----------

        # Inline helper - closes over $App, $Scopes, $Browser, $Private, $Silent.
        # Tries silent refresh first, then interactive auth.
        $AcquireToken = {
            $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
            if ($Cached) {
                try {
                    return $App.AcquireTokenSilent($Scopes, ($Cached | Select-Object -First 1)).
                    ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    Write-Verbose "Silent IPPS token refresh failed: $_"
                }
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
                return $Task.GetAwaiter().GetResult()
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

        $NeedNewToken = $false

        if ($AccessToken) {
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
            Write-Verbose 'Using cached IPPS token.'
        }
        else {
            # MSAL setup, only needed when we actually have to acquire.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            if (-not $GraphModule) {
                throw 'Microsoft.Graph.Authentication must be imported' +
                ' before acquiring an IPPS token.'
            }
            $MsalDllParams = @{
                Path                = $GraphModule.ModuleBase
                ChildPath           = 'Dependencies'
                AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
            }
            $MsalDll = Join-Path @MsalDllParams
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                        Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
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
                $Global:IRT_Session.Exchange.PublicClientApplication
            } elseif ($UseIppsApp) {
                $Global:IRT_Session.IPPS.PublicClientApplication
            } else {
                $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
                $NewApp = $PcaBuilder::Create($ExoClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
                if ($Global:IRT_Config.EnableTokenCache) {
                    try { Register-MsalCache -App $NewApp -CachePath $MsalCachePath }
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
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire IPPS access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $NeedNewToken = $true
        }

        # ---------- Phase 2: Connect-IPPSSession ----------
        # IPPS connections show up in Get-ConnectionInformation alongside EXO.
        # Distinguish by ConnectionUri matching the compliance endpoint.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Connected' -and
                $_.TenantID -eq $TenantId -and
                $_.ConnectionUri -match 'compliance\.protection\.outlook\.com'
            }

        $NeedConnect = $Force -or -not $ExistingConnection

        if ($NeedConnect) {
            if ($ExistingConnection) {
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
            Connect-IPPSSession @Params
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to IPPS for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            TokenExpiry             = Get-TokenExpiry -Token $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
            SearchOnly              = [bool]$SearchOnly
        }
    }
}
#EndRegion '.\Private\Connect\Connect-IRTIPPS.ps1' 251
#Region '.\Private\Connect\Get-TokenExpiry.ps1' -1

function Get-TokenExpiry {
    <#
    .SYNOPSIS
    Returns the UTC expiry time from a JWT access token's exp claim, or $null if unreadable.

    .PARAMETER Token
    The JWT access token string to decode.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [Parameter(Mandatory)]
        [string] $Token
    )

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }

        # Base64url decode the payload segment (second part of the JWT)
        $payload = $parts[1]
        $padded = $payload.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '=' }
        }

        $bytes = [System.Convert]::FromBase64String($padded)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        $claims = $json | ConvertFrom-Json

        if (-not $claims.exp) { return $null }

        return [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
    }
    catch {
        return $null
    }
}
#EndRegion '.\Private\Connect\Get-TokenExpiry.ps1' 40
#Region '.\Private\Connect\Install-MsalExtensions.ps1' -1

function Install-MsalExtensions {
    <#
    .SYNOPSIS
    Ensures the Microsoft.Identity.Client.Extensions.Msal assembly is loaded.

    .DESCRIPTION
    Internal helper. If the assembly is not already loaded into the AppDomain,
    downloads the pinned .nupkg from nuget.org into the user's local app data
    folder (one-time), extracts the netstandard2.0 DLL, and loads it via
    Add-Type. Throws if the download or extraction fails, or if the loaded
    MSAL version is older than the pinned Extensions.Msal requires.

    .OUTPUTS
    [string] - the path to the loaded Extensions DLL.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', '',
        Justification = 'Internal helper; plural name reflects MSAL extensions assembly.')]
    param()

    # Pinned version. Bump when Graph SDK's bundled MSAL outpaces this.
    $Version = '4.66.2'
    $MsalFloor = [version]'4.61.3'  # Extensions.Msal 4.66.x minimum MSAL

    # Already loaded?
    $Loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client.Extensions.Msal' }
    if ($Loaded) {
        return $Loaded.Location
    }

    # Verify the MSAL DLL Graph loaded meets the Extensions floor.
    $Msal = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
        Select-Object -First 1
    if (-not $Msal) {
        throw 'Microsoft.Identity.Client is not loaded. ' +
        'Import a connect function (which loads MSAL) before calling Install-MsalExtensions.'
    }
    $MsalVersion = [version]$Msal.GetName().Version
    if ($MsalVersion -lt $MsalFloor) {
        throw ("Loaded MSAL version $MsalVersion is older than Extensions.Msal $Version requires " +
            "($MsalFloor). Update Microsoft.Graph.Authentication.")
    }

    # Target path.
    $JpParams = @{
        Path                = $env:LOCALAPPDATA
        ChildPath           = 'M365IncidentResponseTools'
        AdditionalChildPath = @('msal-extensions', $Version,
            'Microsoft.Identity.Client.Extensions.Msal.dll')
    }
    $DllPath = Join-Path @JpParams
    $DllDir = Split-Path $DllPath -Parent

    if (-not (Test-Path $DllPath)) {
        if (-not (Test-Path $DllDir)) {
            $null = New-Item -ItemType Directory -Path $DllDir -Force
        }

        # Download .nupkg from NuGet v3 flat container. The nupkg is just a ZIP.
        $LowerId = 'microsoft.identity.client.extensions.msal'
        $NupkgUrl = "https://api.nuget.org/v3-flatcontainer/$LowerId/$Version/" +
        "$LowerId.$Version.nupkg"
        $TempDir = [System.IO.Path]::GetTempPath()
        $TempNupkg = Join-Path -Path $TempDir -ChildPath "$LowerId.$Version.nupkg"
        $ExtractDir = Join-Path -Path $TempDir -ChildPath "$LowerId.$Version"

        Write-IRT "Downloading Microsoft.Identity.Client.Extensions.Msal $Version from nuget.org..."

        try {
            $IwrParams = @{
                Uri             = $NupkgUrl
                OutFile         = $TempNupkg
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            Invoke-WebRequest @IwrParams

            if (Test-Path $ExtractDir) {
                Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Expand-Archive -Path $TempNupkg -DestinationPath $ExtractDir -Force

            $SourceJp = @{
                Path                = $ExtractDir
                ChildPath           = 'lib'
                AdditionalChildPath = @('netstandard2.0',
                    'Microsoft.Identity.Client.Extensions.Msal.dll')
            }
            $SourceDll = Join-Path @SourceJp
            if (-not (Test-Path $SourceDll)) {
                throw "Expected DLL not found in extracted nupkg: $SourceDll"
            }
            Copy-Item -Path $SourceDll -Destination $DllPath -Force
        }
        finally {
            if (Test-Path $TempNupkg) {
                Remove-Item -Path $TempNupkg -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $ExtractDir) {
                Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Add-Type -Path $DllPath
    return $DllPath
}
#EndRegion '.\Private\Connect\Install-MsalExtensions.ps1' 115
#Region '.\Private\Connect\Invoke-AdminConsent.ps1' -1

function Invoke-AdminConsent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $TenantId,
        [Parameter(Mandatory)] [string]   $ClientId,
        [Parameter(Mandatory)] [Alias('Scopes')] [string[]] $Scope,
        [string] $ResourceUri = 'https://graph.microsoft.com',
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,
        [string] $Browser = 'default',
        [switch] $Private,

        [int] $TimeoutSeconds = 300
    )

    begin {
        $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Listener.Start()
        $Port = ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
        $RedirectUri = "http://localhost:$Port/"
    }

    process {
        try {
            $LoginHost = $Global:IRT_CloudEnvironments[$Cloud].LoginHost
            $State = [guid]::NewGuid().ToString('N')

            # Fully-qualify each scope with the resource URI, then space-delimit.
            # This is what makes /v2.0/adminconsent work for dynamic-consent apps
            # like Microsoft Graph Command Line Tools, where /.default would only
            # consent to statically configured permissions (User.Read in this case).
            $ScopeQuery = ($Scope | ForEach-Object { "$ResourceUri/$_" }) -join ' '

            $ConsentUrl = "$LoginHost/$TenantId/v2.0/adminconsent" +
            "?client_id=$ClientId" +
            "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
            "&state=$State" +
            "&scope=$([uri]::EscapeDataString($ScopeQuery))"

            Write-IRT 'Opening admin consent page in browser...' -Level Warn
            Write-IRT "  Granting tenant-wide consent for $($Scope.Count) scope(s)." -Level Warn
            Write-IRT '  Sign in as a Global Administrator and click Accept.' -Level Warn
            Open-Browser -Browser $Browser -Url $ConsentUrl -Private:$Private

            $Cts = [System.Threading.CancellationTokenSource]::new()
            $AcceptTask = $Listener.AcceptTcpClientAsync($Cts.Token)
            $Deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
            while (-not $AcceptTask.IsCompleted) {
                if ([datetime]::UtcNow -gt $Deadline) {
                    $Cts.Cancel()
                    throw "Timed out after $TimeoutSeconds seconds" +
                    " waiting for admin consent response."
                }
                Start-Sleep -Milliseconds 250
            }
            $Client = $AcceptTask.GetAwaiter().GetResult()

            try {
                $Stream = $Client.GetStream()
                $Reader = [System.IO.StreamReader]::new($Stream)
                $RequestLine = $Reader.ReadLine()

                $Body = '<html>' +
                '<body style="font-family:sans-serif;text-align:center;padding-top:4em">' +
                '<h2>Admin consent received.</h2>' +
                '<p>You may close this window and return to PowerShell.</p>' +
                '</body></html>'
                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                $Header = "HTTP/1.1 200 OK`r`n" +
                "Content-Type: text/html; charset=utf-8`r`n" +
                "Content-Length: $($Bytes.Length)`r`n" +
                "Connection: close`r`n`r`n"
                $HeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($Header)
                $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)
                $Stream.Write($Bytes, 0, $Bytes.Length)
                $Stream.Flush()
            } finally {
                $Client.Close()
            }

            if ($RequestLine -notmatch '^GET\s+(\S+)\s+HTTP') {
                throw "Malformed redirect request: $RequestLine"
            }
            $Path = $Matches[1]
            $Query = if ($Path -match '\?(.+)$') { $Matches[1] } else { '' }

            $Params = @{}
            foreach ($Pair in $Query -split '&') {
                $Kv = $Pair -split '=', 2
                if ($Kv.Count -eq 2) {
                    $Params[[uri]::UnescapeDataString($Kv[0])] = [uri]::UnescapeDataString($Kv[1])
                }
            }

            if ($Params['state'] -ne $State) {
                throw 'Admin consent response state mismatch - possible CSRF or stale request.'
            }
            if ($Params['error']) {
                $ErrCode = $Params['error']
                $ErrDesc = $Params['error_description']
                throw "Admin consent denied or failed: $ErrCode - $ErrDesc"
            }
            if ($Params['admin_consent'] -eq 'True') {
                return $true
            }
            throw "Unexpected admin consent response: $Query"
        }
        finally {
            if ($Cts) { $Cts.Cancel(); $Cts.Dispose() }
            $Listener.Stop()
        }
    }
}
#EndRegion '.\Private\Connect\Invoke-AdminConsent.ps1' 114
#Region '.\Private\Connect\Register-MsalCache.ps1' -1

function Register-MsalCache {
    <#
    .SYNOPSIS
    Attaches the IRT persistent token cache to an MSAL PublicClientApplication.

    .DESCRIPTION
    Internal helper. Loads Microsoft.Identity.Client.Extensions.Msal (downloading
    it on first use), then registers a DPAPI-encrypted on-disk cache against the
    supplied app's UserTokenCache. After registration, MSAL automatically
    persists refresh tokens between PowerShell sessions, so subsequent
    AcquireTokenSilent calls succeed without an interactive prompt for the life
    of the refresh token (up to ~90 days).

    .PARAMETER App
    The Microsoft.Identity.Client.IPublicClientApplication instance to attach
    the cache to.

    .PARAMETER CachePath
    Full path to the MSAL cache file. Defaults to $Global:IRT_Config.MsalCachePath.
    The default value is set in M365IncidentResponseTools.psm1.
    Override to use an alternate location (e.g. an isolated path for testing).

    .EXAMPLE
    Register-MsalCache -App $App

    .EXAMPLE
    Register-MsalCache -App $App -CachePath 'C:\Temp\test-msal.bin'

    .NOTES
    Version: 1.1.0
    Windows-only. On non-Windows platforms the function returns silently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $App,

        [string] $CachePath = $Global:IRT_Config.MsalCachePath
    )

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-IRT 'Persistent MSAL cache is currently Windows-only.' -Level Warn
        return
    }

    $null = Install-MsalExtensions

    $CacheDir = Split-Path $CachePath -Parent
    $CacheFile = Split-Path $CachePath -Leaf

    if (-not (Test-Path $CacheDir)) {
        $null = New-Item -ItemType Directory -Path $CacheDir -Force
    }

    # macOS/Linux fields are required by the builder even on Windows.
    $PropsBuilder =
    [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]::new(
        $CacheFile, $CacheDir)
    $PropsBuilder = $PropsBuilder.WithMacKeyChain(
        'Microsoft.M365IncidentResponseTools', 'MSALCache')
    $PropsBuilder = $PropsBuilder.WithLinuxKeyring(
        'com.microsoft.m365incidentresponsetools.tokencache',
        'default',
        'IRT MSAL token cache',
        [System.Collections.Generic.KeyValuePair[string, string]]::new('Version', '1'),
        [System.Collections.Generic.KeyValuePair[string, string]]::new('ProductGroup', 'IRT'))
    $StorageProps = $PropsBuilder.Build()

    $Helper =
    [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync(
        $StorageProps).GetAwaiter().GetResult()
    $Helper.RegisterCache($App.UserTokenCache)
}
#EndRegion '.\Private\Connect\Register-MsalCache.ps1' 74
#Region '.\Private\Connect\Test-GraphAdminConsent.ps1' -1

function Test-GraphAdminConsent {
    <#
    .SYNOPSIS
    Returns the set of requested scopes that are NOT already admin-consented
    tenant-wide for the Microsoft Graph Command Line Tools app.

    .DESCRIPTION
    Queries oauth2PermissionGrants for AllPrincipals (admin) grants and
    compares the consented scopes against the requested set. Returns an
    empty array if all scopes are admin-consented.

    Requires an existing Graph connection with at least
    DelegatedPermissionGrant.Read.All or Directory.Read.All.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias('RequestedScopes')]
        [string[]] $RequestedScope,

        [string] $ClientAppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',  # Graph CLI Tools
        [string] $ResourceAppId = '00000003-0000-0000-c000-000000000000' # Microsoft Graph
    )

    # Resolve SPs (these are tenant-scoped object IDs, not the app IDs)
    $ClientSpParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/servicePrincipals(appId='$ClientAppId')"
        ErrorAction = 'Stop'
    }
    $ClientSp = Invoke-MgGraphRequest @ClientSpParams
    $ResourceSpParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/servicePrincipals(appId='$ResourceAppId')"
        ErrorAction = 'Stop'
    }
    $ResourceSp = Invoke-MgGraphRequest @ResourceSpParams

    # Pull all AllPrincipals grants for this client/resource pair.
    # In practice there's usually one, but multiple are possible if
    # admins consented in batches.
    $Filter = "clientId eq '$($ClientSp.id)' and " +
    "resourceId eq '$($ResourceSp.id)' and " +
    "consentType eq 'AllPrincipals'"
    $Encoded = [uri]::EscapeDataString($Filter)
    $GrantsParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/oauth2PermissionGrants?`$filter=$Encoded"
        ErrorAction = 'Stop'
    }
    $Grants = Invoke-MgGraphRequest @GrantsParams

    # scope is a space-delimited string per grant; flatten across grants
    $Granted = @($Grants.value | ForEach-Object { $_.scope -split '\s+' } |
            Where-Object { $_ } | Select-Object -Unique)

    # Return the missing ones (case-insensitive compare)
    $RequestedScope | Where-Object { $Granted -notcontains $_ }
}
#EndRegion '.\Private\Connect\Test-GraphAdminConsent.ps1' 60
#Region '.\Private\Connect\Test-TokenExpired.ps1' -1

function Test-TokenExpired {
    <#
    .SYNOPSIS
    Returns $true if a JWT access token has expired or is within the buffer window of expiry.

    .PARAMETER Token
    The JWT access token string to evaluate.

    .PARAMETER BufferSeconds
    Number of seconds before the actual expiry time to treat the token as expired.
    Defaults to 300 (5 minutes) to avoid using a token that expires mid-operation.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter( Mandatory )]
        [string] $Token,

        [int] $BufferSeconds = 300
    )

    $expiry = Get-TokenExpiry -Token $Token
    if ($null -eq $expiry) { return $true }

    $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)
    return $expiry -le $threshold
}
#EndRegion '.\Private\Connect\Test-TokenExpired.ps1' 28
#Region '.\Private\Device\Set-IRTDeviceEnabled.ps1' -1

function Set-IRTDeviceEnabled {
    <#
	.SYNOPSIS
	Set AccountEnabled property on Entra device(s). Called by Disable-IRTDevice and Enable-IRTDevice.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $DeviceObject -or $DeviceObject.Count -eq 0 ) {

            # get from global variables
            $ScriptDeviceObjects = @( $Global:IRT_DeviceObjects )

            # if none found, exit
            if ( -not $ScriptDeviceObjects -or $ScriptDeviceObjects.Count -eq 0 ) {
                throw "No device objects passed or found in global variables."
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }

        # variables
        $GetProperties = @(
            'accountEnabled'
            'displayName'
            'deviceId'
            'id'
            'operatingSystem'
            'operatingSystemVersion'
        )
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'DeviceId'
            'OperatingSystem'
            'Id'
        )

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
    }

    process {

        foreach ( $ScriptDeviceObject in $ScriptDeviceObjects ) {

            # get the Entra directory object ID
            $EntraId = $ScriptDeviceObject.Entra?.Id

            if ( -not $EntraId ) {
                $DevName = $ScriptDeviceObject.DisplayName
                Write-IRT "No Entra record for: $DevName. Skipping." -Level Warn
                continue
            }

            # disable/enable device
            Write-IRT "$($Action.TrimEnd('e'))ing device account..."
            if ($PSCmdlet.ShouldProcess($ScriptDeviceObject.DisplayName, "$Action device")) {
                Update-MgDevice -DeviceId $EntraId -AccountEnabled:$Enabled
            }

            # get updated device object
            Write-IRT "Getting updated device properties."
            $NewDeviceObject = Get-MgDevice -DeviceId $EntraId -Property $GetProperties

            # display updated object
            $NewDeviceObject | Format-Table $DisplayProperties
        }
    }
}
#EndRegion '.\Private\Device\Set-IRTDeviceEnabled.ps1' 90
#Region '.\Private\Device\Show-GraphDeviceTree.ps1' -1

function Show-GraphDeviceTree {
    <#
    .SYNOPSIS
    Shows an Entra device object in a compact tree view.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [int] $Depth = 10
    )

    begin {
        $Exclude = @(
            'AdditionalProperties',
            'AlternativeSecurityIds',
            'RegisteredOwners',
            'RegisteredUsers'
        )
    }

    process {
        foreach ($DeviceObjectItem in $DeviceObject) {
            if ($null -eq $DeviceObjectItem) { continue }

            $Projected = $DeviceObjectItem | Select-Object -Property * -ExcludeProperty $Exclude

            $Params = @{
                Depth           = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
#EndRegion '.\Private\Device\Show-GraphDeviceTree.ps1' 41
#Region '.\Private\Entra\Convert-TrustType.ps1' -1

function Convert-TrustType {
    <#
	.SYNOPSIS
	Helper function for displaying logs. Accepts string or int, returns human readable description".

	.NOTES
    TrustType int values described here:
    https://learn.microsoft.com/en-us/azure/active-directory/devices/concept-azure-ad-join

	Version: 1.0.0
	#>
    [OutputType([string])]
    [CmdletBinding()]
    param (
        [psobject] $TrustType
    )

    begin {}

    process {

        if ($TrustType -is [int]) {
            switch ($TrustType) {
                0 { return "Az Registered" }
                1 { return "Az Joined" }
                2 { return "Hybrid Joined" }
                Default { return [string]$TrustType }
            }
        }
        elseif ($TrustType -is [string]) {
            switch ($TrustType.ToLower()) {
                "0" { return "Az Registered" }
                "1" { return "Az Joined" }
                "2" { return "Hybrid Joined" }
                "Hybrid Azure AD joined" { return "Hybrid Joined" }
                "Azure AD joined" { return "Az Joined" }
                "Azure AD registered" { return "Az Registered" }
                Default { return $TrustType }
            }
        }
        else {
            return [string]$TrustType
        }
    }
}
#EndRegion '.\Private\Entra\Convert-TrustType.ps1' 46
#Region '.\Private\Graph\Request-DirectoryRole.ps1' -1

function Request-DirectoryRole {
    <#
    .SYNOPSIS
    Requests directory roles from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID directory roles (with their members) from
    Microsoft Graph and caches the result in a session-scoped global variable. Subsequent
    callers that pass -Cached skip the API call and read from the cache. Used by
    Get-IRTAdminRole and the incident response playbook to avoid redundant Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'DisplayName'
            'Id'
            'RoleTemplateId'
        )
        $ExpandProperties = @( 'Members' )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_DirectoryRoles'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_DirectoryRoles }
                    'tablebyid' { return $Global:IRT_DirectoryRolesById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgDirectoryRole $Elapsed"
        $GdrParams = @{
            All            = $true
            Property       = $GetProperties
            ExpandProperty = $ExpandProperties
        }
        $Objects = Get-MgDirectoryRole @GdrParams |
            Select-Object ( $GetProperties + $ExpandProperties )

        # store in global variables
        $Global:IRT_DirectoryRoles = $Objects
        $Global:IRT_DirectoryRolesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_DirectoryRolesById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoles_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_DirectoryRoles }
            'tablebyid' { return $Global:IRT_DirectoryRolesById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-DirectoryRole.ps1' 97
#Region '.\Private\Graph\Request-DirectoryRoleTemplate.ps1' -1

function Request-DirectoryRoleTemplate {
    <#
    .SYNOPSIS
    Requests directory role templates from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID directory role templates from Microsoft Graph
    and caches the result in a session-scoped global variable. Used alongside
    Request-DirectoryRole to resolve role display names during admin role reporting.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'DisplayName'
            'Id'
        )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_DirectoryRoleTemplates'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_DirectoryRoleTemplates }
                    'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgDirectoryRoleTemplate $Elapsed"
        $GdrtParams = @{
            All      = $true
            Property = $GetProperties
        }
        $Objects = Get-MgDirectoryRoleTemplate @GdrtParams | Select-Object $GetProperties

        # store in global variables
        $Global:IRT_DirectoryRoleTemplates = $Objects
        $Global:IRT_DirectoryRoleTemplatesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_DirectoryRoleTemplatesById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoleTemplates_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_DirectoryRoleTemplates }
            'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-DirectoryRoleTemplate.ps1' 92
#Region '.\Private\Graph\Request-GraphDevice.ps1' -1

function Request-GraphDevice {
    <#
	.SYNOPSIS
    Requests Entra and Intune devices from Microsoft Graph.
    Builds combined device objects and caches them.

    Combined objects expose a flat set of convenience properties
    (DisplayName, DeviceId, OwnerUPN, etc.)
    plus an .Entra property (raw Graph device object) and an .Intune property
    (raw Intune managed-device object, or $null when the device is not enrolled
    / the tenant does not use Intune).

    Devices that appear only in Intune (no matching Entra record) are included with .Entra = $null.

	.NOTES
	Version: 2.0.0
	#>
    [OutputType([System.Object[]], [hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = (Get-Date).ToString($FileNameDateFormat)
    }

    process {

        # return cached data if available
        if ($Cached) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Devices' -ErrorAction SilentlyContinue
            if ($Variable) {
                switch ($Return) {
                    'objects' { return $Global:IRT_Devices }
                    'tablebyid' { return $Global:IRT_DevicesById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # --- Entra devices ---
        Write-Verbose "${FunctionName}: Get-MgDevice $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $EntraDevices = Get-MgDevice -All -ExpandProperty 'RegisteredOwners'

        # --- Intune devices (optional - skipped when not licensed / no permission) ---
        $IntuneDevices = Request-IntuneDevice   # returns $null when Intune is unavailable
        $TenantHasIntune = $null -ne $IntuneDevices

        # build local lookup keyed by AzureADDeviceId for the Entra-Intune join
        $IntuneDevicesByEntraId = @{}
        if ($TenantHasIntune) {
            foreach ($Device in $IntuneDevices) {
                if ($Device.AzureADDeviceId -and
                    $Device.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000'
                ) {
                    $IntuneDevicesByEntraId[$Device.AzureADDeviceId] = $Device
                }
            }
        }

        # --- Build combined objects ---
        $CombinedObjects = [System.Collections.Generic.List[PSObject]]::new()
        $SeenIntuneIds = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($EntraDevice in $EntraDevices) {

            $OwnerUpn = ($EntraDevice.RegisteredOwners | ForEach-Object {
                    $_.AdditionalProperties['userPrincipalName']
                }) -join ', '

            $IntuneDevice = $TenantHasIntune ?
            $IntuneDevicesByEntraId[$EntraDevice.DeviceId] : $null
            if ($IntuneDevice) { [void]$SeenIntuneIds.Add($IntuneDevice.Id) }

            $Combined = [PSCustomObject]@{
                DisplayName     = $EntraDevice.DisplayName
                DeviceId        = $EntraDevice.DeviceId   # AAD device GUID - links Entra, Intune
                OperatingSystem = $EntraDevice.OperatingSystem
                OwnerUPN        = $OwnerUpn
                AccountEnabled  = $EntraDevice.AccountEnabled
                Entra           = $EntraDevice
                Intune          = $IntuneDevice
            }
            $CombinedObjects.Add($Combined)
        }

        # --- Intune-only devices (managed but no Entra record, e.g. some BYOD scenarios) ---
        if ($TenantHasIntune) {
            foreach ($IntuneDevice in $IntuneDevices) {
                if ($SeenIntuneIds.Contains($IntuneDevice.Id)) { continue }

                $AadId = ($IntuneDevice.AzureADDeviceId -and
                    $IntuneDevice.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000') ?
                $IntuneDevice.AzureADDeviceId : $null

                $Combined = [PSCustomObject]@{
                    DisplayName     = $IntuneDevice.DeviceName
                    DeviceId        = $AadId
                    OperatingSystem = $IntuneDevice.OperatingSystem
                    OwnerUPN        = $IntuneDevice.UserPrincipalName
                    AccountEnabled  = $null
                    Entra           = $null
                    Intune          = $IntuneDevice
                }
                $CombinedObjects.Add($Combined)
            }
        }

        $Objects = @($CombinedObjects)

        # store in global variables
        $Global:IRT_Devices = $Objects
        $Global:IRT_DevicesById = [hashtable]::Synchronized(@{})
        foreach ( $Device in $Objects ) {
            if ( $Device.DeviceId ) { $Global:IRT_DevicesById[$Device.DeviceId] = $Device }
        }

        # export to file
        if ($Xml) {
            $FileName = "Devices_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 8 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Devices }
            'tablebyid' { return $Global:IRT_DevicesById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-GraphDevice.ps1' 148
#Region '.\Private\Graph\Request-GraphGroup.ps1' -1

function Request-GraphGroup {
    <#
    .SYNOPSIS
    Requests groups from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID groups from Microsoft Graph and caches the
    result in a session-scoped global variable keyed by object ID. Subsequent callers
    that pass -Cached skip the API call. Used by the playbook and role-reporting functions
    to resolve group membership without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'CreatedDateTime'
            'DisplayName'
            'Description'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
        )

    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Groups' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Groups }
                    'tablebyid' { return $Global:IRT_GroupsById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        Write-Verbose "${FunctionName}: Get-MgGroup $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $Params = @{
            All = $true
            Property = $GetProperties
        }
        $Objects = Get-MgGroup @Params | Select-Object $GetProperties

        # fetch all members for each group (ExpandProperty is limited to 20)
        foreach ( $o in $Objects ) {
            $Members = Get-MgGroupMember -GroupId $o.Id -All
            $o | Add-Member -NotePropertyName 'Members' -NotePropertyValue $Members
        }

        # store in global variables
        $Global:IRT_Groups = $Objects
        $Global:IRT_GroupsById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_GroupsById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "Groups_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Groups }
            'tablebyid' { return $Global:IRT_GroupsById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-GraphGroup.ps1' 98
#Region '.\Private\Graph\Request-GraphOauth2Grant.ps1' -1

function Request-GraphOauth2Grant {
    <#
    .SYNOPSIS
    Requests OAuth2 permission grants from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all delegated OAuth2 permission grants from Microsoft Graph
    and caches them in a session-scoped global variable keyed by client ID. Used by
    Get-IRTUserServicePrincipal and Find-IRTRiskyServicePrincipal to resolve which users
    have consented to which applications without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyclientid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        # $GetProperties = @(
        # )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_Oauth2Grants'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Oauth2Grants }
                    'tablebyclientid' { return $Global:IRT_Oauth2GrantsByClientId }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgOauth2PermissionGrant $Elapsed"
        $Objects = Get-MgOauth2PermissionGrant -All

        # store in global variables
        $Global:IRT_Oauth2Grants = $Objects
        $Global:IRT_Oauth2GrantsByClientId = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            $ClientId = $o.ClientId
            if ( $ClientId ) {
                if ( -not $Global:IRT_Oauth2GrantsByClientId.ContainsKey( $ClientId ) ) {
                    $Global:IRT_Oauth2GrantsByClientId[$ClientId] = @()
                }
                $Global:IRT_Oauth2GrantsByClientId[$ClientId] += $o
            }
        }

        # export to file
        if ($Xml) {
            $FileName = "Oauth2Grants_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Oauth2Grants }
            'tablebyclientid' { return $Global:IRT_Oauth2GrantsByClientId }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-GraphOauth2Grant.ps1' 93
#Region '.\Private\Graph\Request-GraphServicePrincipal.ps1' -1

function Request-GraphServicePrincipal {
    <#
    .SYNOPSIS
    Requests service principals from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID service principals from Microsoft Graph and
    caches the result in a session-scoped global variable keyed by app ID and object ID.
    Used by Get-IRTUserServicePrincipal, Find-IRTRiskyServicePrincipal, and Get-IRTAdminRole
    to resolve service principal identities without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyappid', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'AccountEnabled'
            'AdditionalProperties'
            'AppDescription'
            'AppDisplayName'
            'AppId'
            'AppOwnerOrganizationId'
            'Description'
            'DisplayName'
            'Id'
            'ReplyUrls'
            'ServicePrincipalType'
            'SignInAudience'
        )
    }

    process {

        # return cached data if available
        if ($Cached) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_ServicePrincipals'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ($Variable) {
                switch ($Return) {
                    'objects' { return $Global:IRT_ServicePrincipals }
                    'tablebyappid' { return $Global:IRT_ServicePrincipalsByAppId }
                    'tablebyid' { return $Global:IRT_ServicePrincipalsById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgServicePrincipal $Elapsed"
        $Objects = Get-MgServicePrincipal -All | Select-Object ($GetProperties)

        # extract CreatedDateTime from AdditionalProperties
        foreach ($o in $Objects) {
            if ($o.AdditionalProperties['createdDateTime']) {
                $CreatedDateTime = [datetime]::Parse($o.AdditionalProperties['createdDateTime'])
                $AmParams = @{
                    NotePropertyName  = 'CreatedDateTime'
                    NotePropertyValue = $CreatedDateTime
                    Force             = $true
                }
                $o | Add-Member @AmParams
            }
        }

        # store in global variables
        $Global:IRT_ServicePrincipals = $Objects
        $Global:IRT_ServicePrincipalsByAppId = [hashtable]::Synchronized(@{})
        $Global:IRT_ServicePrincipalsById = [hashtable]::Synchronized(@{})
        foreach ($o in $Objects) {
            if ($o.AppId) { $Global:IRT_ServicePrincipalsByAppId[$o.AppId] = $o }
            if ($o.Id) { $Global:IRT_ServicePrincipalsById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "ServicePrincipals_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 10 -Path $XmlOutputPath
        }

        # return
        switch ($Return) {
            'objects' { return $Global:IRT_ServicePrincipals }
            'tablebyappid' { return $Global:IRT_ServicePrincipalsByAppId }
            'tablebyid' { return $Global:IRT_ServicePrincipalsById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-GraphServicePrincipal.ps1' 116
#Region '.\Private\Graph\Request-GraphUser.ps1' -1

function Request-GraphUser {
    <#
    .SYNOPSIS
    Requests users from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID users from Microsoft Graph and caches the
    result in a session-scoped global variable keyed by object ID. Subsequent callers
    that pass -Cached skip the API call. Used by the playbook and admin role functions
    to resolve user identities without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'DisplayName'
            'AccountEnabled'
            'Id'
            'Mail'
            'OnPremisesLastSyncDateTime'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'ProxyAddresses'
            'UserPrincipalName'
        )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Users' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Users }
                    'tablebyid' { return $Global:IRT_UsersById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        Write-Verbose "${FunctionName}: Get-MgUser $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $Objects = Get-MgUser -All -Property $GetProperties | Select-Object $GetProperties

        # store in global variables
        $Global:IRT_Users = $Objects
        $Global:IRT_UsersById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_UsersById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "Users_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Users }
            'tablebyid' { return $Global:IRT_UsersById }
            'none' { return }
        }
    }
}
#EndRegion '.\Private\Graph\Request-GraphUser.ps1' 90
#Region '.\Private\Graph\Request-IntuneDevice.ps1' -1

function Request-IntuneDevice {
    <#
    .SYNOPSIS
    Requests all managed devices from Intune (Microsoft Graph).
    Returns $null when the tenant has no Intune license or the caller lacks permission.

    .NOTES
    Version: 1.1.0
    #>
    [OutputType([System.Object[]])]
    [CmdletBinding()]
    param ()

    process {

        try {
            return @(Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop)
        }
        catch {
            $Message = $_.Exception.Message
            Write-Verbose "Intune not available or insufficient permissions: $Message"
            return $null
        }
    }
}
#EndRegion '.\Private\Graph\Request-IntuneDevice.ps1' 26
#Region '.\Private\Graph\Resolve-DateRange.ps1' -1

function Resolve-DateRange {
    <#
	.SYNOPSIS
    Validates and resolves date range parameters into a standardized object.

    .DESCRIPTION
    Accepts either a relative range (-Days) or an absolute range (-Start and -End).
    Validates inputs, parses date strings, converts to UTC, and returns a structured
    object with all values needed to build API filter strings and display output.

    Pass -DefaultDays to specify the fallback used when the user provides no date
    arguments. This is handled internally so that the raw -Days value reflects only
    what the user explicitly passed, keeping validation correct.

    .OUTPUTS
    [pscustomobject] with properties:
        RangeType   - 'Relative' or 'Absolute'
        Days        - int: user-specified relative value, or ceiling of absolute span
        StartUtc    - [datetime] UTC start
        EndUtc      - [datetime] UTC end
        StartString - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters
        EndString   - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters

	.NOTES
	Version: 1.1.0
	#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [int]    $Days,
        [string] $Start,
        [string] $End,
        [int]    $DefaultDays
    )

    # validate mutual exclusivity: -Days cannot be combined with -Start or -End
    if ($Days -and ($Start -or $End)) {
        $ErrorParams = @{
            Category    = 'InvalidArgument'
            Message     = 'Choose either relative range with -Days ' +
            'or absolute range with -Start and -End.'
            ErrorAction = 'Stop'
        }
        Write-Error @ErrorParams
    }

    # validate both-or-neither: -Start and -End must be used together
    if (($Start -and -not $End) -or ($End -and -not $Start)) {
        $ErrorParams = @{
            Category    = 'InvalidArgument'
            Message     = "Specify both -Start and -End."
            ErrorAction = 'Stop'
        }
        Write-Error @ErrorParams
    }

    if ($Start -and $End) {

        # absolute range
        $RangeType = 'Absolute'

        # parse start date
        try {
            $StartDate = Get-Date -Date $Start -ErrorAction 'Stop'
            $StartUtc = [DateTime]::SpecifyKind($StartDate, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "-Start invalid. Use format 'MM/dd/yy hh:mm(tt)'"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # parse end date
        try {
            $EndDate = Get-Date -Date $End -ErrorAction 'Stop'
            $EndUtc = [DateTime]::SpecifyKind($EndDate, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "-End invalid. Use format 'MM/dd/yy hh:mm(tt)'"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # ensure start is before end
        if ($StartUtc -gt $EndUtc) {
            $Temp = $StartUtc
            $StartUtc = $EndUtc
            $EndUtc = $Temp
            # also swap local dates so Days calculation is correct
            $Temp = $StartDate
            $StartDate = $EndDate
            $EndDate = $Temp
        }

        # calculate days from absolute range
        $Days = [Int]([Math]::Ceiling(($EndDate - $StartDate).TotalDays))
    }
    else {

        # relative range - apply default if user did not specify -Days
        $RangeType = 'Relative'
        if (-not $Days) {
            $Days = $DefaultDays
        }
        $StartUtc = (Get-Date).AddDays($Days * -1).ToUniversalTime()
        $EndUtc = (Get-Date).ToUniversalTime()
    }

    [pscustomobject]@{
        RangeType   = $RangeType
        Days        = $Days
        StartUtc    = $StartUtc
        EndUtc      = $EndUtc
        StartString = $StartUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        EndString   = $EndUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
#EndRegion '.\Private\Graph\Resolve-DateRange.ps1' 124
#Region '.\Private\Graph\Test-PythonPackage.ps1' -1

function Test-PythonPackage {
    <#
    .SYNOPSIS
    Tests whether a python package is available via python import or uv tool install.

    .PARAMETER Name
    The python module name to import (e.g., 'requests' or 'pandas').

    .PARAMETER MinVersion
    Optional minimum version requirement (nuget-style: 1.2.3).

    .PARAMETER PythonPath
    Optional explicit path to python interpreter. if omitted, tries python, python3, then py -3.

    .OUTPUTS
    [pscustomobject] with Present (bool), Source (string), Version (string),
    Python (string path/command)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [Parameter()]
        [string] $MinVersion,

        [Parameter()]
        [string] $PythonPath
    )

    begin {

        function Find-PythonInterpreter {
            param(
                [string]$ExplicitPath
            )

            # if explicit path provided and exists, use it
            if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
                return @{ Cmd = $ExplicitPath; PrefixArgs = @() }
            }

            # prefer 'python', then 'python3', then 'py -3' on windows
            $Candidates = @(
                @{
                    Cmd = (Get-Command -Name 'python' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @()
                }
                @{
                    Cmd = (Get-Command -Name 'python3' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @()
                }
                @{
                    Cmd = (Get-Command -Name 'py' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @('-3')
                }
            ) | Where-Object { $_.Cmd }

            if (($Candidates | Measure-Object).Count -gt 0) { return $Candidates[0] }

            return $null
        }

        function Find-UvTool {
            param([string]$ToolName)

            $uvCmd = Get-Command -Name 'uv' -ErrorAction SilentlyContinue
            if (-not $uvCmd) { return $null }

            # normalize per PEP 503: lowercase, collapse runs of [-_.] to a single hyphen
            $normalizedName = ($ToolName -replace '[_.\-]+', '-').ToLower()

            try {
                $listOutput = & $uvCmd.Source tool list --no-color 2>$null
                if ($LASTEXITCODE -ne 0) { return $null }

                $version = $null
                $distName = $null
                foreach ($line in $listOutput) {
                    if ($line -match '^(\S+)\s+v(.+)$') {
                        $candidate = ($Matches[1] -replace '[_.\-]+', '-').ToLower()
                        if ($candidate -eq $normalizedName) {
                            $distName = $Matches[1]
                            $version = $Matches[2].Trim()
                            break
                        }
                    }
                }

                if (-not $version) { return $null }

                # locate the venv python inside the tool environment
                $toolDir = (& $uvCmd.Source tool dir 2>$null)
                if ($LASTEXITCODE -ne 0 -or -not $toolDir) {
                    return @{ Version = $version; Python = $null }
                }
                $toolDir = $toolDir.Trim()

                # try likely directory names for the tool's venv
                $dirCandidates = @($distName, $ToolName, $normalizedName) | Select-Object -Unique

                $pythonPath = $null
                foreach ($dir in $dirCandidates) {
                    $JpParams = @{
                        Path      = $toolDir
                        ChildPath = $dir
                    }
                    $testPath = if ($IsWindows -or $env:OS -match 'Windows') {
                        Join-Path @JpParams -AdditionalChildPath 'Scripts', 'python.exe'
                    } else {
                        Join-Path @JpParams -AdditionalChildPath 'bin', 'python'
                    }
                    if (Test-Path -LiteralPath $testPath) {
                        $pythonPath = $testPath
                        break
                    }
                }

                return @{ Version = $version; Python = $pythonPath }
            } catch {
                return $null
            }
        }

        # python snippet: try import, then try to resolve a version
        # - prefers importlib.metadata (py>=3.8) using the package (distribution)
        #   name equal to module name
        # - falls back to module.__version__ if metadata not found
        $PyCode = @"
import sys, importlib
name=sys.argv[1]
try:
    m = importlib.import_module(name)
    ver = ""
    try:
        try:
            from importlib.metadata import version, PackageNotFoundError
        except Exception:
            from importlib_metadata import version, PackageNotFoundError  # backport if installed
        try:
            ver = version(name)
        except PackageNotFoundError:
            ver = getattr(m, "__version__", "") or ""
    except Exception:
        ver = getattr(m, "__Version__", "") or ""
    print(ver)
    sys.exit(0)
except Exception:
    sys.exit(1)
"@.Trim()
    }

    process {

        # === python import check ===
        $Py = Find-PythonInterpreter -ExplicitPath $PythonPath
        $PyPresent = $false
        $PyVersion = $null
        $PyCmd = $null

        if ($Py) {
            $Arguments = @()
            if ($Py.PrefixArgs) { $Arguments += $Py.PrefixArgs }
            $Arguments += @('-c', $PyCode, $Name)

            $Output = & $Py.Cmd @Arguments 2>$null
            $Exit = $LASTEXITCODE

            $PyPresent = ($Exit -eq 0)
            if ($PyPresent) {
                $PyVersion = ($Output | Select-Object -First 1).ToString().Trim()
            } else {
                $PyVersion = $null
            }
            $PrefixStr = if ($Py.PrefixArgs.Count) { ' ' + ($Py.PrefixArgs -join ' ') } else { '' }
            $PyCmd = $Py.Cmd + $PrefixStr
        }

        # === uv tool check ===
        $UvTool = Find-UvTool -ToolName $Name
        $UvPresent = $null -ne $UvTool
        $UvVersion = if ($UvPresent) { $UvTool.Version } else { $null }
        $UvPython = if ($UvPresent) { $UvTool.Python } else { $null }

        # overall result
        $Present = $PyPresent -or $UvPresent

        $Source = if ($PyPresent -and $UvPresent) { 'both' }
        elseif ($PyPresent) { 'python' }
        elseif ($UvPresent) { 'uv-tool' }
        else { $null }

        # effective version (prefer python import, fall back to uv tool)
        $Version = if ($PyVersion) { $PyVersion } elseif ($UvVersion) { $UvVersion } else { $null }

        # effective python interpreter
        # if found via import, use that interpreter; if only via uv tool, use the venv python
        $Python = if ($PyPresent) { $PyCmd }
        elseif ($UvPython) { $UvPython }
        elseif ($PyCmd) { $PyCmd }
        else { $null }

        # optional min version check
        $MeetsMin = $true
        if ($Present -and $MinVersion -and $Version) {
            try {
                # attempt semantic comparison; if parse fails, treat as not comparable
                $vA = [Version]($Version -replace '[^0-9\.].*$', '')
                $vB = [Version]($MinVersion -replace '[^0-9\.].*$', '')
                $MeetsMin = ($vA -ge $vB)
            } catch {
                $MeetsMin = $false
            }
        }

        Write-Output ([pscustomobject]@{
                Present         = $Present
                Source          = $Source
                Version         = $Version
                MeetsMinVersion = if ($MinVersion) { $MeetsMin } else { $null }
                Name            = $Name
                Python          = $Python
            })
    }
}
#EndRegion '.\Private\Graph\Test-PythonPackage.ps1' 226
#Region '.\Private\Lib\Build-Menu.ps1' -1

function Build-Menu {
    <#
    .SYNOPSIS
    Takes a collection, presents a numbered menu, reads user input, returns user's selection.

    .DESCRIPTION
    For a simple menu, provide a list or array. Numbers will automatically be assigned.
    For a customized menu, provide a hashtable in the format below.

    .PARAMETER Options
    Provide collection of menu options. Accepts array of strings, Generic.List[string] or hashtable.

    .PARAMETER List
    Use -List for this menu format:
    [1] Do this
    [2] Do that

    .PARAMETER Table
    Use -Table for this format:
    [1] Do this  [2] Do that

    .EXAMPLE
    Input:
    $Option = [ordered]@{
        '1' = @{
            String = 'Do this'
            Color = 'Red'
        }
        '2' = @{
            String = 'Do that'
            Color = 'Green'
        }
    }
    $MenuParams = @{
        Title = "Choose action:"
        Options = $Option
        List = $true
    }
    $UserChoice = Build-Menu @MenuParams

    Output:
    Choose action:

    [1] Do this     # Foregroundcolor Red
    [2] Do that     # Foregroundcolor Green

    Enter choice:


    .NOTES
    Version: 1.1.2
    1.1.2 - Fixed bugs where script doesn't accept user input.
    1.1.0 - Added validation that hashtable keys are integers, not strings.
    1.01 - Changed hashtable format to allow colors.
    0.02 - Convert to allow building menu based on hashtable.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param(
        [parameter( Mandatory )]
        [Alias('Options')]
        [object] $Option,

        [string] $Title,

        [Parameter(ParameterSetName = 'List')]
        [switch] $List,

        [Parameter(ParameterSetName = 'Table')]
        [switch] $Table,

        [switch] $NoNewLine,

        [string] $TestAnswer
    )

    # determine input type
    if ( (
            $Option -is [array] -and
            ( $Option | ForEach-Object { $_ -is [string] } )
        ) -or
        $Option -is [System.Collections.Generic.List[string]]
    ) {
        $ArrayOrList = $true
    }
    elseif ( $Option -is [System.Collections.Specialized.OrderedDictionary] ) {
        # every key must be a string
        if ( ($Option.Keys | Where-Object { $_ -isnot [string] }).Count ) {
            throw 'Build-Menu: Hashtable keys must be strings.'
        }
        # every value must itself be a hashtable with at least a string key
        foreach ($Value in $Option.Values) {
            if ($Value -isnot [hashtable] -or -not $Value.ContainsKey('String')) {
                throw 'Build-Menu: Each option must be a hashtable that contains a ''String'' key.'
            }
        }
    }
    else {
        throw "Build-Menu: Unsupported input type."
    }

    # display title
    if ( $Title ) {
        Write-Host ''
        Write-Host $Title
    }

    if ( -not $NoNewLine ) {
        Write-Host ''
    }

    if ( $ArrayOrList ) {

        # build menu with numbers counting from one
        for ( $i = 0; $i -lt @($Option).Count; $i++ ) {

            # add one so first index isn't 0
            $Index = $i + 1

            # variables
            $String = $Option[$i]

            # output
            Write-Host -NoNewLine "[${Index}] ${String}  "

            # for list format, add a newline every loop. for table format, only at end
            if ( $List -or
                ( $Table -and
                $Index -eq @($Option).Count - 1 )
            ) {
                Write-Host ''
            }
        }

    }
    else { # if hashtable

        # build menu with numbers from hashtable
        $Keys = $Option.Keys
        $LastKey = $Keys[-1]

        foreach ( $Key in $Keys ) {

            # variables
            $OptionItem = $Option[$Key]
            $String = $OptionItem.String

            # build params for output
            $Params = @{
                NoNewLine = $true
            }

            # if color was specified, add to params
            if ( $OptionItem.ContainsKey('Color') -and $OptionItem['Color']) {
                $Params['ForegroundColor'] = $OptionItem.Color
            }

            Write-Host "[${Key}] ${String}  " @Params

            # for list format, add a newline every loop. for table format, only at end
            if ( $List -or
                ( $Table -and
                $Key -eq $LastKey
            ) ) {
                Write-Host ''
            }
        }
    }

    if ( -not $NoNewLine ) {
        Write-Host ''
    }

    # get input from user
    if ( $TestAnswer ) {
        $UserChoice = $TestAnswer
    }
    else {
        $UserChoice = Read-Host 'Enter choice'
    }

    # validate answer and return string
    if ( $ArrayOrList ) {

        while ( -not ( $UserChoice -ge 1 -and $UserChoice -le @($Option).Count ) ) {
            Write-Host -NoNewLine @Red "Choice must be a number, 1 to $( @($Option).Count )."
            Write-Host -NoNewLine @Red " Enter Choice"
            $UserChoice = Read-Host
        }

        # convert choice number to index number
        $i = $UserChoice - 1

        # use index number to get string
        $Return = $Option[$i]

    }
    else { # if hashtable
        while ( $UserChoice -notin $Option.Keys ) {
            $OptionsString = @( $Option.Keys | Sort-Object ) -join ','
            Write-IRT "Choice must be in ${OptionsString}. Enter Choice" -Level Error
            $UserChoice = Read-Host
        }

        $Return = $Option[$UserChoice].String
    }

    return $Return
}
#EndRegion '.\Private\Lib\Build-Menu.ps1' 209
#Region '.\Private\Lib\Format-Powershell.ps1' -1

function Format-Powershell {
    <#
    .SYNOPSIS
    This function will remove all comments, empty lines, and leading whitespace from Powershell
    content in the clipboard or passed with -Content.

    .EXAMPLE
    Format-Powershell -Comments -KeepVersion -EmptyLines

    In scripts:
    Format-Powershell -Comments -EmptyLines -Whitespace -Script -Content $Content

    .NOTES
    Version: 1.0.3
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, ValueFromPipeline = $true )]
        [string] $Content,
        [switch] $Script,
        [switch] $Comments,
        [switch] $KeepVersion,
        [switch] $EmptyLines,
        [switch] $Whitespace,
        [switch] $OneLine
    )

    begin {

        #region helpers

        function Remove-Comment {
            <#
            .SYNOPSIS
            Remove comments from PowerShell file

            .DESCRIPTION
            Remove comments from PowerShell file and optionally remove empty lines
            By default comments in param block are not removed
            By default comments before param block are not removed

            .PARAMETER SourceFilePath
            File path to the source file

            .PARAMETER Content
            Content of the file

            .PARAMETER DestinationFilePath
            File path to the destination file. If not provided, the content will be returned

            .PARAMETER RemoveEmptyLines
            Remove empty lines if more than one empty line is found

            .PARAMETER RemoveAllEmptyLines
            Remove all empty lines from the content

            .PARAMETER RemoveCommentsInParamBlock
            Remove comments in param block. By default comments in param block are not removed

            .PARAMETER RemoveCommentsBeforeParamBlock
            Remove comments before param block. By default comments before param
            block are not removed.

            .EXAMPLE
            Remove-Comments
                -SourceFilePath 'C:\Support\GitHub\PSPublishModule\Examples\TestScript.ps1'
                -DestinationFilePath 'C:\Support\GitHub\PSPublishModule\Examples\TestScript1.ps1'
                -RemoveAllEmptyLines -RemoveCommentsInParamBlock -RemoveCommentsBeforeParamBlock

            .NOTES
            Most of the work done by Chris Dent, with improvements by Przemyslaw Klys
            https://evotec.xyz/how-to-efficiently-remove-comments-from-your-powershell-script/
            #>
            [CmdletBinding(DefaultParameterSetName = 'FilePath', SupportsShouldProcess = $true)]
            param(
                [Parameter(Mandatory, ParameterSetName = 'FilePath')]
                [alias('FilePath', 'Path', 'LiteralPath')]
                [string] $SourceFilePath,

                [Parameter(Mandatory, ParameterSetName = 'Content')]
                [string] $Content,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [alias('Destination')]
                [string] $DestinationFilePath,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [switch] $RemoveAllEmptyLines,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [switch] $RemoveEmptyLines,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [switch] $RemoveCommentsInParamBlock,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [switch] $RemoveCommentsBeforeParamBlock,

                [Parameter(ParameterSetName = 'Content')]
                [Parameter(ParameterSetName = 'FilePath')]
                [switch] $DoNotRemoveSignatureBlock
            )
            if ($SourceFilePath) {
                $Fullpath = Resolve-Path -LiteralPath $SourceFilePath
                $Content = [IO.File]::ReadAllText($FullPath, [System.Text.Encoding]::UTF8)
            }

            $Tokens = $Errors = @()
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $Content, [ref]$Tokens, [ref]$Errors
            )
            #$functionDefinition = $ast.Find({ $args[0] -is [FunctionDefinitionAst] }, $false)
            $GroupedTokens = $Tokens | Group-Object { $_.Extent.StartLineNumber }
            $DoNotRemove = $false
            $DoNotRemoveCommentParam = $false
            $CountParams = 0
            $ParamFound = $false
            $SignatureBlock = $false
            $ToRemove = foreach ($Line in $GroupedTokens) {
                if ($Ast.Body.ParamBlock.Extent.StartLineNumber -gt $Line.Name) {
                    continue
                }
                $Tokens = $Line.Group
                for ($i = 0; $i -lt $Line.Count; $i++) {
                    $Token = $Tokens[$i]
                    if ($Token.Extent.StartOffset -lt $Ast.Body.ParamBlock.Extent.StartOffset) {
                        continue
                    }

                    # Lets find comments between function and param block and not remove them
                    if ($Token.Extent.Text -eq 'function') {
                        if (-not $RemoveCommentsBeforeParamBlock) {
                            $DoNotRemove = $true
                        }
                        continue
                    }
                    if ($Token.Extent.Text -eq 'param') {
                        $ParamFound = $true
                        $DoNotRemove = $false
                    }
                    if ($DoNotRemove) {
                        continue
                    }
                    # lets find comments between param block and end of param block
                    if ($Token.Extent.Text -eq 'param') {
                        if (-not $RemoveCommentsInParamBlock) {
                            $DoNotRemoveCommentParam = $true
                        }
                        continue
                    }
                    $isOpenParen = $Token.Extent.Text -eq '(' -or $Token.Extent.Text -eq '@('
                    if ($ParamFound -and $isOpenParen) {
                        $CountParams += 1
                    } elseif ($ParamFound -and $Token.Extent.Text -eq ')') {
                        $CountParams -= 1
                    }
                    if ($ParamFound -and $Token.Extent.Text -eq ')') {
                        if ($CountParams -eq 0) {
                            $DoNotRemoveCommentParam = $false
                            $ParamFound = $false
                        }
                    }
                    if ($DoNotRemoveCommentParam) {
                        continue
                    }
                    # if token not comment we leave it as is
                    if ($Token.Kind -ne 'Comment') {
                        continue
                    }

                    # kind of useless to not remove signature block if we're not removing comments
                    # this changes the structure of a file and signature will be invalid
                    if ($DoNotRemoveSignatureBlock) {
                        if ($Token.Kind -eq 'Comment' -and
                            $Token.Text -eq '# SIG # Begin signature block'
                        ) {
                            $SignatureBlock = $true
                            continue
                        }
                        if ($SignatureBlock) {
                            if ($Token.Kind -eq 'Comment' -and
                                $Token.Text -eq '# SIG # End signature block'
                            ) {
                                $SignatureBlock = $false
                            }
                            continue
                        }
                    }
                    $Token
                }
            }
            $ToRemove = $ToRemove | Sort-Object { $_.Extent.StartOffset } -Descending
            foreach ($Token in $ToRemove) {
                $StartIndex = $Token.Extent.StartOffset
                $HowManyChars = $Token.Extent.EndOffset - $Token.Extent.StartOffset
                $Content = $Content.Remove($StartIndex, $HowManyChars)
            }
            if ($RemoveEmptyLines) {
                # Remove empty lines if more than one empty line is found.
                # If it's just one line, leave it as is.
                #$Content = $Content -replace '(?m)^\s*$', ''
                #$Content = $Content -replace "(`r?`n){2,}", "`r`n"
                # $Content = $Content -replace "(`r?`n){2,}", "`r`n`r`n"
                $Content = $Content -replace '(?m)^\s*$', ''
                $Content = $Content -replace "(?:`r?`n|\n|\r)", "`r`n"
            }
            if ($RemoveAllEmptyLines) {
                # Remove all empty lines from the content
                $Content = $Content -replace '(?m)^\s*$(\r?\n)?', ''
            }
            if ($Content) {
                $Content = $Content.Trim()
            }
            if ($DestinationFilePath) {
                $Content | Set-Content -Path $DestinationFilePath -Encoding utf8
            } else {
                $Content
            }
        }

        function Remove-Newline {
            <#
            .SYNOPSIS
            Remove unnecessary newlines from Powershell code.

            This is beta stage. Use at your own risk!
            #>
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '')]
            [CmdletBinding()]
            param (
                [string] $Content
            )

            process {

                # remove newlines before else, elseif, catch, finally
                $ElsePattern = "\}\s*(?:\r?\n\s*#.*\r?\n)?\s*(else|elseif|catch|finally)\s*([\{\(])"
                $ElseReplace = '} $1 $2'
                $Content = $Content -replace $ElsePattern, $ElseReplace

                # remove newlines after logical operators
                $LogicalPattern = "-(and|or|xor|not)\s*\n\s*"
                $LogicalReplace = '-$1 '
                $Content = $Content -replace $LogicalPattern, $LogicalReplace

                # remove newlines before/after pipes
                $PipePattern = "\s*\|\s*"
                $PipeReplace = "|"
                $Content = $Content -replace $PipePattern, $PipeReplace

                # remove newline from parameters
                $ParamNames = 'Alias|CmdletBinding|Parameter|ValidateScript' +
                '|ValidateSet|ValidateRange'
                $CmdletBindingPattern = "(\[(${ParamNames})\((.*?)\)])\s*\n\s*"
                $CmdletBindingReplace = '$1 '
                $Content = $Content -replace $CmdletBindingPattern, $CmdletBindingReplace

                # remove newlines after commas
                $CommaPattern = ",\s*\n\s*"
                $CommaReplace = ', '
                $Content = $Content -replace $CommaPattern, $CommaReplace

                # remove newlines after opening parenthesis/brackets
                $OpenPattern = "([\(\{])\s*"
                $OpenReplace = '$1'
                $Content = $Content -replace $OpenPattern, $OpenReplace

                # remove newlines before closing parenthesis/brackets
                $ClosePattern = "\s*([\)\}])"
                $CloseReplace = '$1'
                $Content = $Content -replace $ClosePattern, $CloseReplace

                # remove newlines, replace with semicolons. must be last
                $Content = $Content -replace '\n', ';'

                return $Content
            }
        }

        function Remove-WhitespaceFromLine {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param (
                [Parameter(
                    Position = 0,
                    ValueFromPipeline = $true
                )]
                [string]$Content
            )

            process {

                # split the content into individual lines
                $Lines = $Content -split "`n"

                # trim each line
                $Lines = $Lines | ForEach-Object { $_.Trim() }

                # change tabs to spaces
                $Lines = $Lines -replace "\t", ' '

                # remove instances of multiple spaces
                $Lines = $Lines -replace " +", ' '

                # join lines back together
                $Output = $Lines -join "`n"

                Write-Output $Output

            } # end process
        }

        #endregion helpers

    } # end begin

    process {

        if ( -not $Script ) {
            $IsClipboardContent = $false
            if ( [string]::IsNullOrWhiteSpace( $Content ) ) {
                # if no content is provided, get text from the clipboard
                Write-Host -ForegroundColor Green "`nProcessing text from clipboard."
                $Content = Get-Clipboard -Raw
                $IsClipboardContent = $true
            }
        }

        # convert to standardized line ending
        $Content = $Content -replace "\r\n", "`n"

        # capture version number
        if ( $KeepVersion ) {
            $VersionPattern = "Version:\s?.*"
            $VersionString = $Content |
                Select-String -Pattern $VersionPattern -AllMatches |
                ForEach-Object { $_.Matches.Value }
        }

        # remove comments
        if ($Comments) {
            $Params = @{
                Content                        = $Content
                RemoveCommentsInParamBlock     = $true
                RemoveCommentsBeforeParamBlock = $true
            }
            if ($EmptyLines) {
                $Params["RemoveAllEmptyLines"] = $true
            }
            $Content = Remove-Comment @Params
        }

        # insert version number
        if ( $KeepVersion ) {
            # separate into lines
            $SplitContent = $Content -Split "\r?\n"

            # insert version into the second line
            $ContentWithVersion = $SplitContent[0..0] +
            "    # ${VersionString}" +
            $SplitContent[1..$SplitContent.Length]

            # rejoin into one string
            $Content = $ContentWithVersion -Join "`n"
        }

        # remove whitespace from each line
        if ($Whitespace) {
            $Content = Remove-WhitespaceFromLine -Content $Content
        }

        if ( $OneLine ) {
            $Content = Remove-Newline -Content $Content
        }

        if ( $IsClipboardContent ) {
            # display output in console
            Write-Host -ForegroundColor Green "`nOutput:"
            Write-Host $Content
            # only copy to clipboard if the content was originally from the clipboard
            $Content | Set-Clipboard
        }
        else {
            # output content if it was provided directly
            Write-Output $Content
        }

    } # end process

    end {
    } # end end

}
#EndRegion '.\Private\Lib\Format-Powershell.ps1' 400
#Region '.\Private\Lib\Format-Tree.ps1' -1

function Format-Tree {
    <#
displays a simple tree view of any object (ps 5.1+)
- property names are light green on ps 7+; values default color
- pass -OmitNullOrEmpty to hide nulls, empty strings, empty containers, and empty objects
- pass -ExcludeProperty to omit properties by name anywhere in the tree (case-insensitive)
- multiline values align continuation lines under the value column
- no artificial root line; first properties start at zero indentation
#>
    [Alias('FTree', 'FTr')]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Depth',
        Justification = 'Used by Out-Print helper via PowerShell dynamic scoping.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console output for terminal display function.')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Position = 0, Mandatory)]
        [int] $Depth,
        [int] $IndentSize = 4,
        [Alias('NewLines')] [bool] $NewLine = $true,

        # hide nulls, empty strings, empty arrays/maps, and objects with no visible children
        [switch] $OmitNullOrEmpty,

        # property names to exclude anywhere (case-insensitive)
        [string[]] $ExcludeProperty
    )

    begin {

        #region helpers

        function Get-Indent([int]$CurrentDepth, [int]$Size) {
            ' ' * ($CurrentDepth * $Size)
        }

        function Get-PropertyName($Obj) {
            $Obj.PSObject.Properties |
                Where-Object {
                    $_.IsGettable -and
                    $_.MemberType -in 'NoteProperty', 'Property', 'AliasProperty'
                } |
                Select-Object -ExpandProperty Name -Unique |
                Sort-Object
        }

        function Resolve-Json($Value) {
            ### if it's a string that looks like json, try to parse it
            ### (handles one level of json-in-a-string)
            # if the value is anything other than string, return it
            if ($Value -isnot [string]) { return $Value }
            $String = $Value.Trim()
            if (-not (
                    ($String.StartsWith('{') -and $String.EndsWith('}')) -or
                    ($String.StartsWith('[') -and $String.EndsWith(']'))
                )
            ) {
                return $Value
            }

            try {
                # convert from json
                $Parsed = $String | ConvertFrom-Json -ErrorAction Stop
                # if the parsed result is itself a json-looking string, try one more pass
                if ($Parsed -is [string]) {
                    $Inner = $Parsed.Trim()
                    if (
                        ($Inner.StartsWith('{') -and $Inner.EndsWith('}')) -or
                        ($Inner.StartsWith('[') -and $Inner.EndsWith(']'))
                    ) {
                        try { return ($Inner | ConvertFrom-Json -ErrorAction Stop) }
                        catch { return $Parsed }
                    }
                }
                return $Parsed
            } catch { return $Value }
        }

        function Test-IsScalar($Value) {
            # treat common primitives as scalars (and helpful extras)
            $Value -is [string] -or $Value -is [bool] -or
            $Value -is [int] -or $Value -is [long] -or
            $Value -is [double] -or $Value -is [decimal] -or
            $Value -is [datetime] -or $Value -is [guid] -or
            $Value -is [timespan] -or $Value -is [uri] -or
            $Value -is [version] -or $Value -is [enum]
        }

        function Test-IsEmptyScalar($Value) {
            ($Value -is [string]) -and [string]::IsNullOrWhiteSpace($Value)
        }

        function Test-HasVisible($Value, [int]$CurrentDepth) {
            # returns $true if value would produce visible output at this depth

            if ($CurrentDepth -gt $Depth) { return $false }

            # if value looks like json
            $Value = Resolve-Json $Value

            if ($CurrentDepth -eq $Depth) {
                if ($null -eq $Value) { return (-not $OmitNullOrEmpty) }
                if (Test-IsScalar $Value) {
                    if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
                    return $true
                }
                return $true
            }

            if ($null -eq $Value) { return (-not $OmitNullOrEmpty) }

            if (Test-IsScalar $Value) {
                if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
                return $true
            }

            if ($Value -is [System.Collections.IDictionary]) {
                foreach ($Key in $Value.Keys) {
                    if (Test-HasVisible $Value[$Key] ($CurrentDepth + 1)) { return $true }
                }
                return $false
            }

            if ($Value -is [System.Collections.IEnumerable]) {
                foreach ($E in $Value) {
                    if (Test-HasVisible $E ($CurrentDepth + 1)) { return $true }
                }
                return $false
            }

            $Names = Get-PropertyName $Value
            if ($ExcludeSet) { $Names = $Names | Where-Object { -not $ExcludeSet.Contains($_) } }
            foreach ($N in $Names) {
                try { $V = $Value.PSObject.Properties[$N].Value } catch { $V = $null }
                if (Test-HasVisible $V ($CurrentDepth + 1)) { return $true }
            }
            return $false
        }

        function Write-NameEllipsis([string]$Name, [int]$CurrentDepth, [int]$Size) {
            $indent = Get-Indent $CurrentDepth $Size
            Write-Host -NoNewline $indent
            Write-Host -NoNewline @Script:Green ($Name + ': ')
            Write-Host @Script:Red '...'
        }

        function Write-NameValue {
            param([string]$Name, [string]$ValueText, [int]$CurrentDepth, [int]$Size)
            $Indent = Get-Indent $CurrentDepth $Size
            $PlainPrefix = $Indent + $Name + ': '
            $ContIndent = ' ' * ($PlainPrefix.Length)
            $Lines = [regex]::Split($ValueText, '(?:\r\n|\n|\r)')
            if ($Lines.Count -eq 0) { $Lines = @('') }

            if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSStyle) {
                $First = $Indent + $PSStyle.Foreground.BrightGreen + $Name +
                $PSStyle.Reset + ': ' + $Lines[0]
                Write-Host $First
                for ($i = 1; $i -lt $Lines.Count; $i++) {
                    Write-Host ($ContIndent + $Lines[$i])
                }
            } else {
                Write-Host @Script:Green ($PlainPrefix + $Lines[0])
                for ($i = 1; $i -lt $Lines.Count; $i++) {
                    Write-Host ($ContIndent + $Lines[$i])
                }
            }
        }

        function Out-Print {
            param(
                [Parameter(Position = 0)]
                [string] $Name,
                [Parameter(Position = 1)]
                $Value,
                [Parameter(Position = 2)]
                [int] $CurrentDepth
            )

            # print node (returns $true if anything was printed)
            if ($CurrentDepth -gt $Depth) { return $false }

            $Value = Resolve-Json $Value

            if ($null -eq $Value) {
                if (-not $OmitNullOrEmpty) {
                    $WnvParams = @{
                        Name         = $Name
                        ValueText    = '<null>'
                        CurrentDepth = $CurrentDepth
                        Size         = $IndentSize
                    }
                    Write-NameValue @WnvParams
                    return $true
                }
                return $false
            }

            if (Test-IsScalar $Value) {
                if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
                $WnvParams = @{
                    Name         = $Name
                    ValueText    = ([string]$Value)
                    CurrentDepth = $CurrentDepth
                    Size         = $IndentSize
                }
                Write-NameValue @WnvParams
                return $true
            }

            # non-scalar at/over the depth limit -> print "NAME: ..."
            if ($CurrentDepth -ge $Depth) {
                Write-NameEllipsis -Name $Name -CurrentDepth $CurrentDepth -Size $IndentSize
                return $true
            }

            if ($Value -is [System.Collections.IDictionary]) {
                # one more level would exceed limit -> collapse whole map to ellipsis
                if (($CurrentDepth + 1) -ge $Depth) {
                    Write-NameEllipsis -Name $Name -CurrentDepth $CurrentDepth -Size $IndentSize
                    return $true
                }

                $Printed = $false

                if (($CurrentDepth + 1) -ge $Depth) {
                    $indent = Get-Indent $CurrentDepth $IndentSize
                    Write-Host -NoNewline $indent
                    Write-Host -NoNewline @Script:Green ($Name + ': ')
                    Write-Host @Script:Red '...'
                    return $true
                }
                foreach ($Key in ($Value.Keys | Sort-Object)) {
                    if (Test-HasVisible $Value[$Key] $ChildDepth) {
                        if (-not $Printed) {
                            $WnvParams = @{
                                Name         = $Name
                                ValueText    = ''
                                CurrentDepth = $CurrentDepth
                                Size         = $IndentSize
                            }
                            Write-NameValue @WnvParams
                            $Printed = $true
                        }
                        $PrintParams = @{
                            Name         = "[$Key]"
                            Value        = $Value[$Key]
                            CurrentDepth = $ChildDepth
                        }
                        $null = Out-Print @PrintParams
                    }
                }
                return $Printed
            }

            if ($Value -is [System.Collections.IEnumerable]) {
                # one more level would exceed limit -> collapse whole map to ellipsis
                if (($CurrentDepth + 1) -ge $Depth) {
                    Write-NameEllipsis -Name $Name -CurrentDepth $CurrentDepth -Size $IndentSize
                    return $true
                }

                $Visible = @()
                foreach ($E in $Value) {
                    if (Test-HasVisible $E ($CurrentDepth + 1)) {
                        $Visible += , $E
                    }
                }
                if ($Visible.Count -eq 0) {
                    return $false
                }
                $WnvParams = @{
                    Name         = $Name
                    ValueText    = "[$($Visible.Count)]"
                    CurrentDepth = $CurrentDepth
                    Size         = $IndentSize
                }
                Write-NameValue @WnvParams
                for ($i = 0; $i -lt $Visible.Count; $i++) {
                    $PrintParams = @{
                        Name         = "[$i]"
                        Value        = $Visible[$i]
                        CurrentDepth = $CurrentDepth + 1
                    }
                    $null = Out-Print @PrintParams
                }
                return $true
            }

            $Names = Get-PropertyName $Value
            if ($ExcludeSet) { $Names = $Names | Where-Object { -not $ExcludeSet.Contains($_) } }

            $Pairs = @()
            foreach ($N in $Names) {
                try { $V = $Value.PSObject.Properties[$N].Value } catch { $V = $null }
                if (Test-HasVisible $V ($CurrentDepth + 1)) { $Pairs += , @($N, $V) }
            }
            if ($Pairs.Count -eq 0) { return $false }

            Write-NameValue -Name $Name -ValueText '' -CurrentDepth $CurrentDepth -Size $IndentSize
            foreach ($P in $Pairs) {
                $null = Out-Print -Name $P[0] -Value $P[1] -CurrentDepth ($CurrentDepth + 1)
            }
            return $true
        }

        #endregion helpers

        $Script:Green = @{ForegroundColor = 'Green' }
        $Script:Red = @{ForegroundColor = 'Red' }

        # case-insensitive exclude set
        $ExcludeSet = $null
        if ($ExcludeProperty) {
            $ExcludeSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($n in $ExcludeProperty) {
                [void]$ExcludeSet.Add($n)
            }
        }

        # empty line before and after, similar to Format-Table, Format-List
        if ($NewLine) {
            Write-Host ''
        }
    }

    process {

        # root handling
        if (Test-IsScalar $InputObject) {
            if (-not ($OmitNullOrEmpty -and (Test-IsEmptyScalar $InputObject))) {
                Write-Host ([string]$InputObject)
            }
            return
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            foreach ($Key in ($InputObject.Keys | Sort-Object)) {
                $null = Out-Print -Name "[$Key]" -Value $InputObject[$Key] -CurrentDepth 0
            }
            return
        }

        $RootNames = Get-PropertyName $InputObject
        if (($RootNames | Measure-Object).Count -gt 0) {
            if ($ExcludeSet) {
                $RootNames = $RootNames | Where-Object { -not $ExcludeSet.Contains($_) }
            }
            foreach ($Name in $RootNames) {
                try {
                    $Value = $InputObject.PSObject.Properties[$Name].Value
                }
                catch {
                    $Value = $null
                }
                $null = Out-Print -Name $Name -Value $Value -CurrentDepth 0
            }
            return
        }

        if ($InputObject -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($E in $InputObject) {
                $null = Out-Print -Name "[$i]" -Value $E -CurrentDepth 0
                $i++
            }
            return
        }

        $WnvParams = @{
            Name         = '<root>'
            ValueText    = "<$($InputObject.GetType().FullName)>"
            CurrentDepth = 0
            Size         = $IndentSize
        }
        Write-NameValue @WnvParams
    }

    end {
        # empty line before and after, similar to Format-Table, Format-List
        if ($NewLine) {
            Write-Host ''
        }
    }
}
#EndRegion '.\Private\Lib\Format-Tree.ps1' 391
#Region '.\Private\Lib\Get-LicenseFullName.ps1' -1

function Get-LicenseFullName {
    <#
    .SYNOPSIS
    Pipeline function that adds a LicenseFullName property to Graph license objects.

    .DESCRIPTION
    Accepts Microsoft Graph subscribed SKU objects from the pipeline and enriches each
    with a LicenseFullName property resolved from Microsoft's published product name CSV.
    The CSV is downloaded automatically to $env:AppData on first use (or when stale).

    When called with a bare -SkuId GUID instead of pipeline input, returns the friendly
    name as a string directly.

    .PARAMETER SkuId
    The SKU GUID of the license to look up. Accepts pipeline input and
    ValueFromPipelineByPropertyName.

    .PARAMETER LicenseFullName
    Reserved for internal pipeline passthrough; not intended for direct use.

    .EXAMPLE
    Get-MgSubscribedSku | Get-LicenseFullName
    Returns enriched license objects with a LicenseFullName property added.

    .EXAMPLE
    Get-LicenseFullName -SkuId '05e9a617-0261-4cee-bb44-138d3ef5d965'
    Returns the friendly product name for the given SKU GUID.

    .OUTPUTS
    PSObject (enriched input object) when used in the pipeline.
    System.String when called with a bare -SkuId.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$SkuId,
        [string]$LicenseFullName
    )

    begin {

        #region helpers

        function Get-LicenseCSVFile {
            <#
            .SYNOPSIS
            Downloads the Microsoft license name CSV to $env:AppData if missing or
            older than 6 days.

            .DESCRIPTION
            Internal helper used by Get-LicenseFullNames. Downloads the Microsoft product names and
            service plan identifiers CSV from the Microsoft Download Center. Skips the download if
            the file already exists in $env:AppData and was last modified less than 6 days ago.
            #>
            param (
                [string]$Url,
                [string]$CsvPath
            )

            # Check if the file exists and if the last modified date is more than a week ago
            if (
                -not ( Test-Path $CsvPath ) -or
                ((Get-Date) - (Get-Item $CsvPath).LastWriteTime) -gt (New-TimeSpan -Days 6)
            ) {
                # Download the file
                Invoke-WebRequest -Uri $Url -OutFile $CsvPath
            }
        }

        function Get-LicenseNameFromCSV {
            <#
            .SYNOPSIS
            Looks up a license SKU GUID in the Microsoft CSV file and returns
            the friendly product name.

            .DESCRIPTION
            Internal helper used by Get-LicenseFullNames. Imports the CSV from the specified path
            and returns the Product_Display_Name for the matching SKU GUID.
            #>
            param (
                [string]$SkuId,
                [string]$CsvPath
            )

            # import csv file
            $CsvData = Import-Csv -Path $CsvPath

            # finds the row that matches the skuid
            $MatchingRow = $CsvData | Where-Object { $_.guid -eq $SkuId }

            # pulls the full name from the matching row
            $LicenseFullName = $Matchingrow.Product_Display_Name

            return $LicenseFullName
        }

        #endregion helpers

    }

    process {
        $ModuleName = $MyInvocation.MyCommand.ModuleName

        # URL to download csv from
        $Url = 'https://download.microsoft.com/download/e/3/e/' +
        'e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/' +
        'Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'

        # Set the destination path
        $CsvPath = "${env:AppData}\${ModuleName}\ProductNamesAndServicePlanIdentifiers.csv"

        # download updated list of license names, if needed
        Get-LicenseCSVFile -url $Url -csvpath $CsvPath

        # two if statements take different action depending on whether being
        # used in pipeline or manually
        if ($SkuId -and $_) {
            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath |
                Sort-Object -Unique

            # adds attributes
            $AmParams = @{
                MemberType = 'NoteProperty'
                Name       = 'LicenseFullName'
                Value      = $LicenseFullName
                PassThru   = $true
            }
            $OutputObject = $_ | Add-Member @AmParams

            Write-Output $OutputObject
        }

        if ($SkuId -and $null -eq $_) {
            # if manually enters, validates good guid
            if ($SkuId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                Write-IRT "Invalid GUID provided. Please provide a valid GUID." -Level Error
                return
            }

            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath |
                Sort-Object -Unique

            Write-IRT "License full name is:"
            Write-IRT $LicenseFullName -NoColor
        }
    }
}
#EndRegion '.\Private\Lib\Get-LicenseFullName.ps1' 150
#Region '.\Private\Lib\Open-Browser.ps1' -1

function Open-Browser {
    <#
    .SYNOPSIS
    Simplifies opening browser windows

    .NOTES
    Version 1.03
    #>

    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string]$Browser,
        [string]$Url,
        [switch]$Private
    )

    if ($Browser -eq 'default') {

        # pull default browser from registry
        $RegPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\' +
        'Associations\UrlAssociations\https\UserChoice'
        $ProgId = Get-ItemProperty -Path $RegPath | Select-Object -ExpandProperty ProgId

        switch -Regex ($ProgId) {
            '^Firefox' {
                $Browser = 'firefox'
            }
            '^MSEdge' {
                $Browser = 'msedge'
            }
            '^Chrome' {
                $Browser = 'chrome'
            }
            '^Brave' {
                $Browser = 'brave'
            }
        }
    }

    switch ( $Browser ) {
        'msedge' {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('--inprivate', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
        'firefox' {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('-private-window', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
        { $_ -in 'chrome', 'brave' } {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('--incognito', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
    }
}
#EndRegion '.\Private\Lib\Open-Browser.ps1' 66
#Region '.\Private\Lib\Set-TerminalTitle.ps1' -1

function Set-TerminalTitle {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console status message for interactive use.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Terminal title change; no ShouldProcess needed.')]
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [string] $Title,
        [switch] $Original,
        [switch] $Quiet
    )

    function Save-TerminalTitle {
        [CmdletBinding()]
        Param(
            [switch] $Quiet
        )

        $Global:OriginalTerminalTitle = $Host.UI.RawUI.WindowTitle

        if (-not $Quiet) {
            Write-Host 'Original terminal title saved.'
        }
    }

    if ($Original) {
        if ($Global:OriginalTerminalTitle) {
            $Host.UI.RawUI.WindowTitle = $Global:OriginalTerminalTitle
        } else {
            if (-not $Quiet) {
                Write-Host 'Original terminal title not saved.' -ForegroundColor Red
            }
        }
    } else {
        if (-not $Global:OriginalTerminalTitle) {
            Save-TerminalTitle -Quiet
        }
        $Host.UI.RawUI.WindowTitle = $Title
    }
}
#EndRegion '.\Private\Lib\Set-TerminalTitle.ps1' 44
#Region '.\Private\MessageTrace\Build-TraceContinuation.ps1' -1

function Build-TraceContinuation {
    # helper: parse continuation Hints from the cmdlet's Warning text
    param([string]$WarningText)

    $cmdText = [regex]::Match($WarningText, 'Get-MessageTraceV2\s.+').Value
    if (-not $cmdText) { return $null }

    $next = @{}

    $sd = [regex]::Match($cmdText, '-StartDate\s+"([^"]+)"').Groups[1].Value
    $ed = [regex]::Match($cmdText, '-EndDate\s+"([^"]+)"').Groups[1].Value
    if ($sd) { $next['StartDate'] = [datetime]$sd }
    if ($ed) { $next['EndDate'] = [datetime]$ed }

    # capture any -starting* param (eg, -StartingRecipientAddress)
    $startMatch = [regex]::Match($cmdText, '-(Starting\w+)\s+"([^"]+)"')
    if ($startMatch.Success) {
        $paramName = $startMatch.Groups[1].Value
        $paramValue = $startMatch.Groups[2].Value
        $next[$paramName] = $paramValue
    }

    if ($next.Count -eq 0) { return $null }
    return $next
}
#EndRegion '.\Private\MessageTrace\Build-TraceContinuation.ps1' 26
#Region '.\Private\MessageTrace\Get-WorkingList.ps1' -1

function Get-WorkingList {
    # helper: ensure each list is sorted; if not, sort it into a new list
    param(
        [System.Collections.Generic.List[psobject][]] $InputList,
        [string] $KeyProperty,
        [bool] $IsAscending
    )
    $InnerType = 'System.Collections.Generic.List[psobject]'
    $Working = New-Object "System.Collections.Generic.List[$InnerType]"
    foreach ($SingleList in $InputList) {
        if (-not $SingleList -or $SingleList.Count -eq 0) {
            $Working.Add([System.Collections.Generic.List[psobject]]::new())
            continue
        }

        $IsSortedParams = @{
            InputList   = $SingleList
            KeyProperty = $KeyProperty
            IsAscending = $IsAscending
        }
        if (Test-IsSorted @IsSortedParams) {
            # already sorted; reuse as-is
            $Working.Add($SingleList)
        } else {
            # not sorted; sort and materialize into a new strongly-typed List[psobject]
            $sortParams = @{
                Property   = $KeyProperty
                Descending = -not $IsAscending
            }
            $Sorted = @( $SingleList | Sort-Object @sortParams )
            $AsList = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Item in $Sorted) { $AsList.Add($Item) }
            $Working.Add($AsList)
        }
    }
    return , $Working
}
#EndRegion '.\Private\MessageTrace\Get-WorkingList.ps1' 38
#Region '.\Private\MessageTrace\Merge-ListOnDate.ps1' -1

function Merge-ListOnDate {
    # merges lists
    [OutputType([System.Collections.Generic.List[psobject]])]
    [CmdletBinding(DefaultParameterSetName = 'Ascending')]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Lists')]
        [System.Collections.Generic.List[psobject][]] $List,

        [Parameter(Mandatory = $true)]
        [string] $PropertyName,

        [Parameter(Mandatory, ParameterSetName = 'Ascending')]
        [switch] $Ascending,

        [Parameter(Mandatory, ParameterSetName = 'Descending')]
        [switch] $Descending
    )

    # validate at least one list exists
    if (-not $List -or $List.Count -eq 0) {
        return [System.Collections.Generic.List[psobject]]::new()
    }

    # determine direction bool once
    $IsAscending = $Ascending -and -not $Descending

    # build working lists (sorted if needed)
    $WorkingListParams = @{
        InputList   = $List
        KeyProperty = $PropertyName
        IsAscending = $IsAscending
    }
    $WorkingLists = Get-WorkingList @WorkingListParams

    # try to use PriorityQueue if available (PowerShell 7+ / .NET 6+)
    $PriorityQueueType = $null
    try {
        $PriorityQueueType = [System.Collections.Generic.PriorityQueue``2].MakeGenericType(
            [psobject], [long]
        )
    } catch {
        $PriorityQueueType = $null
    }

    # if property looks like DateTime, prefer ticks for priority; otherwise fall back at runtime
    $GetPriority = {
        param($Value, [bool] $Asc)
        if ($Value -is [datetime]) {
            $Ticks = [long]$Value.Ticks
            if ($Asc) { return $Ticks }
            else { return [long]::MaxValue - $Ticks }
        }
        elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or
            $Value -is [double] -or $Value -is [single]
        ) {
            $Num = [double]$Value
            if ($Asc) { return [long][math]::Round($Num) }
            else {
                # crude reversal for numerics
                return [long][math]::Round([double]::MaxValue - $Num)
            }
        }
        else {
            return 0
        }
    }

    # if PriorityQueue is available and the key type is suitable, use it;
    # otherwise use portable k-way scan
    $UsePriorityQueue = $false
    if ($null -ne $PriorityQueueType) {
        # quick probe first non-null key
        $ProbeKey = $null
        foreach ($List in $WorkingLists) {
            if ($List.Count -gt 0) {
                $ProbeKey = $List[0].$PropertyName
                if ($null -ne $ProbeKey) { break }
            }
        }
        if ($ProbeKey -is [datetime] -or $ProbeKey -is [int] -or $ProbeKey -is [long] -or
            $ProbeKey -is [double] -or $ProbeKey -is [decimal] -or $ProbeKey -is [single]
        ) {
            $UsePriorityQueue = $true
        }
    }

    $MergedList = [System.Collections.Generic.List[psobject]]::new()

    if ($UsePriorityQueue) {
        # priority-queue merge (O(N log k))
        $Queue = [Activator]::CreateInstance($PriorityQueueType)

        # track current indexes per list
        $CurrentIndexes = [System.Collections.Generic.List[int]]::new()
        foreach ($L in $WorkingLists) { $CurrentIndexes.Add(0) }

        # enqueue first element from each list
        for ($ListIndex = 0; $ListIndex -lt $WorkingLists.Count; $ListIndex++) {
            $IndexInList = $CurrentIndexes[$ListIndex]
            if ($IndexInList -ge $WorkingLists[$ListIndex].Count) { continue }
            $Item = $WorkingLists[$ListIndex][$IndexInList]
            $Key = $Item.$PropertyName
            $Priority = & $GetPriority $Key $IsAscending
            # if priority equals zero due to unknown type, bail to portable path
            if ($Priority -eq 0 -and -not ($Key -is [datetime])) {
                $UsePriorityQueue = $false
                break
            }
            # store a small envelope with list index and item index
            $Envelope = [pscustomobject]@{
                ListIndex = $ListIndex
                ItemIndex = $IndexInList
                Item      = $Item
            }
            $null = $Queue.Enqueue($Envelope, $Priority)
        }

        if ($UsePriorityQueue) {
            while ($Queue.Count -gt 0) {
                $OutEnvelope = $null
                $OutPriority = 0L
                $null = $Queue.TryDequeue([ref]$OutEnvelope, [ref]$OutPriority)
                $MergedList.Add($OutEnvelope.Item)

                # advance the corresponding list and enqueue next
                $ListIndex = $OutEnvelope.ListIndex
                $CurrentIndexes[$ListIndex] = $CurrentIndexes[$ListIndex] + 1
                $NextIndex = $CurrentIndexes[$ListIndex]
                if ($NextIndex -lt $WorkingLists[$ListIndex].Count) {
                    $NextItem = $WorkingLists[$ListIndex][$NextIndex]
                    $NextKey = $NextItem.$PropertyName
                    $NextPriority = & $GetPriority $NextKey $IsAscending
                    $NextEnvelope = [pscustomobject]@{
                        ListIndex = $ListIndex
                        ItemIndex = $NextIndex
                        Item      = $NextItem
                    }
                    $null = $Queue.Enqueue($NextEnvelope, $NextPriority)
                }
            }

            return $MergedList
        }
        # else fall through to portable path
    }

    # portable k-way scan (works everywhere; O(N * k))
    $CurrentPortableIndexes = [System.Collections.Generic.List[int]]::new()
    foreach ($L in $WorkingLists) { $CurrentPortableIndexes.Add(0) }

    while ($true) {
        $SelectedListIndex = -1
        $SelectedValue = $null

        for ($ListIndex = 0; $ListIndex -lt $WorkingLists.Count; $ListIndex++) {
            $IndexInList = $CurrentPortableIndexes[$ListIndex]
            if ($IndexInList -ge $WorkingLists[$ListIndex].Count) { continue }

            $Candidate = $WorkingLists[$ListIndex][$IndexInList]
            $CandidateValue = $Candidate.$PropertyName

            if ($SelectedListIndex -eq -1) {
                $SelectedListIndex = $ListIndex
                $SelectedValue = $CandidateValue
                continue
            }

            if ($IsAscending) {
                if ($CandidateValue -lt $SelectedValue) {
                    $SelectedListIndex = $ListIndex
                    $SelectedValue = $CandidateValue
                }
            } else {
                if ($CandidateValue -gt $SelectedValue) {
                    $SelectedListIndex = $ListIndex
                    $SelectedValue = $CandidateValue
                }
            }
        }

        if ($SelectedListIndex -eq -1) { break }

        $PortIdx = $CurrentPortableIndexes[$SelectedListIndex]
        $MergedList.Add($WorkingLists[$SelectedListIndex][$PortIdx])
        $CurrentPortableIndexes[$SelectedListIndex] = $PortIdx + 1
    }

    return $MergedList
}
#EndRegion '.\Private\MessageTrace\Merge-ListOnDate.ps1' 191
#Region '.\Private\MessageTrace\Request-MessageTrace.ps1' -1

function Request-MessageTrace {
    [CmdletBinding()]
    param(
        [string[]] $SenderAddress,
        [string[]] $RecipientAddress,

        # #FIXME convert to start and end dates
        # [datetime] $StartDateUtc,
        # [datetime] $EndDateUtc,

        [Parameter(Mandatory)]
        [ValidateRange(1, 90)]
        [int] $Days,

        [int] $ResultLimit = 50000,
        [switch] $Quiet
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $MaxPageSize = 5000
        $AbsoluteEnd = Get-Date
        $AbsoluteStart = $AbsoluteEnd.AddDays(-1 * $Days)
        $AllMessages = [System.Collections.Generic.List[psobject]]::new()

        # # adjust start date if older than 90 days.
        # $90DaysAgo = (Get-Date).AddDays(-90).ToUniversalTime()
        # if ($StartDateUtc -lt $90DaysAgo) {
        #     $DateString = $StartDateUtc.ToLocalTime().ToString('MM/dd/yy hh:mmtt')
        #     Write-Host @Yellow "${Function}: ${DateString} is more than max range of 90 days."
        #         # Setting to 90 days.
        #     $StartDateUtc = $90DaysAgo
        # }

        # build non-overlapping 10-day chunks, newest to oldest
        $Chunks = [System.Collections.Generic.List[object]]::new()
        $ChunkEnd = $AbsoluteEnd
        while ($ChunkEnd -gt $AbsoluteStart) {
            $ChunkStart = $ChunkEnd.AddDays(-10)
            if ($ChunkStart -lt $AbsoluteStart) {
                $ChunkStart = $AbsoluteStart
            }
            $Chunks.Add(
                [pscustomobject]@{
                    Start = $ChunkStart
                    End = $ChunkEnd
                }
            )
            # prevent overlap: next Chunk ends just before this Chunk starts
            $ChunkEnd = $ChunkStart.AddTicks(-1)
        }
    }

    process {

        foreach ($Chunk in $Chunks) {
            # prepare base params for this Chunk
            $LoopParams = @{
                StartDate      = $Chunk.Start
                EndDate        = $Chunk.End
                ResultSize     = $MaxPageSize
                WarningAction = 'Continue'
                WarningVariable  = '+Warn'
                ErrorAction    = 'Stop'
            }
            if ($SenderAddress) {
                $LoopParams['SenderAddress'] = $SenderAddress
            }
            if ($RecipientAddress) {
                $LoopParams['RecipientAddress'] = $RecipientAddress
            }

            $StartDateString = $LoopParams.StartDate.ToString("MM/dd/yy")
            $EndDateString = $LoopParams.EndDate.ToString("MM/dd/yy")
            if (-not $Quiet) {
                Write-IRT "Requesting message trace from ${StartDateString} to ${EndDateString}"
            }

            # request first page in this chunk
            $SleepCount = 0
            while ($true) {
                try {
                    $Warn = @()
                    $Page = [psobject[]]@( Get-MessageTraceV2 @LoopParams 3>$null )
                    break
                }
                catch {
                    # handle exo throttling with backoff;
                    # on any other error, return what we have so far
                    $RatePattern = 'surpassed the permitted limit|try again later'
                    $IsRateLimit = $_.Exception.Message -match $RatePattern
                    $IsWriteError = $_.FullyQualifiedErrorId -match 'Write-ErrorMessage'
                    if ($IsRateLimit -and $IsWriteError -and $SleepCount -lt 5) {
                        Write-IRT "$($_.Exception.Message)" -Level Error
                        Write-IRT "Pausing for 60 seconds..." -Level Warn
                        $SleepCount++
                        Start-Sleep -Seconds 60
                        continue
                    }
                    else {
                        Write-IRT "Unable to complete operation. Returning." -Level Warn
                        Write-Output $AllMessages
                        return
                    }
                }
            }
            $PageCount = ($Page | Measure-Object).Count
            if (-not $Quiet) { Write-IRT "Retrieved ${PageCount} messages." }

            # add page messages to AllMessages
            if ($PageCount) {
                foreach ($i in $Page) {
                    $AllMessages.Add($i)
                }
            }

            # if ResultLimit hit, return
            if ($AllMessages.Count -ge $ResultLimit) {
                Write-Output ($AllMessages | Select-Object -First $ResultLimit)
                return
            }

            # keep following the service-provided continuation only while we hit the page size limit
            while ($PageCount -eq $MaxPageSize) {
                $Hint = $Warn |
                    Where-Object { $_ -like '*Get-MessageTraceV2*' } |
                    Select-Object -Last 1
                if (-not $Hint) { break }
                $NextParams = Build-TraceContinuation -WarningText $Hint
                if (-not $NextParams) { break }

                # reset any existing -starting* keys, then merge the new Hints
                # (clamped to the chunk)
                foreach ($k in @($LoopParams.Keys)) {
                    if ($k -like 'Starting*') {
                        $null = $LoopParams.Remove($k)
                    }
                }
                foreach ($k in $NextParams.Keys) {
                    if ($k -eq 'StartDate') {
                        $LoopParams[$k] = if ($NextParams[$k] -lt $Chunk.Start) {
                            $Chunk.Start
                        }
                        else {
                            $NextParams[$k]
                        }
                    }
                    elseif ($k -eq 'EndDate') {
                        $LoopParams[$k] = if ($NextParams[$k] -gt $Chunk.End) {
                            $Chunk.End
                        }
                        else {
                            $NextParams[$k]
                        }
                    }
                    else {
                        $LoopParams[$k] = $NextParams[$k]
                    }
                }

                # next page for this chunk
                $StartDateString = $LoopParams.StartDate.ToString("MM/dd/yy")
                $EndDateString = $LoopParams.EndDate.ToString("MM/dd/yy")
                if (-not $Quiet) {
                    Write-IRT "Requesting message trace from ${StartDateString} to ${EndDateString}"
                }

                $SleepCount = 0
                while ($true) {
                    try {
                        $Warn = @()
                        $Page = [psobject[]]@( Get-MessageTraceV2 @LoopParams 3>$null )
                        break
                    }
                    catch {
                        # handle exo throttling with backoff;
                        # on any other error, return what we have so far
                        $RatePattern = 'surpassed the permitted limit|try again later'
                        $IsRateLimit = $_.Exception.Message -match $RatePattern
                        $IsWriteError = $_.FullyQualifiedErrorId -match 'Write-ErrorMessage'
                        if ($IsRateLimit -and $IsWriteError -and $SleepCount -lt 5) {
                            Write-IRT "$($_.Exception.Message)" -Level Error
                            Write-IRT "Pausing for 60 seconds..." -Level Warn
                            $SleepCount++
                            Start-Sleep -Seconds 60
                            continue
                        }
                        else {
                            Write-IRT "Unable to complete operation. Returning." -Level Warn
                            Write-Output $AllMessages
                            return
                        }
                    }
                }

                $PageCount = ($Page | Measure-Object).Count
                if (-not $Quiet) { Write-IRT "Retrieved ${PageCount} messages." }
                foreach ($m in $Page) { $AllMessages.Add($m) }
                if (($AllMessages | Measure-Object).Count -ge $ResultLimit) {
                    Write-Output ($AllMessages | Select-Object -First $ResultLimit)
                    return
                }
            }

            # if we got here, either page count < 5000 (done with this chunk)
            # or no more Hint was provided
        }

        Write-Output $AllMessages
    }
}
#EndRegion '.\Private\MessageTrace\Request-MessageTrace.ps1' 212
#Region '.\Private\MessageTrace\Request-MessageTraceV1.ps1' -1

function Request-MessageTraceV1 {
    param(
        [string[]] $SenderAddress,
        [string[]] $RecipientAddress,

        [Alias('InternetMessageId')]
        [string[]] $MessageId,

        [Parameter(Mandatory)]
        [datetime] $StartDate,
        [Parameter(Mandatory)]
        [datetime] $EndDate,
        [int] $ResultLimit = 50000,
        [switch] $Quiet
    )
    begin {
        Update-IRTToken -Service 'Exchange'
        $PageSize = 5000
        $Page = 1
        $MoreToGet = $true
        $Params = @{
            StartDate = $StartDate
            EndDate   = $EndDate
            PageSize  = $PageSize
        }
        if ( $SenderAddress ) { $Params['SenderAddress'] = $SenderAddress }
        if ( $RecipientAddress ) { $Params['RecipientAddress'] = $RecipientAddress }
        if ( $MessageId ) { $Params['MessageId'] = $MessageId }
    }

    process {

        # get all records
        $AllMessages = [System.Collections.Generic.List[psobject]]::new()
        while ($MoreToGet -and $AllMessages.Count -le $ResultLimit ) {

            $Params['Page'] = $Page

            # retrieve one page
            if (-not $Quiet) { Write-IRT "Requesting message trace page ${Page}" }
            $Params['WarningAction'] = 'SilentlyContinue'
            $Params['WarningVariable'] = 'mtWarnings'
            $PageResults = [psobject[]]@(Get-MessageTrace @Params)
            $mtWarnings | Where-Object { $_ -notlike '*Get-MessageTrace will start deprecating*' } |
                ForEach-Object { Write-Warning $_ }
            foreach ($i in $PageResults) { [void]$AllMessages.Add($i) }

            # stop if the page had less than max page size
            if (($PageResults | Measure-Object).Count -lt $PageSize) {
                $MoreToGet = $false
            }
            else {
                $Page++
            }
        }

        return $AllMessages
    }
}
#EndRegion '.\Private\MessageTrace\Request-MessageTraceV1.ps1' 60
#Region '.\Private\MessageTrace\Test-IsSorted.ps1' -1

function Test-IsSorted {
    # helper: check if a list is sorted on property in the requested direction
    param(
        [System.Collections.Generic.List[psobject]] $InputList,
        [string] $KeyProperty,
        [bool] $IsAscending
    )
    if ($InputList.Count -lt 2) { return $true }
    $Previous = $InputList[0].$KeyProperty
    for ($Index = 1; $Index -lt $InputList.Count; $Index++) {
        $Current = $InputList[$Index].$KeyProperty
        if ($IsAscending) {
            if ($Current -lt $Previous) { return $false }
        } else {
            if ($Current -gt $Previous) { return $false }
        }
        $Previous = $Current
    }
    return $true
}
#EndRegion '.\Private\MessageTrace\Test-IsSorted.ps1' 21
#Region '.\Private\MessageTrace\Test-MergeSortedListsOnDate.ps1' -1

function Test-MergeSortedListsOnDate {
    [CmdletBinding()]
    param(
        # show merged outputs (off by default to keep output minimal)
        [switch] $ShowMerged
    )

    # helper: build a strongly-typed list[psobject] from an array of datetimes
    function New-DateList {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [datetime[]] $Dates,
            [string] $Tag
        )
        $Out = [System.Collections.Generic.List[psobject]]::new()
        foreach ($D in $Dates) {
            # each item carries a date-like property and a tag so you can spot provenance
            $Out.Add([pscustomobject]@{ When = $D; Tag = $Tag })
        }
        return $Out
    }

    # helper: check a list is sorted on the given property in the given direction
    function Test-IsSortedOn {
        param(
            [System.Collections.Generic.List[psobject]] $List,
            [string] $PropertyName,
            [bool] $Ascending
        )
        if ($List.Count -lt 2) { return $true }
        for ($I = 1; $I -lt $List.Count; $I++) {
            $Prev = $List[$I - 1].$PropertyName
            $Curr = $List[$I].$PropertyName
            if ($Ascending) {
                if ($Curr -lt $Prev) { return $false }
            } else {
                if ($Curr -gt $Prev) { return $false }
            }
        }
        return $true
    }

    # build three lists; one intentionally unsorted to validate auto-sort behavior
    $ListOne = New-DateList -Dates @(
        [datetime]'2025-01-01',
        [datetime]'2025-01-03',
        [datetime]'2025-01-05'
    ) -Tag 'L1'

    $ListTwo = New-DateList -Dates @(
        [datetime]'2025-01-02',
        [datetime]'2025-01-04'
    ) -Tag 'L2'

    # intentionally out of order
    $ListThree = New-DateList -Dates @(
        [datetime]'2025-01-07',
        [datetime]'2025-01-06'
    ) -Tag 'L3'

    $AllInputCount = $ListOne.Count + $ListTwo.Count + $ListThree.Count

    # run ascending merge
    $AscParams = @{
        Lists        = @($ListOne, $ListTwo, $ListThree)
        PropertyName = 'When'
        Ascending    = $true
    }
    $MergedAsc = Merge-SortedListsOnDate @AscParams

    # run descending merge
    $DescParams = @{
        Lists        = @($ListOne, $ListTwo, $ListThree)
        PropertyName = 'When'
        Descending   = $true
    }
    $MergedDesc = Merge-SortedListsOnDate @DescParams

    # perform simple assertions
    $Failures = [System.Collections.Generic.List[string]]::new()

    if ($MergedAsc.Count -ne $AllInputCount) {
        $Failures.Add("ascending: expected $AllInputCount items, got $($MergedAsc.Count)")
    }
    if ($MergedDesc.Count -ne $AllInputCount) {
        $Failures.Add("descending: expected $AllInputCount items, got $($MergedDesc.Count)")
    }

    if (-not (Test-IsSortedOn -List $MergedAsc -PropertyName 'When' -Ascending $true)) {
        $Failures.Add('ascending: merge result is not sorted ascending on When')
    }
    if (-not (Test-IsSortedOn -List $MergedDesc -PropertyName 'When' -Ascending $false)) {
        $Failures.Add('descending: merge result is not sorted descending on When')
    }

    # spot-check boundaries
    $AscFirst = if ($MergedAsc.Count) { $MergedAsc[0].When } else { $null }
    $AscLast = if ($MergedAsc.Count) { $MergedAsc[-1].When } else { $null }
    $DescFirst = if ($MergedDesc.Count) { $MergedDesc[0].When } else { $null }
    $DescLast = if ($MergedDesc.Count) { $MergedDesc[-1].When } else { $null }

    if ($AscFirst -ne [datetime]'2025-01-01' -or $AscLast -ne [datetime]'2025-01-07') {
        $Failures.Add('ascending: first/last boundary dates are incorrect')
    }
    if ($DescFirst -ne [datetime]'2025-01-07' -or $DescLast -ne [datetime]'2025-01-01') {
        $Failures.Add('descending: first/last boundary dates are incorrect')
    }

    # build result object
    $Result = [pscustomobject]@{
        Passed           = ($Failures.Count -eq 0)
        FailureCount     = $Failures.Count
        Failures         = if ($Failures.Count) { $Failures } else { @() }
        TotalInputItems  = $AllInputCount
        AscendingCount   = $MergedAsc.Count
        DescendingCount  = $MergedDesc.Count
        AscendingFirst   = $AscFirst
        AscendingLast    = $AscLast
        DescendingFirst  = $DescFirst
        DescendingLast   = $DescLast
        ShowMergedHint   = 're-run with -ShowMerged to see merged outputs'
    }

    if ($ShowMerged) {
        # when requested, also emit the merged lists (as properties to avoid noisy pipeline output)
        $Result | Add-Member -NotePropertyName 'MergedAscending'  -NotePropertyValue $MergedAsc
        $Result | Add-Member -NotePropertyName 'MergedDescending' -NotePropertyValue $MergedDesc
    }

    # return the summary object; no extraneous screen output
    Write-Output $Result
}
#EndRegion '.\Private\MessageTrace\Test-MergeSortedListsOnDate.ps1' 134
#Region '.\Private\OnPremAd\Get-AdGlobalUserObject.ps1' -1

function Get-AdGlobalUserObject {
    <#
    .SYNOPSIS
    Gets user objects from global variables. Designed to be used by other scripts.

    .DESCRIPTION
    Internal helper. Returns $Global:IRT_UserObject as a list. Used by onprem_ad functions
    as the fallback user-resolution mechanism when no -UserObject parameter is supplied
    directly.

    .NOTES
    Version: 1.0.0
    #>
    #>
    [OutputType([System.Collections.Generic.List[System.Management.Automation.PSObject]])]
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
    }

    process {

        if ($Global:IRT_UserObject) {
            $ScriptUserObjects.Add($Global:IRT_UserObject)
        }

        return $ScriptUserObjects
    }
}
#EndRegion '.\Private\OnPremAd\Get-AdGlobalUserObject.ps1' 35
#Region '.\Private\OnPremAd\Set-AdUserEnabled.ps1' -1

function Set-AdUserEnabled {
    <#
    .SYNOPSIS
    Set Enabled property on on-premises AD user(s).
    Called by Disable-IRTAdUser and Enable-IRTAdUser.

    .DESCRIPTION
    Core implementation for enabling or disabling AD user accounts. For each user, calls
    Enable-AdAccount or Disable-AdAccount using $env:ComputerName as the target DC, then
    re-fetches the account to confirm the Enabled state changed. Triggers AD replication
    via repadmin if running on a DC, and Start-ADSyncSyncCycle if the ADSync service is
    local. Not typically called directly - use Disable-AdUser or Enable-AdUser instead.

    .PARAMETER UserObject
    One or more AD user objects to modify. Falls back to global session objects if omitted.

    .PARAMETER Enabled
    Required. $true to enable the account, $false to disable it.

    .EXAMPLE
    Set-AdUserEnabled -UserObject $AdUser -Enabled $false
    Disables the specified user account.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $UserProperties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
        )

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }

        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }
    }

    process {

        if ( -not (Test-AdAvailable) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        Write-IRT ''

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # disable/enable the user object
            Write-IRT "`n$($Action.TrimEnd('e'))ing $($ScriptUserObject.SamAccountName)."
            $Params = @{
                Identity = $ScriptUserObject
                Server   = $env:ComputerName
            }
            if ($PSCmdlet.ShouldProcess($ScriptUserObject.SamAccountName, "$Action account")) {
                if ( $Enabled ) {
                    Enable-AdAccount @Params
                }
                else {
                    Disable-AdAccount @Params
                }
            }

            # get new object to show result
            Write-IRT "`nGetting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $UserProperties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add( $NewObject )
        }

        # show results
        $OutputObjects | Format-Table $UserProperties

        # push ad replication
        if ( Test-RunningOnDomainController ) {
            Write-IRT "Pushing AD replication."
            $null = & repadmin /syncall $env:ComputerName /APed *>&1
        }
        else {
            Write-Warning "Not running on a domain controller; skipping replication push."
        }

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ( $SyncService ) {
            Write-IRT "`nPushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            $Msg = "Azure sync isn't running on this server. " +
            "Run Push-IRTAdSync, or duplicate actions in M365."
            Write-IRT $Msg -Level Error
        }
    }
}
#EndRegion '.\Private\OnPremAd\Set-AdUserEnabled.ps1' 135
#Region '.\Private\OnPremAd\Test-AdAvailable.ps1' -1

function Test-AdAvailable {
    <#
    .SYNOPSIS
    Returns true if the ActiveDirectory module is available and a domain controller can be reached.

    .DESCRIPTION
    Internal helper. Returns $true only when the ActiveDirectory RSAT module is installed
    AND Get-ADDomain succeeds (i.e., a domain controller is reachable). Returns $false on
    any error. Used as a guard condition at the top of every onprem_ad function.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        return $false
    }

    try {
        $null = Get-ADDomain -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}
#EndRegion '.\Private\OnPremAd\Test-AdAvailable.ps1' 29
#Region '.\Private\OnPremAd\Test-RunningOnDomainController.ps1' -1

function Test-RunningOnDomainController {
    <#
    .SYNOPSIS
    Returns true if the current machine is a domain controller.

    .DESCRIPTION
    Internal helper. Compares $env:ComputerName against the list of domain controllers
    returned by Get-ADDomainController -Filter *. Returns $false on any error. Used to
    gate repadmin calls that must run on a DC.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    try {
        $DomainControllerNames = (Get-ADDomainController -Filter *).Name
        return $env:ComputerName -in $DomainControllerNames
    }
    catch {
        return $false
    }
}
#EndRegion '.\Private\OnPremAd\Test-RunningOnDomainController.ps1' 26
#Region '.\Private\Role\Get-UnknownObject.ps1' -1

function Get-UnknownObject {
    <#
	.SYNOPSIS
	Looks up an object by Id using cached ById hashtables.
	Falls back to Get-MgDirectoryObject if not found in cache.

	.NOTES
	Version: 2.0.0
    2.0.0 - Rewrote to use Request-* cached ById hashtables instead of direct Graph calls.
	#>
    [CmdletBinding()]
    param(
        [string] $Id
    )

    process {

        # try cached lookups first
        if ( $Global:IRT_UsersById -and $Global:IRT_UsersById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_UsersById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'User' -Force
            return $Obj
        }
        if ( $Global:IRT_GroupsById -and $Global:IRT_GroupsById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_GroupsById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'Group' -Force
            return $Obj
        }
        if ($Global:IRT_ServicePrincipalsById -and
            $Global:IRT_ServicePrincipalsById.ContainsKey($Id)
        ) {
            $Obj = $Global:IRT_ServicePrincipalsById[$Id]
            $AmSpParams = @{
                NotePropertyName  = 'ObjectType'
                NotePropertyValue = 'ServicePrincipal'
                Force             = $true
            }
            $Obj | Add-Member @AmSpParams
            return $Obj
        }

        # fallback to direct Graph lookup
        try {
            $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Id -ErrorAction Stop
            $AmUnkParams = @{
                NotePropertyName  = 'ObjectType'
                NotePropertyValue = 'Unknown'
                Force             = $true
            }
            $DirectoryObject | Add-Member @AmUnkParams
            return $DirectoryObject
        }
        catch {
            Write-Error "Unable to find object with Id: ${Id}"
        }
    }
}
#EndRegion '.\Private\Role\Get-UnknownObject.ps1' 58
#Region '.\Private\Role\New-RoleMemberObject.ps1' -1

function New-RoleMemberObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', ''
    )]
    param(
        [string] $Id,
        [Alias('Roles')] [string] $Role,
        [string] $RoleSource,
        $GraphObject
    )

    switch ( $GraphObject.ObjectType ) {
        'User' {
            return [pscustomobject]@{
                ObjectType        = 'User'
                Id                = $Id
                Enabled           = $GraphObject.AccountEnabled
                DisplayName       = $GraphObject.DisplayName
                UserPrincipalName = $GraphObject.UserPrincipalName
                RoleSource        = $RoleSource
                Roles             = $Role
            }
        }
        'ServicePrincipal' {
            return [pscustomobject]@{
                ObjectType           = 'ServicePrincipal'
                Id                   = $Id
                Enabled              = $GraphObject.AccountEnabled
                DisplayName          = $GraphObject.DisplayName
                ServicePrincipalType = $GraphObject.ServicePrincipalType
                Description          = $GraphObject.Description
                RoleSource           = $RoleSource
                Roles             = $Role
            }
        }
        'Group' {
            return [pscustomobject]@{
                ObjectType  = 'Group'
                Id          = $Id
                DisplayName = $GraphObject.DisplayName
                Description = $GraphObject.Description
                RoleSource  = $RoleSource
                Roles             = $Role
            }
        }
        default {
            Write-Error "Unknown object type '$($GraphObject.ObjectType)' for Id: ${Id}"
        }
    }
}
#EndRegion '.\Private\Role\New-RoleMemberObject.ps1' 51
#Region '.\Private\ServicePrincipal\Show-GraphServicePrincipalTree.ps1' -1

function Show-GraphServicePrincipalTree {
    <#
    .SYNOPSIS
    Renders a Graph service principal object as a compact property tree.

    .DESCRIPTION
    Projects the service principal object, excluding the noisy AdditionalProperties
    collection, then passes the result to Format-Tree for console display. Intended
    to be called via pipeline from Show-IRTServicePrincipal.

    .PARAMETER ServicePrincipalObject
    The service principal object(s) to render. Accepts pipeline input.

    .PARAMETER Depth
    Maximum recursion depth for nested objects. Default: 10.

    .OUTPUTS
    None. Output is written to the console via Format-Tree.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [int] $Depth = 10
    )

    begin {
        $Exclude = @(
            'AdditionalProperties'
        )
    }

    process {
        foreach ($ServicePrincipalObjectItem in $ServicePrincipalObject) {
            if ($null -eq $ServicePrincipalObjectItem) { continue }

            $Projected = $ServicePrincipalObjectItem |
                Select-Object -Property * -ExcludeProperty $Exclude

            $Params = @{
                Depth           = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
#EndRegion '.\Private\ServicePrincipal\Show-GraphServicePrincipalTree.ps1' 53
#Region '.\Private\UnifiedAuditLog\Build-AllOperationSheet.ps1' -1

function Build-AllOperationSheet {
    <#
    .SYNOPSIS
    Builds the AllOperations Excel worksheet for unified audit logs.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory)]
        $ExcelPackage,

        [hashtable] $MessageTraceTable,

        [Parameter(Mandatory)]
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [string] $Title,

        [Alias('OperationsSheetData')]
        [psobject[]] $OperationSheetData,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'

        $OperationsFromSheet = [System.Collections.Generic.HashSet[string]]::new()
        if ($OperationSheetData) {
            foreach ($Row in $OperationSheetData) {
                $Op = "$($Row.Workload)|$($Row.RecordType)|$($Row.Operation)"
                [void]$OperationsFromSheet.Add($Op)
            }
        }
        $OperationsFromLog = [System.Collections.Generic.HashSet[string]]::new()
    }

    process {

        #region ROW LOOP

        $RowCount = ($Log | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Row loop starting (${RowCount} rows) $Elapsed"
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $RowCount; $i++) {

            $LogEntry = $Log[$i]

            # save operations to create complete list
            $OpKey = "$($LogEntry.AuditData.Workload)|" +
            "$($LogEntry.AuditData.RecordType)|$($LogEntry.AuditData.Operation)"
            [void]$OperationsFromLog.Add($OpKey)

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10

            #region USERIDS
            if ( $LogEntry.UserIds -match '^ServicePrincipal_.*$' ) {
                $SpName = $LogEntry.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            else {
                $UserIds = $LogEntry.UserIds
            }

            #region IPADDRESSES
            $IpAddresses = [System.Collections.Generic.Hashset[string]]::new()
            if ( $LogEntry.AuditData.ClientIP ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIP
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                }
            }
            if ( $LogEntry.AuditData.ActorIpAddress ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ActorIpAddress
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                } }
            if ( $LogEntry.AuditData.ClientIPAddress ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIPAddress
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                }
            }
            $IpText = if ($IpAddresses.Count -gt 0) {
                ($IpAddresses | Sort-Object) -join ', '
            } else { '' }

            #region Summary
            $RecordType = $LogEntry.RecordType
            $Operations = $LogEntry.Operations
            $OperationString = $RecordType + ' ' + $Operations
            $EmailParams = @{
                Log = $LogEntry
            }
            if ($MessageTraceTable) { $EmailParams['MessageTraceTable'] = $MessageTraceTable }
            switch ( $OperationString ) {
                'AzureActiveDirectory Add member to role.' {
                    $EventObject = Get-AddRemoveRoleSummary -Log $LogEntry
                }
                'AzureActiveDirectory Remove member from role.' {
                    $EventObject = Get-AddRemoveRoleSummary -Log $LogEntry
                }
                'AzureActiveDirectory Update user.' {
                    $EventObject = Get-UpdateUserSummary -Log $LogEntry
                }
                'AzureActiveDirectoryStsLogon UserLoggedIn' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoggedOff' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoginFailed' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'ExchangeAdmin New-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $LogEntry
                }
                'ExchangeAdmin Set-ConditionalAccessPolicy' {
                    $EventObject = Get-SetConditionalAccessPolicySummary -Log $LogEntry
                }
                'ExchangeAdmin Set-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $LogEntry
                }
                'ExchangeItemAggregated AttachmentAccess' {
                    $EventObject = Get-AttachmentAccessSummary -Log $LogEntry
                }
                'ExchangeItemAggregated MailItemsAccessed' {
                    $EventObject = Get-MailItemsAccessedSummary @EmailParams
                }
                'ExchangeItem Create' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $LogEntry
                }
                'ExchangeItem Send' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $LogEntry
                }
                'ExchangeItem Update' {
                    $EventObject = Get-ExchangeItemUpdateSummary -Log $LogEntry
                }
                'ExchangeItemGroup HardDelete' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'ExchangeItemGroup MoveToDeletedItems' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'ExchangeItemGroup SoftDelete' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'SharePoint PageViewed' {
                    $EventObject = Get-PageViewedSummary -Log $LogEntry
                }
                'SharePoint PIMRoleAssigned' {
                    $EventObject = Get-PIMRoleAssignedSummary -Log $LogEntry -Cached:$Cached
                }
                'SharePoint SearchQueryPerformed' {
                    $EventObject = Get-SearchQueryPerformedSummary -Log $LogEntry
                }
                'SharePointFileOperation FileAccessed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileDownloaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileModified' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileModifiedExtended' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FilePreviewed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileSyncDownloadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileSyncUploadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileUploaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                default {
                    $EventObject = [pscustomobject]@{
                        Summary = ''
                    }
                }
            }

            # Date/Time
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw = $Raw
                    $DateColumnHeader = $DateTime
                    UserIds = $UserIds
                    Workload = $LogEntry.AuditData.Workload
                    RecordType = $LogEntry.RecordType
                    Operation = $LogEntry.AuditData.Operation
                    IpAddress = $IpText
                    Summary = $EventObject.Summary
                })

            if ($VerbosePreference -ne 'SilentlyContinue' -and ($i % 100 -eq 0)) {
                $Percent = [int]( ($i / $RowCount ) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
            }
        }

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed
        }

        #region EXPORT
        Write-Verbose "${FunctionName}: Export-Excel $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $ExcelParams = @{
            ExcelPackage  = $ExcelPackage
            WorkSheetname = $WorksheetName
            Title         = $Title
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        $Workbook = $Rows | Export-Excel @ExcelParams
        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]

        #region FORMATTING
        if ($Worksheet.Tables.Count -gt 0) {

            # get table ranges
            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableAddress = $Worksheet.Tables.Address | Select-Object -First 1
            $TableStartColumn = $TableAddress.Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = $TableAddress.Start.Row

            $SummaryColEntry = $Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Summary' }
            $SummaryColumn = $SummaryColEntry.Id | Convert-DecimalToExcelColumn
            $OperationColEntry = $Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Operation' }
            $OperationColumn = $OperationColEntry.Id | Convert-DecimalToExcelColumn

            # IP address conditional formatting
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

            # operations conditional formatting
            if ($OperationSheetData) {
                foreach ($Row in $OperationSheetData) {
                    if ($Row.Risk -eq 'High') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:" +
                            "${OperationColumn}${EndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = $Row.Operation
                            BackgroundColor = 'LightPink'
                        }
                        Add-ConditionalFormatting @CFParams
                    }
                    if ($Row.Risk -eq 'Medium') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:" +
                            "${OperationColumn}${EndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = $Row.Operation
                            BackgroundColor = 'LightGoldenrodYellow'
                        }
                        Add-ConditionalFormatting @CFParams
                    }
                }
            }

            # column widths
            $ColumnWidths = @{
                'Raw'              = 8
                $DateColumnHeader  = 26
                'UserIds'          = 30
                'Workload'         = 25
                'RecordType'       = 25
                'Operation'        = 25
                'IpAddress'        = 25
                'Summary'          = 200
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # date format
            $DateFormatParams = @{
                Worksheet    = $Worksheet
                Range        = "B:B"
                NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
            }
            Set-ExcelRange @DateFormatParams

            # font
            $FontParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            try { Set-ExcelRange @FontParams } catch {}

            # left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            # text wrapping on Summary (applied last to prevent other formatting from resetting it)
            $SummaryWrapParams = @{
                Worksheet = $Worksheet
                Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @SummaryWrapParams

        } # end if Tables.Count

        #region MISSING OPERATIONS
        # FIXME no hard coded paths! use config path
        $AllOperationsFileName = 'UALAllOperations.xlsx'
        $OperationsToAdd = [System.Collections.Generic.HashSet[PSCustomObject]]::new()
        foreach ($o in $OperationsFromLog) {
            if ($OperationsFromSheet.Add($o)) {
                $Split = $o.Split('|')
                [void]$OperationsToAdd.Add(
                    [PSCustomObject]@{
                        Workload   = $Split[0]
                        RecordType = $Split[1]
                        Operation  = $Split[2]
                    }
                )
            }
        }
        if (($OperationsToAdd | Measure-Object).Count -gt 0) {
            $OperationsSheetPath = $Global:IRT_Config.AllOperationsSheetPath
            Write-IRT "Add to ${AllOperationsFileName}:" -Level Warn
            $OperationsToAdd | Format-Table | Out-Host
            Write-IRT "Appending to: ${OperationsSheetPath}" -Level Warn
            $ExportParams = @{
                Path          = $OperationsSheetPath
                WorksheetName = 'Operations'
                Append        = $true
            }
            $OperationsToAdd | Export-Excel @ExportParams
        }

        return $Workbook
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Build-AllOperationSheet.ps1' 392
#Region '.\Private\UnifiedAuditLog\Build-UserLoginOperationsSheet.ps1' -1

function Build-UserLoginOperationsSheet {
    <#
    .SYNOPSIS
    Builds an Excel worksheet with sign-in specific columns for UserLoggedIn/Off/Failed UAL events.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[PSObject]] $Logs,

        [Parameter(Mandatory)]
        $ExcelPackage,

        [Parameter(Mandatory)]
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [string] $Title,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
    }

    process {

        #region ROW LOOP
        $RowCount = ($Logs | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Row loop starting (${RowCount} rows) $Elapsed"
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)

        for ($i = 0; $i -lt $RowCount; $i++) {

            $Log = $Logs[$i]

            # Raw
            $Raw = $Log | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($Log.$RawDateProperty) { $DateTime = $Log.$RawDateProperty.ToLocalTime() }

            # UserIds/Actor
            if ($Log.UserIds -match '^ServicePrincipal_.*$') {
                $SpName = $Log.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            else {
                $UserIds = $Log.UserIds
            }
            # FIXME If no userid, parse Id from $Log.AuditData.Actor[0].ID and resolve to name

            # Operation
            $Operation = $Log.AuditData.Operation

            # Error
            $ErrCode = $Log.AuditData.ErrorNumber
            $ErrorDescription = ConvertTo-HumanErrorDescription -ErrorCode $ErrCode

            # IpAddress
            $IpAddresses = [System.Collections.Generic.Hashset[string]]::new()
            if ($Log.AuditData.ClientIP) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIP } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            if ($Log.AuditData.ActorIpAddress) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ActorIpAddress } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            if ($Log.AuditData.ClientIPAddress) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIPAddress } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            $IpText = if ($IpAddresses.Count -gt 0) {
                ($IpAddresses | Sort-Object) -join ', '
            } else { '' }

            # Application (Target)
            $Application = $null
            $TargetId = $Log.AuditData.Target.ID
            if ($TargetId) {
                $Application = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            }
            if (-not $Application) { $Application = $TargetId }

            # DeviceProperties
            $DevDispEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DisplayName' }
            $DeviceName = $DevDispEntry.Value
            if (-not $DeviceName) {
                $DevDevNameEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'DeviceName' }
                $DeviceName = $DevDevNameEntry.Value
            }
            $OS = ($Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'OS' }).Value
            $DevBrwEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceBrowser' }
            $Browser = $DevBrwEntry.Value
            if (-not $Browser) {
                $DevBrwTypeEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'BrowserType' }
                $Browser = $DevBrwTypeEntry.Value
            }
            $DevTrustEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'TrustType' }
            $Trust = Convert-TrustType -TrustType $DevTrustEntry.Value
            $DevSessEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'SessionId' }
            $SessionId = $DevSessEntry.Value

            # UserAgent
            $DevUserAgentEntry = $Log.AuditData.ExtendedProperties |
                Where-Object { $_.Name -eq 'UserAgent' }
            $UserAgent = $DevUserAgentEntry.Value

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw          = $Raw
                    $DateColumnHeader = $DateTime
                    UserIds      = $UserIds
                    Operation    = $Operation
                    Error        = $ErrorDescription
                    IpAddress    = $IpText
                    Application  = $Application
                    Browser      = $Browser
                    OS           = $OS
                    Trust        = $Trust
                    DeviceName   = $DeviceName
                    SessionId    = $SessionId
                    UserAgent    = $UserAgent
                })
        }

        #region EXPORT
        Write-Verbose "${FunctionName}: Export-Excel $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $ExcelParams = @{
            ExcelPackage  = $ExcelPackage
            WorkSheetname = $WorksheetName
            Title         = $Title
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        $Workbook = $Rows | Export-Excel @ExcelParams
        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]

        #region FORMATTING
        Write-Verbose "${FunctionName}: Formatting $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        if ($Worksheet.Tables.Count -gt 0) {

            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableAddress = $Worksheet.Tables.Address | Select-Object -First 1
            $TableStartColumn = $TableAddress.Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = $TableAddress.Start.Row

            # IP address conditional formatting
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Add-IpInfoToSheet $Elapsed"
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

            # Application conditional formatting - highlight PowerShell/CLI tools
            $AppColEntry = $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Application' }
            $AppColumn = $AppColEntry.Id | Convert-DecimalToExcelColumn
            $PsAppStrings = @(
                'Azure Active Directory PowerShell'
                'Microsoft Azure CLI'
                'Microsoft Exchange REST API Based Powershell'
                'Microsoft Graph Command Line Tools'
            )
            foreach ($String in $PsAppStrings) {
                $CFParams = @{
                    Worksheet       = $Worksheet
                    Address         = "${AppColumn}${TableStartRow}:${AppColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $String
                    BackgroundColor = 'LightPink'
                }
                Add-ConditionalFormatting @CFParams
            }

            # Column widths
            $ColumnWidths = @{
                'Raw'         = 8
                $DateColumnHeader = 26
                'UserIds'     = 30
                'Operation'   = 20
                'Error'       = 25
                'IpAddress'   = 25
                'Application' = 25
                'Browser'     = 20
                'OS'          = 12
                'Trust'       = 12
                'DeviceName'  = 20
                'SessionId'   = 20
                'UserAgent'   = 150
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # Date format
            $DateFormatParams = @{
                Worksheet    = $Worksheet
                Range        = 'B:B'
                NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
            }
            Set-ExcelRange @DateFormatParams

            # # Text wrapping on IpAddress and UserAgent
            # $IpCol = ($Worksheet.Tables[0].Columns |
            #     Where-Object {$_.Name -eq 'IpAddress'}).Id |
            #     Convert-DecimalToExcelColumn
            # $IpWrapParams = @{
            #     Worksheet = $Worksheet
            #     Range     = "${IpCol}${TableStartRow}:${IpCol}${EndRow}"
            #     WrapText  = $true
            # }
            # Set-ExcelRange @IpWrapParams # FIXME maybe we don't want text wrapping?

            # Font
            try {
                $FontParams = @{
                    Worksheet = $Worksheet
                    Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                    FontName  = $Font
                }
                Set-ExcelRange @FontParams
            } catch {}

            # Left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

        } # end if Tables.Count

        return $Workbook
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Build-UserLoginOperationsSheet.ps1' 261
#Region '.\Private\UnifiedAuditLog\Get-AddRemoveRoleSummary.ps1' -1

function Get-AddRemoveRoleSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory "Remove member from role." and "Add member to role."
    events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # Target
        $TargetDictionary = $Log.AuditData.Target
        $Target = ($TargetDictionary | Where-Object { $_.Type -eq 5 }).ID
        $SummaryLines.Add("Target: ${Target}")

        # Role
        $ModifiedPropertiesDict = $Log.AuditData.ModifiedProperties
        if ($ModifiedPropertiesDict.Name -contains 'Role.DisplayName') {
            $RoleProps = $ModifiedPropertiesDict |
                Where-Object { $_.Name -eq 'Role.DisplayName' }
            $OldValue = $RoleProps.OldValue
            $NewValue = $RoleProps.NewValue
            if ($NewValue -and $OldValue) {
                $Role = "New: ${NewValue}, Old: ${OldValue}"
            }
            else {
                if ($OldValue) {
                    $Role = $OldValue
                }
                if ($NewValue) {
                    $Role = $NewValue
                }
            }
            $SummaryLines.Add("Role.DisplayName: ${Role}")
        }
        else {
            $TemplateProps = $ModifiedPropertiesDict |
                Where-Object { $_.Name -eq 'Role.TemplateId' }
            $Role = $TemplateProps.OldValue
            $SummaryLines.Add("Role.TemplateId: ${Role}")
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-AddRemoveRoleSummary.ps1' 65
#Region '.\Private\UnifiedAuditLog\Get-AttachmentAccessSummary.ps1' -1

function Get-AttachmentAccessSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItemAggregated AttachmentAccess events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        $null = $Log  # TODO: implement attachment log parsing (see FIXME below)
        # need to lookup email by ID.
        #FIXME logs only contain id numbers. need to find way to translate id to attachment name

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-AttachmentAccessSummary.ps1' 36
#Region '.\Private\UnifiedAuditLog\Get-ExchangeItemCreateSendSummary.ps1' -1

function Get-ExchangeItemCreateSendSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItem events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # Items
        foreach ( $Item in $Log.AuditData.Item ) {

            $Subject = $Item.Subject
            $SummaryLines.Add( "Subject: ${Subject}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-ExchangeItemCreateSendSummary.ps1' 39
#Region '.\Private\UnifiedAuditLog\Get-ExchangeItemDeleteSummary.ps1' -1

function Get-ExchangeItemDeleteSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItemGroup HardDelete events from UAL.

	.NOTES
	Version: 2.1.0
    2.1.0 - Moved wait logic to Show-IRTUnifiedAuditLog. Now receives resolved
            MessageTraceTable directly.
    2.0.0 - Replaced per-user variable with single IRT_MessageTraceTable. Added SharedState
            support for cross-runspace communication. Added timeout and -Test diagnostics.
    1.1.0 - Removed Auditdata param, added parsing for email subjects.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [hashtable] $MessageTraceTable
    )

    begin {
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # AffectedItems

        # build table by folder
        $FolderTable = @{}

        foreach ( $AffectedItem in $Log.AuditData.AffectedItems ) {

            $FolderPath = $AffectedItem.ParentFolder.Path

            # if table key doesn't exist, create it.
            if (-not $FolderTable.ContainsKey($FolderPath)) {
                $FolderTable[$FolderPath] = [System.Collections.Generic.List[psobject]]::new()
            }

            # add object to table
            $FolderTable[$FolderPath].Add($AffectedItem)
        }

        # loop through folders
        foreach ($Folder in $FolderTable.GetEnumerator()) {

            $SummaryLines.Add( "Folder: $($Folder.Name)" )

            # loop through items
            foreach ($Item in $Folder.Value) {

                $Subject = $null

                # if item has subject property, use it
                if ($Item.Subject) {
                    $Subject = $Item.Subject
                }
                elseif ($Item.InternetMessageId -and $MessageTraceTable) {
                    # if not, try to retrieve from message trace table.
                    $NormalizedId = ($Item.InternetMessageId -replace '[<>]', '').Trim()
                    if ($MessageTraceTable.ContainsKey($NormalizedId)) {
                        $Subject = $MessageTraceTable[$NormalizedId].Subject
                    }
                }

                # add best option to summary
                if ($Subject) {
                    $SummaryLines.Add( "    Subject: ${Subject}" )
                }
                elseif ($Item.InternetMessageId) {
                    $SummaryLines.Add( "    Item: $($Item.InternetMessageId)" )
                }
                else {
                    $SummaryLines.Add( "    Item: $($Item.Id)" )
                }
            }
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-ExchangeItemDeleteSummary.ps1' 90
#Region '.\Private\UnifiedAuditLog\Get-ExchangeItemUpdateSummary.ps1' -1

function Get-ExchangeItemUpdateSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItem Update events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ModifiedProperties
        foreach ( $Item in $Log.AuditData.ModifiedProperties ) {
            $SummaryLines.Add( "Modified: ${Item}" )
        }

        # Items
        foreach ( $Item in $Log.AuditData.Item ) {
            $Subject = $Item.Subject
            $SummaryLines.Add( "Item: ${Subject}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-ExchangeItemUpdateSummary.ps1' 43
#Region '.\Private\UnifiedAuditLog\Get-InboxRuleSummary.ps1' -1

function Get-InboxRuleSummary {
    <#
	.SYNOPSIS
    Parses ExchangeAdmin ???-InboxRule events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # AppPoolName
        $AppPoolName = $Log.AuditData.AppPoolName
        $SummaryLines.Add("AppPoolName: ${AppPoolName}")

        # Parameters
        foreach ($Parameter in $Log.AuditData.Parameters) {
            $Name = $Parameter.Name
            $Value = $Parameter.Value
            $SummaryLines.Add("${Name}: ${Value}")
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-InboxRuleSummary.ps1' 43
#Region '.\Private\UnifiedAuditLog\Get-LoginOperationSummary.ps1' -1

function Get-LoginOperationSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory UserLoggedIn, UserLoggedOff, and UserLoginFailed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log,

        [switch] $Cached
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ErrorNumber
        $ErrorDescription = ConvertTo-HumanErrorDescription -ErrorCode $Log.AuditData.ErrorNumber
        $SummaryLines.Add("Error: $ErrorDescription")

        # Target
        $TargetId = $Log.AuditData.Target.ID
        if ($TargetId) {
            # ensure global variable exists
            Request-GraphServicePrincipal -Return 'none' -Cached:$Cached

            # fetch name from table
            $TargetName = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            if ($TargetName) {
                $SummaryLines.Add("TargetApp: $TargetName")
            }
        }

        # DeviceProperties
        $DispNameEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DisplayName' }
        $DisplayName = $DispNameEntry.Value
        if (-not $DisplayName) {
            $DevNameEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceName' }
            $DisplayName = $DevNameEntry.Value
        }
        if ($DisplayName) { $SummaryLines.Add("DeviceDisplayName: $DisplayName") }
        $OS = ($Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'OS' }).Value
        if ($OS) { $SummaryLines.Add("OS: $OS") }
        $DevBrowserEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DeviceBrowser' }
        $Browser = $DevBrowserEntry.Value
        if (-not $Browser) {
            $BrwTypeEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'BrowserType' }
            $Browser = $BrwTypeEntry.Value
        }
        if ($Browser) { $SummaryLines.Add("Browser: $Browser") }
        $TrustEntry = $Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'TrustType' }
        $TrustType = Convert-TrustType -TrustType $TrustEntry.Value
        if ($TrustType) { $SummaryLines.Add("Trust: $TrustType") }

        # UserAgent
        $UserAgentEntry = $Log.AuditData.ExtendedProperties |
            Where-Object { $_.Name -eq 'UserAgent' }
        $UserAgent = $UserAgentEntry.Value
        if ($UserAgent) { $SummaryLines.Add("UserAgent: $UserAgent") }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-LoginOperationSummary.ps1' 82
#Region '.\Private\UnifiedAuditLog\Get-MailItemsAccessedSummary.ps1' -1

function Get-MailItemsAccessedSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItemAggregated MailItemsAccessed events from UAL.

	.NOTES
	Version: 2.1.0
    2.1.0 - Moved wait logic to Show-IRTUnifiedAuditLog. Now receives resolved
            MessageTraceTable directly.
    2.0.0 - Replaced per-user variable with single IRT_MessageTraceTable. Added SharedState
            support for cross-runspace communication. Added timeout and -Test diagnostics.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [hashtable] $MessageTraceTable
    )

    begin {
        $Summary = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ClientInfoString
        $ClientInfoString = $Log.AuditData.ClientInfoString
        $Summary.Add( "ClientInfoString: ${ClientInfoString}" )

        # Folders
        foreach ($Folder in $Log.AuditData.Folders) {

            $Summary.Add( "Folder: $($Folder.Path)" )
            $Items = $Folder.FolderItems

            # Items
            foreach ($Item in $Items) {
                $Subject = $null
                $InternetMessageId = $Item.InternetMessageId
                if ($MessageTraceTable -and $InternetMessageId) {
                    $NormalizedId = ($InternetMessageId -replace '[<>]', '').Trim()
                    $Trace = $MessageTraceTable[$NormalizedId]
                    if ($Trace) {
                        $Subject = $Trace.Subject
                    }
                }

                if ($Subject) {
                    $Summary.Add( "    Subject: ${Subject}" )
                }
                else {
                    $Summary.Add( "    Item: ${InternetMessageId}" )
                }
            }
        }

        # join strings, create return object
        $AllSummary = $Summary -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $AllSummary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-MailItemsAccessedSummary.ps1' 67
#Region '.\Private\UnifiedAuditLog\Get-PageViewedSummary.ps1' -1

function Get-PageViewedSummary {
    <#
	.SYNOPSIS
    Parses PageViewed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ObjectId
        $ObjectId = $Log.AuditData.ObjectId
        $SummaryLines.Add( "ObjectId: ${ObjectId}" )


        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-PageViewedSummary.ps1' 37
#Region '.\Private\UnifiedAuditLog\Get-PIMRoleAssignedSummary.ps1' -1

function Get-PIMRoleAssignedSummary {
    <#
	.SYNOPSIS
    Parses Sharepoint "PIMRoleAssigned" events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log,

        [switch] $Cached
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()

        $User = Request-GraphUser -Cached:$Cached
    }

    process {

        # User
        $GuidPattern = "\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b"
        $UserId = $Log.AuditData.EventData |
            Select-String -Pattern $GuidPattern -AllMatches |
            ForEach-Object { $_.Matches.Value }
        $UserPrincipalName = ($User | Where-Object { $_.Id -eq $UserId }).UserPrincipalName
        $SummaryLines.Add("User: ${UserPrincipalName}")

        # Role
        $ModifiedPropertiesDict = $Log.AuditData.ModifiedProperties
        $PimProps = $ModifiedPropertiesDict |
            Where-Object { $_.Name -eq 'PIMRoleAssigned' }
        $OldValue = $PimProps.OldValue
        $NewValue = $PimProps.NewValue
        if ($NewValue -and $OldValue) {
            $Role = "New: ${NewValue}, Old: ${OldValue}"
        }
        else {
            if ($OldValue) {
                $Role = $OldValue
            }
            if ($NewValue) {
                $Role = $NewValue
            }
        }
        $SummaryLines.Add("Role: ${Role}")

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-PIMRoleAssignedSummary.ps1' 63
#Region '.\Private\UnifiedAuditLog\Get-SearchQueryPerformedSummary.ps1' -1

function Get-SearchQueryPerformedSummary {
    <#
	.SYNOPSIS
    Parses SearchQueryPerformed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # SearchQueryText
        $SearchQueryText = $Log.AuditData.SearchQueryText
        $SummaryLines.Add( "SearchQueryText: ${SearchQueryText}" )

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-SearchQueryPerformedSummary.ps1' 36
#Region '.\Private\UnifiedAuditLog\Get-SetConditionalAccessPolicySummary.ps1' -1

function Get-SetConditionalAccessPolicySummary {
    <#
	.SYNOPSIS
    Parses ExchangeAdmin Set-ConditionalAccessPolicy events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # DisplayName
        $DisplayEntry = $Log.AuditData.Parameters | Where-Object { $_.Name -eq 'DisplayName' }
        $DisplayName = $DisplayEntry.Value
        $SummaryLines.Add("DisplayName: ${DisplayName}")

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-SetConditionalAccessPolicySummary.ps1' 37
#Region '.\Private\UnifiedAuditLog\Get-SharePointFileOperationSummary.ps1' -1

function Get-SharePointFileOperationSummary {
    <#
	.SYNOPSIS
    Parses Sharepoint FileAccessed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ObjectId. the full web url for the file. it seems like this property is present
        # on every sharepoint operation
        $ObjectId = $Log.AuditData.ObjectID
        if ($ObjectId) {
            $SummaryLines.Add( "ObjectId: ${ObjectId}" )
        }

        # ApplicationDisplayName. the application that generated the operation
        $ApplicationDisplayName = $Log.AuditData.ApplicationDisplayName
        if ($ApplicationDisplayName) {
            $SummaryLines.Add( "ApplicationDisplayName: ${ApplicationDisplayName}" )
        }

        # SourceFileName. just the name of the file
        $SourceFileName = $Log.AuditData.SourceFileName
        if ($SourceFileName) {
            $SummaryLines.Add( "SourceFileName: ${SourceFileName}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $SummaryObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $SummaryObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-SharePointFileOperationSummary.ps1' 51
#Region '.\Private\UnifiedAuditLog\Get-TeamsSessionStartedSummary.ps1' -1

function Get-TeamsSessionStartedSummary {
    <#
	.SYNOPSIS


	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [Parameter( Mandatory )]
        [pscustomobject] $CustomObject,

        [Alias('Users')]
        [psobject[]] $User,

        [switch] $Cached
    )

    begin {

        # variables
        $AuditData = $Log.AuditData | ConvertFrom-Json
        $User = Request-GraphUser -Cached:$Cached
    }

    process {

        # UserType
        $UserTypeNum = $AuditData.UserType
        $UserTypeWord = $Global:IRT_UalUserTypeTable[[int]$UserTypeNum]
        $UserTypeString = "${UserTypeNum}:${UserTypeWord}"
        $AddParams = @{
            MemberType = 'NoteProperty'
            Name       = 'UserType'
            Value      = $UserTypeString
        }
        $CustomObject | Add-Member @AddParams


        # user?



        # summary?


    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-TeamsSessionStartedSummary.ps1' 53
#Region '.\Private\UnifiedAuditLog\Get-UpdateUserSummary.ps1' -1

function Get-UpdateUserSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory "Update user." events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryStrings = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ModifiedProperties
        $Properties = ( $Log.AuditData.ModifiedProperties |
                Where-Object { $_.Name -eq "Included Updated Properties" } ).NewValue
        foreach ( $Property in $Properties ) {
            $SummaryStrings.Add( "Property: ${Property}" )
        }

        # join strings, create return object
        $SummaryString = $SummaryStrings -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $SummaryString
        }

        return $EventObject
    }
}
#EndRegion '.\Private\UnifiedAuditLog\Get-UpdateUserSummary.ps1' 39
#Region '.\Private\User\Format-SentinelDate.ps1' -1

function Format-SentinelDate {
    param(
        [pscustomobject]$Obj
    )
    # helper: normalize sentinel dates (year 1) to $null
    foreach ($Name in 'Birthday', 'HireDate') {
        $Prop = $Obj.PSObject.Properties[$Name]
        if (-not $Prop) { continue }
        $Value = $Prop.Value
        $IsEmptyDate = $false

        if ($Value -is [datetime]) {
            if ($Value.Year -le 1) { $IsEmptyDate = $true }
        } elseif ($Value) {
            try {
                $dt = [datetime]::Parse($Value)
                if ($dt.Year -le 1) { $IsEmptyDate = $true }
            } catch { }
        }

        if ($IsEmptyDate) { $Obj.$Name = $null }
    }
}
#EndRegion '.\Private\User\Format-SentinelDate.ps1' 24
#Region '.\Private\User\Get-FullUserObject.ps1' -1

function Get-FullUserObject {
    <#
    .SYNOPSIS
    retrieves a user with a broad set of properties and augments with optional ones.

    .NOTES
    version: 1.0.5
    - add pipeline support (by object or by id/upn)
    - keep signInActivity in initial selection
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    param(
        # pipe full user objects
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [ValidateNotNull()]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser] $UserObject,

        [Parameter(Mandatory, ValueFromPipeline,
            ValueFromPipelineByPropertyName, ParameterSetName = 'ById')]
        [Alias('Id')]
        [ValidateNotNullOrEmpty()]
        [string] $UserId,

        [Parameter(ParameterSetName = 'ByObject')]
        [Parameter(ParameterSetName = 'ById')]
        [switch] $NoRefresh
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ScriptUserObject = $UserObject

        # properties you can safely query on all users
        $SelectProps = @(
            'id', 'userPrincipalName', 'displayName', 'accountEnabled',
            'ageGroup', 'businessPhones', 'city', 'companyName', 'consentProvidedForMinor',
            'country', 'createdDateTime', 'creationType', 'department',
            'employeeHireDate', 'employeeId', 'employeeLeaveDateTime', 'employeeOrgData',
            'employeeType', 'externalUserState', 'externalUserStateChangeDateTime',
            'faxNumber', 'givenName', 'identities', 'imAddresses', 'isResourceAccount',
            'jobTitle', 'lastPasswordChangeDateTime', 'legalAgeGroupClassification',
            'licenseAssignmentStates', 'mail', 'mailNickname', 'mobilePhone', 'officeLocation',
            'onPremisesDistinguishedName', 'onPremisesDomainName', 'onPremisesExtensionAttributes',
            'onPremisesImmutableId', 'onPremisesLastSyncDateTime', 'onPremisesProvisioningErrors',
            'onPremisesSamAccountName', 'onPremisesSecurityIdentifier', 'onPremisesSyncEnabled',
            'onPremisesUserPrincipalName', 'otherMails', 'passwordPolicies', 'passwordProfile',
            'postalCode', 'preferredDataLocation', 'preferredLanguage', 'provisionedPlans',
            'proxyAddresses', 'securityIdentifier', 'showInAddressList',
            'signInSessionsValidFromDateTime', 'state', 'streetAddress', 'surname',
            'usageLocation', 'userType', 'signInActivity'
        )

        # properties that may error depending on licensing/mailbox/etc.
        $OptionalProps = @(
            'aboutMe', 'birthday', 'deviceEnrollmentLimit', 'hireDate', 'interests',
            'mailboxSettings', 'mailFolders', 'mySite', 'pastProjects', 'preferredName',
            'print', 'responsibilities', 'schools', 'skills'
        )
    }

    process {

        # if object is already full object, and -NoRefresh, don't query.
        if ($NoRefresh -and $PSCmdlet.ParameterSetName -eq 'ByObject' -and
            $ScriptUserObject.PSObject.Properties['AllProperties'] -and
            $ScriptUserObject.AllProperties) {
            Write-Output $ScriptUserObject
            return
        }

        # resolve the identifier for this pipeline item
        switch ($PSCmdlet.ParameterSetName) {
            'ById' { $ResolvedId = $UserId }
            'ByObject' { $ResolvedId = $ScriptUserObject.Id }
            default { $ResolvedId = $null }
        }

        if (-not $ResolvedId) {
            Write-Verbose "skipping item: could not resolve an id."
            return
        }

        # get base user with wide $select
        $GetParams = @{
            UserId      = $ResolvedId
            Property    = $SelectProps
            ErrorAction = 'Stop'
        }

        try {
            $ScriptUserObject = Get-MgUser @GetParams
        }
        catch {
            Write-Error "Get-MgUser failed for '$ResolvedId': $($_.Exception.Message)"
            if ($PSCmdlet.ParameterSetName -eq 'ByObject' -and $ScriptUserObject) {
                Write-Output $ScriptUserObject
            }
            return
        }

        # augment with optional properties (best-effort)
        foreach ($Property in $OptionalProps) {
            try {
                $OptionalParams = @{
                    UserId      = $ResolvedId
                    Property    = $Property
                    ErrorAction = 'Stop'
                }
                $TempUserObject = Get-MgUser @OptionalParams
                $ScriptUserObject.$Property = $TempUserObject.$Property
            }
            catch {
                $ErrMsg = "Unable to retrieve property '$Property' for '$ResolvedId': " +
                $_.Exception.Message
                Write-Verbose $ErrMsg
            }
        }

        # add property indicating object has all properties.
        $AmParams = @{
            NotePropertyName  = 'AllProperties'
            NotePropertyValue = $true
            Force             = $true
        }
        $ScriptUserObject | Add-Member @AmParams

        Write-Output $ScriptUserObject
    }
}
#EndRegion '.\Private\User\Get-FullUserObject.ps1' 130
#Region '.\Private\User\Set-UserEnabled.ps1' -1

function Set-UserEnabled {
    <#
	.SYNOPSIS
	Set AccountEnabled property on graph user(s). Called by Disable-GraphUser and Enable-GraphUser.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # variables
        $GetProperties = @(
            'AccountEnabled'
            'DisplayName'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
            'Id'
        )
        $TimeZoneInfo = [System.TimeZoneInfo]::Local

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # if disabling, force sign outs
            if ( -not $Enabled ) {
                Write-IRT "Revoking user sessions..."
                $Upn = $ScriptUserObject.UserPrincipalName
                if ($PSCmdlet.ShouldProcess($Upn, 'Revoke sign-in sessions')) {
                    $null = Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id
                }
            }

            # disable/enable account
            Write-IRT "$($Action.TrimEnd('e'))ing user account..."
            if ($PSCmdlet.ShouldProcess($ScriptUserObject.UserPrincipalName, "$Action account")) {
                Update-MgUser -UserId $ScriptUserObject.Id -AccountEnabled:$Enabled
            }

            # get new user object
            Write-IRT "Getting updated user properties."
            $NewUserObject = Get-MgUser -UserId $ScriptUserObject.Id -Property $GetProperties

            # display new object
            $NewUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ($NewUserObject.OnPremisesSyncEnabled) {
                $Msg = "User is synced from on-premises. ${Action} user in local AD too!"
                Write-IRT $Msg -Level Error
            }
        }


        ### show last onprem sync time
        # get date object
        if ($NewUserObject.OnPremisesSyncEnabled) {
            $LastOrgSync = (Get-MgOrganization).OnPremisesLastSyncDateTime
        }
        if ($LastOrgSync) {
            # build date string
            $BuildString = $LastOrgSync.ToLocalTime().ToString('MM/dd/yy hh:mmtt').ToLower()

            # create acronym from timezone full name
            if ($LastOrgSync.IsDaylightSavingTime()) {
                $TimeZoneName = $TimeZoneInfo.DaylightName
            }
            else {
                $TimeZoneName = $TimeZoneInfo.StandardName
            }
            $TimeZoneAcronym = -join ($TimeZoneName -split ' ' | ForEach-Object { $_[0] })

            # add time zone acronym to string
            $DateString = $BuildString + " " + $TimeZoneAcronym

            Write-IRT "Last on-premises sync:"
            Write-IRT $DateString
        }
    }
}
#EndRegion '.\Private\User\Set-UserEnabled.ps1' 123
#Region '.\Private\User\Show-GraphUserTree.ps1' -1

function Show-GraphUserTree {
    <#
	.SYNOPSIS
	Shows a graph user object in a compact tree view.

	.NOTES
	Version: 1.0.5
	#>
    [CmdletBinding()]
    param(
        # accept object(s) from pipeline or parameter
        [Parameter(ValueFromPipeline)]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject,

        [int]$Depth = 10
    )

    begin {
        # list of user properties to exclude
        $Exclude = @(
            'AllProperties'
            'AssignedPlans',
            'Drive',
            'ProvisionedPlans',
            'AdditionalProperties',
            'LicenseAssignmentStates'
        )
    }

    process {

        $ScriptUserObjects = $UserObject
        foreach ($ScriptUserObject in $ScriptUserObjects) {
            if ($null -eq $ScriptUserObject) { continue }

            # create a pscustomobject projection so we can safely tweak values
            $Projected = $ScriptUserObject | Select-Object -Property * -ExcludeProperty $Exclude
            Format-SentinelDate $Projected

            # call format-tree with defaults; always omit null/empty
            $Params = @{
                Depth        = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
#EndRegion '.\Private\User\Show-GraphUserTree.ps1' 50
#Region '.\Private\Utility\Add-IpInfoToSheet.ps1' -1

function Add-IpInfoToSheet {
    <#
    .SYNOPSIS
    Enriches IP address cells in an Excel worksheet with ip_info lookup data.

    .DESCRIPTION
    Reads IP addresses from the specified column(s) of an already-exported worksheet,
    queries ip_info for any not yet cached in $Global:IRT_IpInfo, then rewrites each
    cell as "ip1, ip2 [padding]\n\ntable1\n\ntable2". Handles comma-separated multi-IP
    cells (e.g., UAL rows with multiple source addresses).

    Does nothing if $Global:IRT_Config.IpInfoAvailable is $false or the worksheet has
    no table.

    .PARAMETER Worksheet
    An OfficeOpenXml worksheet object (e.g., from $Workbook.Workbook.Worksheets['Name']).

    .PARAMETER ColumnName
    One or more column names to enrich. Columns not present in the worksheet are
    silently skipped.

    .EXAMPLE
    Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

    .EXAMPLE
    Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'FromIP', 'ToIP'

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [AllowNull()]
        [Parameter(Mandatory)]
        $Worksheet,

        [Parameter(Mandatory)]
        [string[]] $ColumnName
    )

    if (-not $Global:IRT_Config.IpInfoAvailable) { return }
    if ($null -eq $Worksheet) { return }
    if ($Worksheet.Tables.Count -eq 0) { return }

    $Table = $Worksheet.Tables[0]
    $TableStartCol = $Table.Address.Start.Column
    $DataStartRow = $Table.Address.Start.Row + 1  # row 1 is the header
    $DataEndRow = $Table.Address.End.Row

    if ($DataEndRow -lt $DataStartRow) { return }

    # Build column-index map for requested columns that exist in this worksheet.
    $ColMap = @{}
    foreach ($Name in $ColumnName) {
        $TableCol = $Table.Columns | Where-Object { $_.Name -eq $Name }
        if ($TableCol) {
            $ColMap[$Name] = $TableStartCol + $TableCol.Id - 1
        }
    }
    if ($ColMap.Count -eq 0) { return }

    # First pass: collect all unique IPs across all target columns.
    $AllIps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($AbsCol in $ColMap.Values) {
        for ($Row = $DataStartRow; $Row -le $DataEndRow; $Row++) {
            $CellValue = $Worksheet.Cells[$Row, $AbsCol].Value
            if (-not $CellValue) { continue }
            foreach ($Part in ($CellValue -split ', ')) {
                $IpObj = $null
                if ([System.Net.IPAddress]::TryParse($Part.Trim(), [ref]$IpObj)) {
                    [void]$AllIps.Add($IpObj.ToString())
                }
            }
        }
    }
    if ($AllIps.Count -eq 0) { return }

    # Query ip_info for any IPs not already in the cache.
    $IpInfoTable = $Global:IRT_IpInfo
    $UnseenIps = @($AllIps | Where-Object { -not $IpInfoTable.ContainsKey($_) })
    if ($UnseenIps.Count -gt 0) {
        $env:PYTHONUTF8 = '1'
        $RawOutput = @(& ip_info --apis bulk --output_format jsontable --ip_addresses $UnseenIps)
        if ($LASTEXITCODE -ne 0) {
            Write-IRT "ip_info query failed (exit $LASTEXITCODE)." -Level Error
            return
        }
        $JsonStart = -1
        for ($i = 0; $i -lt $RawOutput.Length; $i++) {
            if ($RawOutput[$i] -match '^\{') { $JsonStart = $i; break }
        }
        if ($JsonStart -ge 0) {
            $JsonText = ($RawOutput[$JsonStart..($RawOutput.Length - 1)]) -join "`n"
            $JsonData = $JsonText | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($JsonData) {
                foreach ($Prop in $JsonData.PSObject.Properties) {
                    $IpInfoTable[$Prop.Name] = $Prop.Value
                }
            }
        }
    }

    # Second pass: rewrite cells with enriched content.
    foreach ($Name in $ColMap.Keys) {
        $AbsCol = $ColMap[$Name]
        for ($Row = $DataStartRow; $Row -le $DataEndRow; $Row++) {
            $Cell = $Worksheet.Cells[$Row, $AbsCol]
            $CellValue = $Cell.Value
            if (-not $CellValue) { continue }

            $ValidIps = [System.Collections.Generic.List[string]]::new()
            foreach ($Part in ($CellValue -split ', ')) {
                $IpObj = $null
                if ([System.Net.IPAddress]::TryParse($Part.Trim(), [ref]$IpObj)) {
                    [void]$ValidIps.Add($IpObj.ToString())
                }
            }
            if ($ValidIps.Count -eq 0) { continue }

            $CellLines = [System.Collections.Generic.List[string]]::new()
            $CellLines.Add(($ValidIps -join ', ') + (' ' * 20))
            foreach ($Ip in $ValidIps) {
                if ($IpInfoTable.ContainsKey($Ip)) {
                    $CellLines.Add($IpInfoTable[$Ip])
                }
            }

            # Only rewrite if we actually have enrichment data to add.
            if ($CellLines.Count -gt 1) {
                $Cell.Value = $CellLines -join "`n`n"
            }
        }
    }

    # Apply conditional formatting rules from the template for each enriched column.
    # ExcelWorkbook.Package is not a public property in the bundled EPPlus build.
    # Retrieve it via the non-public _package backing field so CF can be applied.
    $BindFlags = [System.Reflection.BindingFlags]'NonPublic,Instance'
    $PkgField = $Worksheet.Workbook.GetType().GetField('_package', $BindFlags)
    $DestPackage = if ($PkgField) { $PkgField.GetValue($Worksheet.Workbook) } else { $null }

    if ($null -ne $DestPackage) {
        foreach ($Name in $ColMap.Keys) {
            $ColLetter = $ColMap[$Name] | Convert-DecimalToExcelColumn
            $CopyParams = @{
                Source           = $Global:IRT_Config.IPConditionalFormattingTemplatePath
                SourceRange      = 'A1:A1048576'
                Destination      = $DestPackage
                DestinationSheet = $Worksheet.Name
                DestinationRange = "${ColLetter}:${ColLetter}"
            }
            Copy-ConditionalFormatting @CopyParams
        }
    }
}
#EndRegion '.\Private\Utility\Add-IpInfoToSheet.ps1' 156
#Region '.\Private\Utility\Convert-DecimalToExcelColumn.ps1' -1

function Convert-DecimalToExcelColumn {
    <#
	.SYNOPSIS
	Takes a number and returns an Excel column letter value.

    .EXAMPLE
    1 | Convert-DecimalToExcelColumn
    A

    26 | Convert-DecimalToExcelColumn
    Z

    27 | Convert-DecimalToExcelColumn
    AA

    28 | Convert-DecimalToExcelColumn
	AB

	.NOTES
	Version: 1.0.1
    1.0.1 - Fixed type casting error preventing script from working correctly for 27+.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Number
    )

    process {
        # initialize result variable
        $ColumnLetters = [System.Collections.Generic.List[char]]::new()

        # Use a local variable so [ValidateRange] on $Number is not re-evaluated
        $Current = $Number
        while ( $Current -gt 0 ) {

            # divide by 26
            [int]$Remainder = ($Current - 1) % 26

            # determine the corresponding letter (a=0 maps to A)
            $Letter = [char]([int][char]'A' + $Remainder)

            # prepend the letter to the result string
            $ColumnLetters.Insert(0, $Letter)

            # update the number for next iteration
            $Current = [int][math]::Floor(($Current - 1) / 26)
        }

        return ($ColumnLetters -join '')
    }
}
#EndRegion '.\Private\Utility\Convert-DecimalToExcelColumn.ps1' 54
#Region '.\Private\Utility\ConvertTo-HumanErrorDescription.ps1' -1

function ConvertTo-HumanErrorDescription {
    <#
    .SYNOPSIS
    Helper function for Entra sign in logs. Accepts an error code number and returns
    a human-readable description string.

    .DESCRIPTION
    Looks up an Entra ID (Azure AD) sign-in error code in the bundled EntraErrorCodes.csv
    data file and returns a formatted string in the form "CODE:Description". The lookup
    table is cached in $Global:IRT_EntraErrorTable after the first call for performance.

    Used internally by Get-IRTEntraSignIn and Get-IRTNonInteractiveSignIn to annotate each log row.

    .PARAMETER ErrorCode
    The integer Entra sign-in error code to look up.

    .EXAMPLE
    ConvertTo-HumanErrorDescription -ErrorCode 50076
    Returns '50076:User was required to use multi-factor authentication.'

    .OUTPUTS
    System.String

    .NOTES
    Version: 1.1.0
    1.1.0 - Converted from doing the whole sheet to just one log at a time
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param (
        [int] $ErrorCode
    )

    process {

        if ($Global:IRT_EntraErrorTable.ContainsKey($ErrorCode)) {
            # get row from table
            $Row = $Global:IRT_EntraErrorTable[$ErrorCode]
            # pick best description, if present
            $Description = if (-not [string]::IsNullOrWhiteSpace($Row.CustomDescription)) {
                $Row.CustomDescription
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Row.ShortDescription)) {
                $Row.ShortDescription
            }
            # if there's a description return code:description string, if not, just the code
            if ($Description) {
                return "${ErrorCode}:${Description}"
            }
            else {
                return "$ErrorCode"
            }
        }
        else {
            return "$ErrorCode"
        }
    }
}
#EndRegion '.\Private\Utility\ConvertTo-HumanErrorDescription.ps1' 59
#Region '.\Private\Utility\Copy-ConditionalFormatting.ps1' -1

function Copy-ConditionalFormatting {
    <#
.SYNOPSIS
    Copies every conditional-formatting rule that touches a source range onto a destination range,
    using the EPPlus object model exposed by the ImportExcel module.

.DESCRIPTION
    For each rule on the source worksheet whose address intersects -SourceRange, the rule is
    recreated on the destination worksheet and the following attributes are copied across:

    Scalar rule properties (when present on the rule type):
      StopIfTrue, Formula, Formula2, Text, Rank, Percent, StdDev

    Value objects - LowValue, MiddleValue, HighValue (colour scales / data bars),
    and Icon1-Icon5 (icon sets) - each contribute:
      Type, Value, Formula, Color

    Constructor-time properties (supplied when creating the new rule object):
      IconSet  (ThreeIconSet / FourIconSet / FiveIconSet rules)
      Color    (DataBar rules)

    DXF style (applied to all rule types via the Style property):
      NumberFormat  : Format
      Font          : Bold, Italic, Strike, Underline, Color
      Fill          : PatternType, BackgroundColor, PatternColor
      Border edges  : Left / Right / Top / Bottom - each: Style, Color

    Geometry is handled Format-Painter style: each rule's address is first clipped to -SourceRange,
    then shifted by the offset between the source range's top-left cell and the destination range's
    top-left cell. The size of -DestinationRange is therefore ignored - only its anchor (top-left)
    matters, so you may pass a full range ("H2:K20") or just the anchor cell ("H2").

    Rules are RECREATED rather than cloned, because EPPlus conditional-formatting rules are
    worksheet-scoped but the styles they reference are workbook-scoped; copying rule objects
    directly between packages produces invalid DxfId references.

.PARAMETER Source
    A file path (string) or an OfficeOpenXml.ExcelPackage object (e.g. from Open-ExcelPackage).
    If a path is given the package is opened here and closed WITHOUT saving when done.

.PARAMETER SourceSheet
    Source worksheet name. Optional when the source workbook has exactly one sheet.

.PARAMETER SourceRange
    A1-style range whose conditional formatting should be copied, e.g. "A2:D100".

.PARAMETER Destination
    The destination OfficeOpenXml.ExcelPackage object (or a file path). If an object is passed it
    is left open and is NOT saved - the caller is responsible for Close-ExcelPackage. If a path is
    passed it is opened here and saved + closed when done.

.PARAMETER DestinationSheet
    Destination worksheet name. Optional when the destination workbook has exactly one sheet.

.PARAMETER DestinationRange
    Destination anchor. Pass a full range or just the top-left cell, e.g. "H2".

.EXAMPLE
    $dst = Open-ExcelPackage -Path .\report.xlsx
    $params = @{
        Source           = '.\template.xlsx'
        SourceRange      = 'A2:D50'
        Destination      = $dst
        DestinationSheet = 'Data'
        DestinationRange = 'A2'
    }
    Copy-ConditionalFormatting @params
    Close-ExcelPackage $dst   # caller saves the destination

.NOTES
    * Relative references inside Expression rule formulas (custom formulas) are copied VERBATIM and
      are NOT re-based to the new location (this mirrors EPPlus, which does not adjust formulas when
      an address changes). Keep source and destination in the same columns/rows, or use absolute ($)
      references, to avoid surprises. A warning is emitted when Expression rules are copied with a
      non-zero offset. Other rule types (text matching, value comparisons, etc.) are unaffected.
    * Colour scales, data bars and icon sets are copied best-effort (value objects + colours).
    * Any rule that cannot be recreated is skipped with a warning; the rest still copy.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Source,
        [Parameter(Mandatory)] [string] $SourceRange,
        [Parameter(Mandatory)] [object] $Destination,
        [Parameter(Mandatory)] [string] $DestinationRange,
        [string] $SourceSheet,
        [string] $DestinationSheet
    )

    # ---------------------------------------------------------------- helpers ----
    function Resolve-Package($in, [string]$role) {
        if ($in -is [string]) {
            if (-not (Test-Path -LiteralPath $in)) { throw "$role file not found: $in" }
            return @{ Package = (Open-ExcelPackage -Path $in); Opened = $true }
        }
        if ($in -isnot [OfficeOpenXml.ExcelPackage]) {
            $msg = "$role must be a file path or an OfficeOpenXml.ExcelPackage; " +
            "got [$($in.GetType().FullName)]."
            throw $msg
        }
        return @{ Package = $in; Opened = $false }
    }

    function Resolve-Sheet($pkg, [string]$name, [string]$role) {
        $wb = $pkg.Workbook
        $names = @($wb.Worksheets | ForEach-Object Name)
        if ($name) {
            $ws = $wb.Worksheets[$name]
            if (-not $ws) {
                throw "$role worksheet '$name' not found. Available: $($names -join ', ')"
            }
            return $ws
        }
        if ($wb.Worksheets.Count -eq 1) { return $wb.Worksheets[1] }
        $msg = "$role workbook has $($wb.Worksheets.Count) sheets; specify the sheet name. " +
        "Available: $($names -join ', ')"
        throw $msg
    }

    # Return list of {FromRow,FromCol,ToRow,ToCol} for single- or multi-area addresses.
    function Get-Area($address) {
        $out = New-Object System.Collections.Generic.List[object]
        $subs = $address.Addresses
        $list = if ($subs) { $subs } else { @($address) }
        foreach ($a in $list) {
            $out.Add([pscustomobject]@{
                    FromRow = $a.Start.Row; FromCol = $a.Start.Column
                    ToRow   = $a.End.Row; ToCol   = $a.End.Column
                })
        }
        return $out
    }

    # Copy one DXF property from $srcContainer to $dstContainer.
    # In EPPlus 5.x, DXF sub-properties (PatternType, Bold, Color, etc.) are
    # ExcelDxfStyleXxx<T> wrapper objects whose property setters are internal.
    # Direct assignment ($dst.Prop = $wrapperObj) therefore fails silently.
    # The correct write path is $dst.Prop.Value = $wrapperObj.Value.
    # For plain nullable values (EPPlus 4.x or non-wrapped props), fall back to
    # direct assignment.
    function Copy-DxfProp($srcContainer, $dstContainer, [string]$prop) {
        $sv = $srcContainer.$prop
        if ($null -eq $sv) { return }
        if ($sv.PSObject.Properties['HasValue']) {
            if ($sv.HasValue) { try { $dstContainer.$prop.Value = $sv.Value } catch {} }
        } else {
            try { $dstContainer.$prop = $sv } catch {}
        }
    }

    function Copy-DxfColor($s, $d) {
        if (-not $s -or -not $d) { return }
        foreach ($p in 'Color', 'Theme', 'Index', 'Tint', 'Auto') {
            Copy-DxfProp -srcContainer $s -dstContainer $d -prop $p
        }
    }

    function Copy-DxfStyle($s, $d) {
        if (-not $s -or -not $d) { return }
        if ($s.NumberFormat -and $s.NumberFormat.Format) {
            try { $d.NumberFormat.Format = $s.NumberFormat.Format } catch {}
        }
        if ($s.Font -and $d.Font) {
            foreach ($p in 'Bold', 'Italic', 'Strike', 'Underline') {
                Copy-DxfProp -srcContainer $s.Font -dstContainer $d.Font -prop $p
            }
            Copy-DxfColor $s.Font.Color $d.Font.Color
        }
        if ($s.Fill -and $d.Fill) {
            Copy-DxfProp -srcContainer $s.Fill -dstContainer $d.Fill -prop 'PatternType'
            Copy-DxfColor $s.Fill.BackgroundColor $d.Fill.BackgroundColor
            Copy-DxfColor $s.Fill.PatternColor    $d.Fill.PatternColor
            # Excel encodes solid-fill CF rules without a patternType attribute, which EPPlus
            # reads back as PatternType=None. Writing a rule with PatternType=None causes EPPlus
            # to omit the fill from XML entirely. Upgrade to Solid when any fill color was copied.
            $hasBg = $null -ne $d.Fill.BackgroundColor.Color
            $hasPat = $null -ne $d.Fill.PatternColor.Color
            if (($hasBg -or $hasPat) -and
                $d.Fill.PatternType -ne [OfficeOpenXml.Style.ExcelFillStyle]::Solid) {
                $d.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            }
        }
        if ($s.Border -and $d.Border) {
            foreach ($edge in 'Left', 'Right', 'Top', 'Bottom') {
                $sb = $s.Border.$edge; $db = $d.Border.$edge
                if ($sb -and $db) {
                    Copy-DxfProp -srcContainer $sb -dstContainer $db -prop 'Style'
                    Copy-DxfColor $sb.Color $db.Color
                }
            }
        }
    }

    # Copy a conditional-format value object (cfvo): used by colour scales, data bars, icon sets.
    function Copy-ValueObject($s, $d) {
        if (-not $s -or -not $d) { return }
        foreach ($p in 'Type', 'Value', 'Formula', 'Color') {
            if ($s.PSObject.Properties[$p] -and $d.PSObject.Properties[$p]) {
                $sv = $s.$p
                if ($null -ne $sv) { try { $d.$p = $sv } catch {} }
            }
        }
    }

    function Copy-Scalar($s, $d) {
        foreach ($p in 'StopIfTrue', 'Formula', 'Formula2', 'Text', 'Rank', 'Percent', 'StdDev') {
            if ($s.PSObject.Properties[$p] -and $d.PSObject.Properties[$p]) {
                $sv = $s.$p
                if ($null -ne $sv) { try { $d.$p = $sv } catch {} }
            }
        }
    }
    # -----------------------------------------------------------------------------

    $srcInfo = $null; $dstInfo = $null
    try {
        $srcInfo = Resolve-Package $Source      'Source'
        $dstInfo = Resolve-Package $Destination 'Destination'

        $srcSheet = Resolve-Sheet -pkg $srcInfo.Package -name $SourceSheet -role 'Source'
        $dstSheet = Resolve-Sheet -pkg $dstInfo.Package -name $DestinationSheet -role 'Destination'

        $srcAddr = [OfficeOpenXml.ExcelAddress]::new($SourceRange)
        $dstAddr = [OfficeOpenXml.ExcelAddress]::new($DestinationRange)

        $sr1 = $srcAddr.Start.Row; $sc1 = $srcAddr.Start.Column
        $sr2 = $srcAddr.End.Row; $sc2 = $srcAddr.End.Column

        $rowOffset = $dstAddr.Start.Row - $sr1
        $colOffset = $dstAddr.Start.Column - $sc1

        $hasOffset = ($rowOffset -ne 0 -or $colOffset -ne 0)
        $hasWarnedAboutFormulas = $false

        $cf = $dstSheet.ConditionalFormatting
        $copied = 0

        # Snapshot source rules first to prevent mutate-while-enumerate on the same sheet.
        foreach ($rule in @($srcSheet.ConditionalFormatting)) {
            if (-not $rule.Address) { continue }

            # Build the destination address: clip each area to the source range, then offset.
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($a in (Get-Area $rule.Address)) {
                $ir1 = [math]::Max($a.FromRow, $sr1); $ic1 = [math]::Max($a.FromCol, $sc1)
                $ir2 = [math]::Min($a.ToRow, $sr2); $ic2 = [math]::Min($a.ToCol, $sc2)
                if ($ir1 -le $ir2 -and $ic1 -le $ic2) {
                    $parts.Add([OfficeOpenXml.ExcelCellBase]::GetAddress(
                            ($ir1 + $rowOffset), ($ic1 + $colOffset),
                            ($ir2 + $rowOffset), ($ic2 + $colOffset)))
                }
            }
            if ($parts.Count -eq 0) { continue }   # rule does not touch the source range

            $newAddrString = $parts -join ' '
            $typeName = $rule.Type.ToString()

            # Only warn about formula offset issues for Expression rules (custom formulas).
            # Other types like ContainsText, BeginsWith, etc., use auto-generated formulas
            # that reference the cell being evaluated, so offsets don't affect them.
            if ($hasOffset -and -not $hasWarnedAboutFormulas -and $typeName -eq 'Expression') {
                $Offset = "rows: $rowOffset, cols: $colOffset"
                $WarnMsg = "Copy-ConditionalFormatting: Applying offset ($Offset). " +
                'Relative references inside Expression rule formulas are copied ' +
                'as-is and will NOT be re-based.'
                Write-Warning $WarnMsg
                $hasWarnedAboutFormulas = $true
            }

            try {
                $addr = [OfficeOpenXml.ExcelAddress]::new($newAddrString)
                $addName = "Add$typeName"

                # Most types take just the address. Icon sets need the icon-set type; the data bar
                # needs a colour (and its method is 'AddDatabar', not 'AddDataBar').
                $newRule =
                if ($typeName -in 'ThreeIconSet', 'FourIconSet', 'FiveIconSet') {
                    $cf.$addName($addr, $rule.IconSet)
                }
                elseif ($typeName -eq 'DataBar') {
                    $cf.AddDatabar($addr, $rule.Color)
                }
                else {
                    $cf.$addName($addr)
                }

                Copy-Scalar $rule $newRule

                foreach ($vo in 'LowValue', 'MiddleValue', 'HighValue') {
                    if ($rule.PSObject.Properties[$vo] -and $newRule.PSObject.Properties[$vo]) {
                        Copy-ValueObject $rule.$vo $newRule.$vo
                    }
                }
                foreach ($ic in 'Icon1', 'Icon2', 'Icon3', 'Icon4', 'Icon5') {
                    if ($rule.PSObject.Properties[$ic] -and $newRule.PSObject.Properties[$ic]) {
                        Copy-ValueObject $rule.$ic $newRule.$ic
                    }
                }
                foreach ($p in 'Reverse', 'ShowValue') {
                    if ($rule.PSObject.Properties[$p] -and $newRule.PSObject.Properties[$p]) {
                        $sv = $rule.$p
                        if ($null -ne $sv) { try { $newRule.$p = $sv } catch {} }
                    }
                }

                if ($rule.PSObject.Properties['Style'] -and
                    $newRule.PSObject.Properties['Style'] -and $rule.Style) {
                    Copy-DxfStyle $rule.Style $newRule.Style
                }

                $copied++
                Write-Verbose "Copied '$typeName' rule -> $newAddrString"
            }
            catch {
                $warnMsg = ("Skipped rule (type '{0}', source '{1}'): {2}" -f
                    $typeName, $rule.Address.Address, $_.Exception.Message)
                Write-Warning $warnMsg
            }
        }

        Write-Verbose "Copied $copied conditional-formatting rule(s) to $($dstSheet.Name)."
    }
    finally {
        # Close only packages we opened: source is discarded; a path-based destination is saved.
        if ($srcInfo -and $srcInfo.Opened) {
            Close-ExcelPackage -ExcelPackage $srcInfo.Package -NoSave
        }
        if ($dstInfo -and $dstInfo.Opened) {
            Close-ExcelPackage -ExcelPackage $dstInfo.Package
        }
    }
}
#EndRegion '.\Private\Utility\Copy-ConditionalFormatting.ps1' 332
#Region '.\Private\Utility\Format-PhoneNumber.ps1' -1

function Format-PhoneNumber {
    <#
    .SYNOPSIS
    Formats a phone number for Excel compatibility by removing the leading '+'.

    .DESCRIPTION
    Converts Graph API phone number format (+1 1234567890) to an Excel-safe format.
    US/CA numbers (+1): 123-456-7890
    Other country codes: 44 123-456-7890

    .EXAMPLE
    Format-PhoneNumber '+1 1234567890'
    123-456-7890

    .EXAMPLE
    Format-PhoneNumber '+44 1234567890'
    44 123-456-7890

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter( Mandatory, Position = 0, ValueFromPipeline )]
        [string] $PhoneNumber
    )

    process {
        if ( $PhoneNumber -match '^\+(\d+)\s+(\d{3})(\d{3})(\d{4})$' ) {
            if ( $Matches[1] -eq '1' ) {
                # US/CA: 123-456-7890
                return "$($Matches[2])-$($Matches[3])-$($Matches[4])"
            }
            else {
                # other country codes: 44 123-456-7890
                return "$($Matches[1]) $($Matches[2])-$($Matches[3])-$($Matches[4])"
            }
        }

        return $PhoneNumber
    }
}
#EndRegion '.\Private\Utility\Format-PhoneNumber.ps1' 44
#Region '.\Private\Utility\Get-DefaultDomain.ps1' -1

function Get-DefaultDomain {
    <#
    .SYNOPSIS
    Returns the tenant's default verified domain, with lazy caching on the session variable.

    .DESCRIPTION
    Queries Microsoft Graph for the tenant's default verified domain (IsDefault -eq $true),
    caches both the full domain object and the second-level domain (SLD) label on
    $Global:IRT_Session, and returns whichever form was requested.

    On the first call the function makes one Graph API request (Get-MgDomain). Every
    subsequent call within the same session is served from the in-memory cache with no
    network traffic. The cache is invalidated automatically when Disconnect-IRT clears
    $Global:IRT_Session.

    The second-level domain (SLD) is the label immediately to the left of the top-level
    domain (TLD): for "contoso.com" the SLD is "contoso". This label is used throughout
    the module as a short tenant identifier in exported file names.

    .PARAMETER Domain
    Return the full Microsoft Graph domain object
    (Microsoft.Graph.PowerShell.Models.MicrosoftGraphDomain) for the default domain.

    .PARAMETER SecondLevelDomain
    Return only the second-level domain label extracted from the default domain's Id
    property (e.g. "contoso" from "contoso.com"). This is the default output when
    neither switch is specified.

    .OUTPUTS
    [string] when -SecondLevelDomain or no parameter is supplied.
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphDomain] when -Domain is supplied.

    .EXAMPLE
    Get-DefaultDomain

    Returns the SLD label for the current tenant's default domain, e.g. "contoso".
    Equivalent to passing -SecondLevelDomain explicitly.

    .EXAMPLE
    Get-DefaultDomain -SecondLevelDomain

    Same as the default. Useful when you want to be explicit in a script.

    .EXAMPLE
    Get-DefaultDomain -Domain

    Returns the full Graph domain object, including Id, IsDefault, IsVerified, etc.

    .EXAMPLE
    $FileNameDate = (Get-Date).ToString('yy-MM-dd_HH-mm')
    $FileName = "Users_Raw_$(Get-DefaultDomain)_${FileNameDate}.xml"

    Typical use: build a tenant-scoped export file name.

    .NOTES
    Requires an active Microsoft Graph connection established via Connect-IRT or
    Connect-IRTGraph.

    The function writes a Verbose message only on a cache miss (i.e. when an actual
    Graph API call is made). There is no Verbose output on a cache hit.

    Property names stored on $Global:IRT_Session:
        DefaultDomain     - the full Graph domain object
        DefaultDomainName - the SLD string
    #>
    [OutputType([string], ParameterSetName = 'SecondLevelDomain')]
    [OutputType([object], ParameterSetName = 'Domain')]
    [CmdletBinding(DefaultParameterSetName = 'SecondLevelDomain')]
    param (
        [Parameter(ParameterSetName = 'Domain')]
        [switch] $Domain,

        [Parameter(ParameterSetName = 'SecondLevelDomain')]
        [switch] $SecondLevelDomain
    )

    process {

        # serve from cache when available
        if ($Global:IRT_Session -and $Global:IRT_Session.PSObject.Properties['DefaultDomain']) {
            if ($Domain) { return $Global:IRT_Session.DefaultDomain }
            if ($SecondLevelDomain) { return $Global:IRT_Session.DefaultDomainName }
            return $Global:IRT_Session.DefaultDomainName
        }

        # cache miss -- fetch from Graph
        $FunctionName = $MyInvocation.MyCommand.Name
        Write-Verbose "${FunctionName}: Get-MgDomain (cache miss)"
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DefaultDomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        if ($Global:IRT_Session) {
            $AmParams = @{ Force = $true }
            $AmParams.NotePropertyName = 'DefaultDomain'
            $AmParams.NotePropertyValue = $DefaultDomain
            $Global:IRT_Session | Add-Member @AmParams
            $AmParams.NotePropertyName = 'DefaultDomainName'
            $AmParams.NotePropertyValue = $DefaultDomainName
            $Global:IRT_Session | Add-Member @AmParams
        }

        if ($Domain) { return $DefaultDomain }
        if ($SecondLevelDomain) { return $DefaultDomainName }
        return $DefaultDomainName
    }
}
#EndRegion '.\Private\Utility\Get-DefaultDomain.ps1' 107
#Region '.\Private\Utility\Get-GlobalUserObject.ps1' -1

function Get-GlobalUserObject {
    <#
    .SYNOPSIS
    Gets user objects from global variables. Designed to be used by other scripts.

    .DESCRIPTION
    Returns the de-duplicated, DisplayName-sorted list of Entra ID user objects currently
    stored in $Global:IRT_UserObjects. This is the standard way IRT functions resolve users
    when no -UserObject parameter is supplied directly.

    .EXAMPLE
    $Users = Get-GlobalUserObject
    Returns all user objects currently in the global session.

    .OUTPUTS
    System.Collections.Generic.List[PSObject]

    .NOTES
    Version: 1.0.3
    #>
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
    }

    process {

        # add userobjects
        if ( $Global:IRT_UserObjects ) {
            $IterationList = @( $Global:IRT_UserObjects )
            foreach ( $i in $IterationList ) {
                $ScriptUserObjects.Add( $i )
            }
        }

        # return user objects
        return $ScriptUserObjects | Sort-Object Id -Unique | Sort-Object DisplayName
    }
}
#EndRegion '.\Private\Utility\Get-GlobalUserObject.ps1' 45
#Region '.\Private\Utility\Get-RandomPassword.ps1' -1

function Get-RandomPassword {
    <#
    .SYNOPSIS
    Generates passwords of random characters. Guarantees at least one character
    of each type so password will meet complexity requirements.

    Usage:
    Get-RandomPassword 10
    Get-RandomPassword -Length 14

    .NOTES
    Version 0.02
    #>
    param (
        [ValidateRange(4, [int]::MaxValue)]
        [int] $Length = 15
    )

    $upperChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lowerChars = 'abcdefghjkmnpqrstuvwxyz'.ToCharArray()
    $numberChars = '23456789'.ToCharArray()
    $symbolChars = '!#$%&*/?@[]^~+<=>'.ToCharArray()

    # Ensure at least one character from each category
    $upper = $upperChars | Get-Random
    $lower = $lowerChars | Get-Random
    $number = $numberChars | Get-Random
    $symbol = $symbolChars | Get-Random
    $result = @($upper, $lower, $number, $symbol)

    # Calculate the remaining length for random characters
    # Use a separate variable so [ValidateRange] on $Length is not re-evaluated
    $remaining = $Length - 4

    # Define the character set for the remaining random characters
    $charSet = $upperChars + $lowerChars + $numberChars + $symbolChars

    # Create an instance of the random number generator
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider

    # generate more characters to fill array
    $bytes = New-Object byte[]($remaining)
    $rng.GetBytes($bytes)
    for ( $i = 0; $i -lt $remaining; $i++ ) {
        $result += $charSet[$bytes[$i] % $charSet.Length]
    }

    $result = $result | Get-Random -Count $result.Count

    return ( -join $result )
}
#EndRegion '.\Private\Utility\Get-RandomPassword.ps1' 52
#Region '.\Private\Utility\Import-ReferenceData.ps1' -1

function Import-ReferenceData {
    <#
    .SYNOPSIS
    Loads static reference data files into module global variables.

    .DESCRIPTION
    Reads the three bundled data files into globals used by sign-in log, unified audit log,
    and other functions. Called automatically at module import.

    Call this manually after editing any of the data files to pick up changes without
    reloading the entire module.

    Globals populated:
      $Global:IRT_EntraErrorTable   - Hashtable[int -> row] from EntraErrorCodes.csv
      $Global:IRT_UalOperationsData - Array of rows from UALAllOperations.xlsx
      $Global:IRT_UalUserTypeTable  - Hashtable[int -> 'UserType member name']
        from UALUserType.csv
      $Global:IRT_TenantInfoTable   - Hashtable[TenantId -> row]
        from APPDATA\<ModuleName>\TenantOwnerInfo.csv

    The AllOperations path can be overridden by setting AllOperationsSheetPath in config.json.

    .EXAMPLE
    Import-ReferenceData
    Re-reads all reference data files. Use after editing EntraErrorCodes.csv, the AllOperations
    workbook, UALUserType.csv, or TenantOwnerInfo.csv.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase

    # Entra ID sign-in error codes (int-keyed synchronized hashtable for runspace safety)
    $EntraErrorPath = Join-Path -Path $ModuleRoot -ChildPath 'Data\EntraErrorCodes.csv'
    $EntraTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $EntraErrorPath)) {
        $EntraTable[[int]$Row.Error] = $Row
    }
    $Global:IRT_EntraErrorTable = $EntraTable

    # UAL operation risk metadata (xlsx, path configurable via IRT_Config.AllOperationsSheetPath)
    $AllOperationsPath = $Global:IRT_Config.AllOperationsSheetPath
    if (-not $AllOperationsPath) {
        $AopsJoin = @{
            Path      = $ModuleRoot
            ChildPath = 'Data\UALAllOperations.xlsx'
        }
        $AllOperationsPath = Join-Path @AopsJoin
        $Global:IRT_Config.AllOperationsSheetPath = $AllOperationsPath
    }
    if (Test-Path -LiteralPath $AllOperationsPath) {
        $IeParams = @{
            Path          = $AllOperationsPath
            WorksheetName = 'Operations'
        }
        $Global:IRT_UalOperationsData = @(Import-Excel @IeParams)
    } else {
        $Global:IRT_UalOperationsData = @()
        Write-Warning ('Import-ReferenceData: AllOperations sheet not found at: ' +
            $AllOperationsPath)
    }

    # UAL user type lookup
    $UserTypePath = Join-Path -Path $ModuleRoot -ChildPath 'Data\UALUserType.csv'
    $UserTypeTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $UserTypePath)) {
        $UserTypeTable[[int]$Row.Value] = $Row.'UserType member name'
    }
    $Global:IRT_UalUserTypeTable = $UserTypeTable

    # Tenant owner info cache (keyed by TenantId GUID string)
    $ModuleName = $MyInvocation.MyCommand.ModuleName
    $TcJoin = @{
        Path                = $env:APPDATA
        ChildPath           = $ModuleName
        AdditionalChildPath = 'TenantOwnerInfo.csv'
    }
    $TenantCachePath = Join-Path @TcJoin
    $TenantTable = [hashtable]::Synchronized(@{})
    if (Test-Path -LiteralPath $TenantCachePath) {
        foreach ($Row in (Import-Csv -Path $TenantCachePath)) {
            $TenantTable[$Row.TenantId] = $Row
        }
    }
    $Global:IRT_TenantInfoTable = $TenantTable
}
#EndRegion '.\Private\Utility\Import-ReferenceData.ps1' 90
#Region '.\Private\Utility\Write-IRT.ps1' -1

function Write-IRT {
    <#
    .SYNOPSIS
    Writes a colored, prefixed status message to the host.

    .DESCRIPTION
    Central output helper for IRT. Reads foreground colors from $Global:IRT_Config
    (InfoColor, WarnColor, ErrorColor) with hardcoded fallbacks so it works even
    before the config is loaded (e.g. in onprem_ad functions pasted to a remote
    machine).

    The calling function's name is detected automatically from the call stack and
    prepended to the message. Override it with -FunctionName when a parent function
    wants its name to appear on output from a child helper it calls.

    .PARAMETER Message
    The message text to display.

    .PARAMETER Level
    Output level: Info (default), Warn, or Error.

    .PARAMETER FunctionName
    Override the auto-detected caller name. Useful when a parent passes its own
    name down to a child helper: Request-GraphUser -FunctionName $MyInvocation.MyCommand.Name

    .PARAMETER NoNewline
    Passes -NoNewline through to Write-Host.

    .PARAMETER NoColor
    Suppresses color output. Useful when writing to a transcript or redirected
    stream that does not support ANSI color codes.

    .PARAMETER NoFunctionName
    Suppresses the calling function name prefix. Useful for plain status messages
    that do not need attribution.

    .EXAMPLE
    Write-IRT "Retrieving sign-in logs for $($User.DisplayName)."
    Writes an Info-level message with the calling function's name prepended.

    .EXAMPLE
    Write-IRT "No records found." -Level Warn
    Writes a yellow warning message.

    .OUTPUTS
    None. Output is written directly to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Message = '',

        [ValidateSet('Info', 'Warn', 'Error')]
        [string] $Level = 'Info',

        [string] $FunctionName = '',
        [switch] $NoNewline,
        [switch] $NoColor,
        [switch] $NoFunctionName
    )

    if (-not $FunctionName) {
        $FunctionName = (
            Get-PSCallStack |
                Select-Object -Skip 1 |
                Where-Object { $_.Command -notlike '<*>' } |
                Select-Object -First 1
        ).Command
        if (-not $FunctionName) { $FunctionName = '<unknown>' }
    }

    $color = switch ($Level) {
        'Info' {
            if ($Global:IRT_Config?.InfoColor) {
                $Global:IRT_Config.InfoColor
            } else {
                'DarkCyan'
            }
        }
        'Warn' {
            if ($Global:IRT_Config?.WarnColor) {
                $Global:IRT_Config.WarnColor
            } else {
                'Yellow'
            }
        }
        'Error' {
            if ($Global:IRT_Config?.ErrorColor) {
                $Global:IRT_Config.ErrorColor
            } else {
                'Red'
            }
        }
    }

    $text = if ($Message -eq '') {
        ''
    } elseif ($NoFunctionName) {
        $Message
    } else {
        "${FunctionName}: ${Message}"
    }
    if ($NoColor) {
        Write-Host $text -NoNewline:$NoNewline
    } else {
        Write-Host $text -ForegroundColor $color -NoNewline:$NoNewline
    }
}
#EndRegion '.\Private\Utility\Write-IRT.ps1' 113
#Region '.\Public\Connect\Clear-IRTTokenCache.ps1' -1

function Clear-IRTTokenCache {
    <#
    .SYNOPSIS
    Removes the persistent IRT MSAL token cache and signs out all in-process accounts.

    .DESCRIPTION
    When the persistent token cache is enabled (config: EnableTokenCache),
    MSAL writes refresh tokens to disk so the user is not re-prompted in every
    new PowerShell session. This command:

      1. Removes every account from any PublicClientApplication currently held
         in $Global:IRT_Session (Graph, Exchange, IPPS). Removal also strips
         their tokens from the on-disk cache via the registered cache helper.
      2. Deletes the on-disk cache file as a belt-and-suspenders measure in
         case no MSAL app is currently registered against it.

    Use this after a credential rotation, when sharing a workstation, or to
    force the next Connect-IRT to prompt interactively.

    .EXAMPLE
    Clear-IRTTokenCache
    Wipes the cache. The next Connect-IRT call will require interactive sign-in.

    .OUTPUTS
    None.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ClearIRTTokenCache')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Sign out in-process accounts first. This invokes the cache helper's
    # write callback and removes the entries from the file cleanly.
    if ($Global:IRT_Session) {
        foreach ($svc in 'Graph', 'Exchange', 'IPPS') {
            $App = $Global:IRT_Session.$svc.PublicClientApplication
            if (-not $App) { continue }
            try {
                $Accounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
                foreach ($acct in $Accounts) {
                    $null = $App.RemoveAsync($acct).GetAwaiter().GetResult()
                }
            }
            catch {
                Write-IRT "Failed to remove $svc MSAL accounts: $_" -Level Warn
            }
        }
    }

    # Belt-and-suspenders: delete the cache file directly if it survived.
    $CachePath = $Global:IRT_Config.MsalCachePath
    if (Test-Path $CachePath) {
        if ($PSCmdlet.ShouldProcess($CachePath, 'Delete MSAL token cache file')) {
            Remove-Item -Path $CachePath -Force -ErrorAction SilentlyContinue
            Write-IRT "Deleted token cache file at $CachePath."
        }
    }
    else {
        Write-IRT 'No token cache file found.'
    }
}
#EndRegion '.\Public\Connect\Clear-IRTTokenCache.ps1' 64
#Region '.\Public\Connect\Connect-IRT.ps1' -1

function Connect-IRT {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph and Exchange Online for incident response.

    .DESCRIPTION
    Orchestrates connections to Graph and Exchange Online.
    When no service switches are specified, both services are connected. Use -Graph
    or -Exchange to connect to specific services only.

    The cloud environment is identified automatically via an unauthenticated OIDC
    discovery lookup. Pass -Cloud to skip the lookup and connect directly
    to a known cloud.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, China.
    When omitted the cloud is detected automatically via OIDC discovery. Provide
    this parameter to skip the lookup or to override the detected value.

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER Browser
    Browser to use for URL opening. Valid values: msedge, chrome, firefox,
    brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .PARAMETER Refresh
    Re-connects all services that are present in the current session using the
    stored TenantId and cloud environment. Reads parameters from
    $Global:IRT_Session instead of requiring them on the command line.
    Combine with -Silent to suppress interactive auth fallback.

    .PARAMETER Silent
    When set, token acquisition skips the interactive browser/device-code
    fallback. If MSAL cannot silently refresh a token, the function throws
    instead of prompting. Intended for use in the prompt function and other
    non-interactive callers.

    .PARAMETER ClientId
    Override the MSAL client ID used for all three services (Graph, Exchange,
    IPPS). When omitted, each service uses its own first-party Microsoft client
    ID. Use this when connecting via a custom app registration that has been
    granted the necessary delegated permissions.

    .EXAMPLE
    Connect-IRT -TenantId $tid
    Connects to Graph and Exchange Online.

    .EXAMPLE
    Connect-IRT -TenantId $tid -Exchange -Cloud USGov
    Connects to Exchange in a USGov cloud, skipping OIDC discovery.

    .EXAMPLE
    Connect-IRT -Refresh
    Silently re-acquires tokens for all services in the existing session.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('ConnectIRT')]
    [CmdletBinding(DefaultParameterSetName = 'TenantId')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'TenantId')]
        [string] $TenantId,

        [Parameter(Mandatory, ParameterSetName = 'Refresh')]
        [switch] $Refresh,

        [switch] $Silent,

        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,
        [Alias('AdditionalScopes')]
        [string[]] $AdditionalScope,

        [switch] $Graph,
        [switch] $Exchange,
        [switch] $IPPS,

        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string] $Browser = $Global:IRT_Config.Browser ?? 'default',
        [switch] $Private,

        [switch] $Force,

        [string] $ClientId
    )

    process {

        # -Refresh: read params from the existing session and recurse.
        if ($Refresh) {
            if (-not $Global:IRT_Session) {
                Write-Error 'No active IRT session to refresh. Run Connect-IRT -TenantId first.'
                return
            }
            $RefreshParams = @{
                TenantId = $Global:IRT_Session.TenantId
                Cloud    = $Global:IRT_Session.Environment
                Force    = $true
            }
            if ($Silent) { $RefreshParams['Silent'] = $true }
            if ($Global:IRT_Session.ClientId) {
                $RefreshParams['ClientId'] = $Global:IRT_Session.ClientId
            }
            if ($Global:IRT_Session.Graph) { $RefreshParams['Graph'] = $true }
            if ($Global:IRT_Session.Exchange) { $RefreshParams['Exchange'] = $true }
            if ($Global:IRT_Session.IPPS) { $RefreshParams['IPPS'] = $true }
            if (-not ($RefreshParams.ContainsKey('Graph') -or
                    $RefreshParams.ContainsKey('Exchange') -or
                    $RefreshParams.ContainsKey('IPPS'))) {
                Write-Error 'IRT session exists but no service connections are recorded.'
                return
            }
            Connect-IRT @RefreshParams
            return
        }

        # if no service switches specified, connect to all
        $ConnectAll = -not ($Graph -or $Exchange -or $IPPS)
        $ConnectGraph = $ConnectAll -or $Graph
        $ConnectExchange = $ConnectAll -or $Exchange
        $ConnectIPPS = $ConnectAll -or $IPPS

        # --- Resolve cloud ---
        # Use the OIDC lookup when -Cloud is not specified.
        $DetectedEnvironment = $Cloud
        if (-not $Cloud) {
            $Oidc = Get-IRTTenantOidc -TenantId $TenantId
            if ($Oidc) {
                $DetectedEnvironment = $Oidc.Cloud
            } else {
                $DetectedEnvironment = 'Commercial'
                $Msg = 'OIDC discovery did not find the tenant cloud; ' +
                'defaulting to "-Cloud Commercial".'
                Write-IRT $Msg -Level Warn
            }
        }

        # --- Initialize session global before attempting connections ---
        if ($Global:IRT_Session -and $Global:IRT_Session.TenantId -ne $TenantId) {
            $OldTenant = $Global:IRT_Session.TenantId
            Write-Warning "TenantId mismatch (current: $OldTenant). Disconnecting existing session."
            Disconnect-IRT
        }

        if (-not $Global:IRT_Session) {
            $Global:IRT_Session = [pscustomobject]@{
                TenantId    = $TenantId
                Environment = $DetectedEnvironment
                ClientId    = $ClientId
                Graph       = $null
                Exchange    = $null
                IPPS        = $null
            }
        }

        # --- Graph ---
        if ($ConnectGraph) {

            $GraphParams = @{
                TenantId = $TenantId
            }
            $GraphParams['Cloud'] = $DetectedEnvironment
            if ($Force) { $GraphParams['Force'] = $true }
            $GraphParams['Browser'] = $Browser
            if ($Private) { $GraphParams['Private'] = $true }
            if ($AdditionalScope) {
                $GraphParams['AdditionalScope'] = $AdditionalScope
            }
            if ($Silent) { $GraphParams['Silent'] = $true }
            if ($ClientId) { $GraphParams['ClientId'] = $ClientId }

            $GraphConnection = Connect-IRTGraph @GraphParams
            if ($GraphConnection) { $Global:IRT_Session.Graph = $GraphConnection }
        }

        # --- Exchange Online ---
        if ($ConnectExchange) {

            $ExchangeParams = @{
                TenantId          = $TenantId
            }
            $ExchangeParams['Cloud'] = $DetectedEnvironment
            if ($Force) { $ExchangeParams['Force'] = $true }
            $ExchangeParams['Browser'] = $Browser
            if ($Private) { $ExchangeParams['Private'] = $true }
            if ($Silent) { $ExchangeParams['Silent'] = $true }
            if ($ClientId) { $ExchangeParams['ClientId'] = $ClientId }

            $ExchangeConnection = Connect-IRTExchange @ExchangeParams
            if ($ExchangeConnection) { $Global:IRT_Session.Exchange = $ExchangeConnection }
        }

        # --- IPPS ---
        if ($ConnectIPPS) {
            $IPPSParams = @{ TenantId = $TenantId }
            $IPPSParams['Cloud'] = $DetectedEnvironment
            if ($Force) { $IPPSParams['Force'] = $true }
            $IPPSParams['Browser'] = $Browser
            if ($Private) { $IPPSParams['Private'] = $true }
            if ($Silent) { $IPPSParams['Silent'] = $true }
            if ($ClientId) { $IPPSParams['ClientId'] = $ClientId }

            $IPPSConnection = Connect-IRTIPPS @IPPSParams
            if ($IPPSConnection) { $Global:IRT_Session.IPPS = $IPPSConnection }
        }

        # display status if at least one connection succeeded
        if ($Global:IRT_Session.Graph -or
            $Global:IRT_Session.Exchange -or
            $Global:IRT_Session.IPPS
        ) {
            Test-IRTConnection
            $DomainName = if ($Global:IRT_Session.Graph) {
                try { Get-DefaultDomain -ErrorAction Stop } catch { $null }
            } else {
                $null
            }
            Set-TerminalTitle $(if ($DomainName) { "[IRT] $DomainName" } else { '[IRT]' })
        }
    }
}
#EndRegion '.\Public\Connect\Connect-IRT.ps1' 236
#Region '.\Public\Connect\Connect-IRTTenant.ps1' -1

function Connect-IRTTenant {
    <#
    .SYNOPSIS
    Connects to a tenant using a friendly alias looked up from a tenant configuration worksheet.

    .DESCRIPTION
    Reads tenant information from a worksheet and matches the provided alias against
    each tenant's Aliases regex pattern. Once matched, it passes the tenant's parameters
    to Connect-IRT and opens any configured URLs in the browser.

    If multiple tenants match the alias, a numbered menu is presented so the user can
    select which tenant to connect to. This allows the same alias patterns to be shared
    across multiple tenants belonging to the same client.

    The tenants worksheet should be stored at $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.
    A template file (TenantsTemplate.xlsx) is included in the Data folder for reference.

    .PARAMETER Alias
    A string to match against tenant alias patterns. Matched as a regex against the
    Aliases column in the tenants worksheet.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Browser
    Browser to use for URL opening. Valid values: msedge, chrome,
    firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .EXAMPLE
    Connect-IRTTenant contoso
    Looks up 'contoso' in the tenants worksheet and connects to all services.

    .EXAMPLE
    Connect-IRTTenant fab -Graph
    Looks up 'fab' in the tenants worksheet and connects to Graph only.

    .EXAMPLE
    irttenant bestcompany
    Uses the alias to connect to the matching tenant.

    .NOTES
    Version: 1.2.0
    1.2.0 - Multiple-match now prompts user with a selection menu instead of throwing.
    1.1.0 - Updated to use xlsx file instead of csv.
    #>
    [Alias('IRTTenant')]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword', 'PasswordBrowser')]

    param (
        [Parameter( Mandatory, Position = 0 )]
        [string] $Alias,

        [string] $TenantFile,

        [switch] $Graph,
        [switch] $Exchange,

        [Alias('AdditionalScopes', 'Scopes', 'Scope')]
        [string[]] $AdditionalScope,

        [string] $PasswordBrowser = $IRT_Config.PasswordBrowser,

        [switch] $Private
    )

    begin {
        if (-not $TenantFile) {
            $TenantFile = $Global:IRT_Config.TenantsSheetPath
        }
    }

    process {


        # validate tenant file exists
        if (-not ( Test-Path $TenantFile )) {
            Write-Error ("Tenant file not found: ${TenantFile}`n" +
                "Run Open-IRTTenantSheet to create it and edit with your tenant information.")
            return
        }

        # import and search for matching tenant
        $Tenants = Import-Excel -Path $TenantFile
        $MatchedTenants = @()

        foreach ($Tenant in $Tenants) {

            if ($Alias -match "^($($Tenant.Aliases))$") {
                $MatchedTenants += $Tenant
            }
        }
        if ($MatchedTenants.Count -eq 0) {

            $AvailableNames = ($Tenants | ForEach-Object { $_.TenantName }) -join ', '
            Write-Error "No tenant matched alias '${Alias}'. Available tenants: ${AvailableNames}"
            return
        }
        if ($MatchedTenants.Count -gt 1) {
            $TenantNames = $MatchedTenants | ForEach-Object { $_.TenantName }
            $MenuParams = @{
                Option = $TenantNames
                Title  = "Multiple tenants matched '${Alias}'. Select a tenant:"
                List   = $true
            }
            $SelectedName = Build-Menu @MenuParams
            $MatchedTenant = $MatchedTenants | Where-Object { $_.TenantName -eq $SelectedName }
        }
        else {
            $MatchedTenant = $MatchedTenants[0]
        }

        Write-IRT "Matched tenant: $($MatchedTenant.TenantName)"

        # build connection parameters
        $ConnectParams = @{
            TenantId = $MatchedTenant.TenantId
        }

        if ($Graph) { $ConnectParams['Graph'] = $true }
        if ($Exchange) { $ConnectParams['Exchange'] = $true }

        if ($AdditionalScope) {
            $ConnectParams['AdditionalScope'] = $AdditionalScope
        }

        if ($Private) { $ConnectParams['Private'] = $true }

        # open configured URLs
        if ($MatchedTenant.PasswordURLs) {
            $URLs = $MatchedTenant.PasswordURLs -split ';'
            foreach ($URL in $URLs) {
                $URL = $URL.Trim()
                if ($URL) {
                    Open-Browser -Browser $PasswordBrowser -Url $URL -Private:$Private
                }
            }
        }

        # connect
        Connect-IRT @ConnectParams
    }
}
#EndRegion '.\Public\Connect\Connect-IRTTenant.ps1' 157
#Region '.\Public\Connect\Disconnect-IRT.ps1' -1

function Disconnect-IRT {
    <#
    .SYNOPSIS
    Disconnects from Microsoft Graph and Exchange Online and cleans up session state.

    .DESCRIPTION
    Disconnects from Graph and Exchange Online, clears all auth-related global variables,
    and restores the original PowerShell prompt.

    .PARAMETER Graph
    Disconnect from Microsoft Graph only.

    .PARAMETER Exchange
    Disconnect from Exchange Online only.

    .PARAMETER IPPS
    Disconnect from Security & Compliance PowerShell (IPPS) only.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('IRTDisconnect', 'DisconnectIRT')]
    [CmdletBinding()]
    param (
        [switch] $Graph,
        [switch] $Exchange,
        [switch] $IPPS
    )

    process {

        # if no service switches specified, disconnect from all
        $DisconnectAll = -not ($Graph -or $Exchange -or $IPPS)

        $DisconnectGraph = $DisconnectAll -or $Graph
        $DisconnectExchange = $DisconnectAll -or $Exchange
        $DisconnectIPPS = $DisconnectAll -or $IPPS

        # --- Graph ---
        if ($DisconnectGraph) {
            $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
            if ($GraphCtx) {
                $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
                Write-IRT 'Disconnected from Microsoft Graph.' -Level Warn
            }
        }

        # --- Exchange ---
        # Disconnect-ExchangeOnline -ConnectionId allows targeting one session
        # without taking down sibling EXO/IPPS sessions.
        $IppsPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'
        if ($DisconnectExchange) {
            $ExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -notmatch $IppsPattern
                }
            foreach ($Conn in $ExoConns) {
                $ExoDisconParams = @{
                    ConnectionId = $Conn.ConnectionId
                    Confirm      = $false
                    ErrorAction  = 'SilentlyContinue'
                }
                Disconnect-ExchangeOnline @ExoDisconParams
            }
            if ($ExoConns) {
                Write-IRT 'Disconnected from Exchange Online.' -Level Warn
            }
        }

        # --- IPPS ---
        if ($DisconnectIPPS) {
            $IppsConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -match $IppsPattern
                }
            foreach ($Conn in $IppsConns) {
                $IppsDisconParams = @{
                    ConnectionId = $Conn.ConnectionId
                    Confirm      = $false
                    ErrorAction  = 'SilentlyContinue'
                }
                Disconnect-ExchangeOnline @IppsDisconParams
            }
            if ($IppsConns) {
                Write-IRT 'Disconnected from IPPS (Security & Compliance).' -Level Warn
            }
        }

        # --- Clear session globals ---
        # Only when all services are now disconnected.
        $GraphStillConnected = [bool](Get-MgContext -ErrorAction SilentlyContinue)
        $ExoOrIppsStillConnected = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Connected' })

        if (-not $GraphStillConnected -and -not $ExoOrIppsStillConnected) {
            # Preserve IRT_OriginalPrompt - needed by the module's OnRemove handler to
            # restore the original prompt when Remove-Module is called.
            Get-Variable -Scope Global -Name 'IRT_*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'IRT_OriginalPrompt' } |
                Remove-Variable -Scope Global -ErrorAction SilentlyContinue
        }
    }
}
#EndRegion '.\Public\Connect\Disconnect-IRT.ps1' 106
#Region '.\Public\Connect\Get-IRTTenantOidc.ps1' -1

function Get-IRTTenantOidc {
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
    Get-IRTTenantOidc -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

    .EXAMPLE
    $oidc = Get-IRTTenantOidc -TenantId $tid
    Write-Host "Environment: $( $oidc.Environment ) | Graph: $( $oidc.msgraph_host )"

    .OUTPUTS
    PSCustomObject (augmented OIDC discovery document), or $null if not found.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Alias('Domain')]
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
#EndRegion '.\Public\Connect\Get-IRTTenantOidc.ps1' 93
#Region '.\Public\Connect\Open-IRTTab.ps1' -1

function Open-IRTTab {
    <#
    .SYNOPSIS
    Opens a new Windows Terminal tab and loads the module.

    .DESCRIPTION
    Opens a new tab in the current Windows Terminal window and imports
    M365IncidentResponseTools. If an active IRT session exists, also calls
    Connect-IRT to connect to the same tenant.

    Must be run from within Windows Terminal; detected via the WT_SESSION
    environment variable set by Windows Terminal in every hosted session.

    .PARAMETER Title
    Title for the new terminal tab. Defaults to '[IRT]'.

    .PARAMETER Quiet
    When set, silently returns without error if the current console is not
    Windows Terminal. Useful when calling from a profile or script that may
    run in multiple console hosts.

    .EXAMPLE
    Open-IRTTab
    Opens a new tab. Connects to the current tenant if a session is active.

    .EXAMPLE
    Open-IRTTab -Quiet
    Opens a new tab if in Windows Terminal; silently does nothing otherwise.

    .EXAMPLE
    Open-IRTTab -Title '[IRT] Secondary'
    Opens a new tab with a custom title.

    .OUTPUTS
    None

    .NOTES
    Version: 1.1.0
    1.1.0 - Requires Windows Terminal host. Opens without connecting when no
            active session exists.
    #>
    [Alias('OpenIRTTab', 'Open-Tab', 'OpenTab', 'NewIRTTab', 'New-Tab', 'NewTab', 'IRTTab')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string] $Title = '[IRT]',

        [switch] $Quiet
    )

    process {
        if (-not $env:WT_SESSION) {
            if (-not $Quiet) {
                Write-Error 'This command must be run from within Windows Terminal.'
            }
            return
        }

        $ModuleName = $MyInvocation.MyCommand.Module.Name
        $HasSession = $Global:IRT_Session -and $Global:IRT_Session.TenantId

        if ($HasSession) {
            $TenantId = $Global:IRT_Session.TenantId
            $Cloud = $Global:IRT_Session.Environment
            $ClientId = $Global:IRT_Session.ClientId

            $ConnectParts = [System.Collections.Generic.List[string]]::new()
            $ConnectParts.Add("Connect-IRT -TenantId '$TenantId'")
            if ($Cloud) { $ConnectParts.Add("-Cloud $Cloud") }
            if ($ClientId) { $ConnectParts.Add("-ClientId '$ClientId'") }

            $InnerScript = "Import-Module $ModuleName; $($ConnectParts -join ' ')"
            Write-IRT "Opening new tab for tenant $TenantId"
        } else {
            $InnerScript = "Import-Module $ModuleName"
            Write-IRT 'Opening new tab (no active session; module will load without connecting)'
        }

        $Encoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($InnerScript)
        )

        $WtArgs = @(
            '--window', '0',
            'new-tab',
            '--startingDirectory', $PWD.Path,
            '--no-focus',
            '--title', $Title,
            '--',
            'pwsh', '-NoExit', '-EncodedCommand', $Encoded
        )
        & wt $WtArgs
    }
}
#EndRegion '.\Public\Connect\Open-IRTTab.ps1' 95
#Region '.\Public\Connect\Test-IRTConnection.ps1' -1

function Test-IRTConnection {
    <#
    .SYNOPSIS
    Shows which IRT services are connected and to which tenant.

    .DESCRIPTION
    Checks the current Graph and Exchange Online connections and displays
    the connected domain for each. Useful for confirming which tenant you
    are working against before running incident response commands.

    .PARAMETER Quiet
    Returns $true if both Graph and Exchange are connected to the same
    tenant (matched by TenantId), $false otherwise. Suppresses all output.

    .EXAMPLE
    Test-IRTConnection
    Displays connection status for Graph and Exchange.

    .EXAMPLE
    if (-not (Test-IRTConnection -Quiet)) { throw 'Not fully connected.' }
    Silently asserts that both services are connected to the same tenant.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param (
        [switch] $Quiet
    )

    process {

        $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
        $GraphTokenValid = $false
        if ($GraphCtx) {
            try {
                $GraphParams = @{
                    Method      = 'GET'
                    Uri         = 'https://graph.microsoft.com/v1.0/organization?$select=id&$top=1'
                    ErrorAction = 'Stop'
                }
                $null = Invoke-MgGraphRequest @GraphParams
                $GraphTokenValid = $true
            } catch {
                $GraphTokenValid = $false
            }
        }

        $IppsPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'
        $AllExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' }
        $ExoConn = $AllExoConns |
            Where-Object { $_.ConnectionUri -notmatch $IppsPattern } |
            Select-Object -First 1
        $IppsConn = $AllExoConns |
            Where-Object { $_.ConnectionUri -match $IppsPattern } |
            Select-Object -First 1

        $GraphConnected = $GraphCtx -and $GraphCtx.Account -and $GraphTokenValid
        $ExoConnected = $null -ne $ExoConn
        $IppsConnected = $null -ne $IppsConn

        if ($Quiet) {
            if (-not $GraphConnected -or -not $ExoConnected) {
                return $false
            }
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId = $ExoConn.TenantID
            return ($GraphTenantId -and $ExoTenantId -and
                $GraphTenantId -eq $ExoTenantId)
        }

        # --- Verbose display ---
        $graphDomain = if ($GraphConnected) {
            ($GraphCtx.Account -split '@')[-1]
        } else { $null }

        $exoDomain = if ($ExoConnected) {
            ($ExoConn.UserPrincipalName -split '@')[-1]
        } else { $null }

        $ippsDomain = if ($IppsConnected) {
            ($IppsConn.UserPrincipalName -split '@')[-1]
        } else { $null }

        $rows = @(
            [pscustomobject]@{
                Service   = 'Graph'
                Connected = $GraphConnected
                Domain    = if ($graphDomain) { $graphDomain } else { '-' }
                Account   = if ($GraphConnected) { $GraphCtx.Account } else { '-' }
            }
            [pscustomobject]@{
                Service   = 'Exchange'
                Connected = $ExoConnected
                Domain    = if ($exoDomain) { $exoDomain } else { '-' }
                Account   = if ($ExoConnected) { $ExoConn.UserPrincipalName } else { '-' }
            }
            [pscustomobject]@{
                Service   = 'IPPS'
                Connected = $IppsConnected
                Domain    = if ($ippsDomain) { $ippsDomain } else { '-' }
                Account   = if ($IppsConnected) { $IppsConn.UserPrincipalName } else { '-' }
            }
        )

        $rows | Format-Table -AutoSize

        # warn if both are connected but to different tenants
        if ($GraphConnected -and $ExoConnected) {
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId = $ExoConn.TenantID
            if ($GraphTenantId -and $ExoTenantId -and $GraphTenantId -ne $ExoTenantId) {
                Write-Warning 'Graph and Exchange are connected to different tenants.'
            }
        }
    }
}
#EndRegion '.\Public\Connect\Test-IRTConnection.ps1' 120
#Region '.\Public\Connect\Update-IRTToken.ps1' -1

function Update-IRTToken {
    <#
    .SYNOPSIS
    Checks whether the token for one or more M365 services is expiring soon and refreshes
    if needed. Writes a friendly error if a required service is not connected.

    .DESCRIPTION
    Intended to be called at the start of any domain function that requires a live
    Graph, Exchange, or IPPS connection. For each requested service it reads the
    token expiry stored in $Global:IRT_Session and:

      - Writes an error message and returns if the service is not connected.
      - Calls Connect-IRT -Refresh when the token expires within 5 minutes.
      - Does nothing when the token is healthy.

    The 5-minute window aligns with MSAL's internal silent-refresh threshold so
    that AcquireTokenSilent uses the refresh token and returns genuinely new tokens
    rather than the same near-expired cached access token.

    .PARAMETER Service
    One or more service names to check. Accepts 'Graph', 'Exchange', and 'IPPS'.
    Defaults to all three.

    .PARAMETER SkipIfNeverConnected
    When set, silently skips any service that has no active session rather than
    writing an error. Intended for use in the prompt function, which runs regardless
    of whether the user has called Connect-IRT.

    .PARAMETER PassThru
    When set, returns a hashtable keyed by each requested service name with a boolean
    value indicating whether the token is currently valid (not expired). The status
    reflects the state after any refresh that was performed.

    .EXAMPLE
    Update-IRTToken -Service 'Graph'
    Checks and refreshes the Graph token if it is expiring within 5 minutes.
    Writes an error if the Graph session does not exist.

    .EXAMPLE
    Update-IRTToken -Service 'Graph', 'Exchange'
    Checks both Graph and Exchange tokens and refreshes if either is expiring soon.

    .EXAMPLE
    Update-IRTToken
    Checks all three services (Graph, Exchange, IPPS).

    .OUTPUTS
    System.Collections.Hashtable
    When -PassThru is specified, returns a hashtable keyed by service name (Graph,
    Exchange, IPPS) with boolean values indicating whether each token is currently valid.
    Returns nothing otherwise.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Automatic token-refresh guard; ShouldProcess is not applicable here.')]
    param (
        [ValidateSet('Graph', 'Exchange', 'IPPS')]
        [string[]] $Service = @('Graph', 'Exchange', 'IPPS'),

        [switch] $SkipIfNeverConnected,

        [switch] $PassThru
    )

    if (-not $Global:IRT_Session) {
        if (-not $SkipIfNeverConnected) {
            foreach ($svc in $Service) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
        }
        return
    }

    $needsRefresh = $false
    foreach ($svc in $Service) {
        $svcObj = $Global:IRT_Session.$svc
        if (-not $svcObj -or -not $svcObj.Token -or -not $svcObj.TokenExpiry) {
            if (-not $SkipIfNeverConnected) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
            continue
        }
        if (($svcObj.TokenExpiry - [datetime]::UtcNow).TotalMinutes -lt 5) {
            $needsRefresh = $true
        }
    }

    if ($needsRefresh) {
        Write-IRT 'Token expiring soon - refreshing...'
        try {
            $null = Connect-IRT -Refresh -ErrorAction Stop
        }
        catch {
            Write-IRT "Token refresh failed: $_" -Level Error
        }
    }

    if ($PassThru) {
        $status = @{}
        foreach ($svc in $Service) {
            $svcObj = $Global:IRT_Session.$svc
            $status[$svc] = [bool](
                $svcObj -and $svcObj.TokenExpiry -and
                ($svcObj.TokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0
            )
        }
        return $status
    }
}
#EndRegion '.\Public\Connect\Update-IRTToken.ps1' 115
#Region '.\Public\Device\Disable-IRTDevice.ps1' -1

function Disable-IRTDevice {
    <#
	.SYNOPSIS
	Disable Entra device account(s).

	.NOTES
	Version: 1.0.0
	#>
    [Alias('DisableDevice', 'DisableDevices')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $DeviceObject ) {
        $Params['DeviceObject'] = $DeviceObject
    }

    Set-IRTDeviceEnabled @Params
}
#EndRegion '.\Public\Device\Disable-IRTDevice.ps1' 26
#Region '.\Public\Device\Enable-IRTDevice.ps1' -1

function Enable-IRTDevice {
    <#
	.SYNOPSIS
	Enable Entra device account(s).

	.NOTES
	Version: 1.0.0
	#>
    [Alias('EnableDevice', 'EnableDevices')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $DeviceObject ) {
        $Params['DeviceObject'] = $DeviceObject
    }

    Set-IRTDeviceEnabled @Params
}
#EndRegion '.\Public\Device\Enable-IRTDevice.ps1' 26
#Region '.\Public\Device\Find-IRTDevice.ps1' -1

function Find-IRTDevice {
    <#
    .SYNOPSIS
    Finds devices by display name, device ID, operating system, registered owner, serial number,
    or other Entra/Intune identifiers. Creates $IRT_DeviceObjects from combined Entra + Intune
    device records.

    .EXAMPLE
    Find-IRTDevice DESKTOP-ABC123
    Find-IRTDevice -Search DESKTOP-ABC123,LAPTOP-XYZ789
    Find-IRTDevice flast@domain.com
    Find-IRTDevice -Search bf7573a5844f   # partial device id / Entra id / Intune id
    Find-IRTDevice -Search SN1234567890   # serial number (Intune)

    .NOTES
    Version: 1.2.0
    1.2.0 - Added -AllMatches to collect all matching devices and deduplicate results.
    #>
    [Alias('FindDevice', 'FindDevices')]
    [OutputType([psobject[]])]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $ScriptDeviceObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'OperatingSystem'
            'DisplayName'
            'OwnerUPN'
            'DeviceId'
        )

        # get all combined device objects from cache
        $AllDevices = Request-GraphDevice -Cached
    }

    process {

        Write-IRT ''

        foreach ($SearchString in $Search) {

            # match against flat convenience properties, Entra sub-object, and Intune sub-object
            $MatchingDevices = $AllDevices | Where-Object {
                $_.DisplayName -match $SearchString -or
                $_.DeviceId -match $SearchString -or
                $_.Entra.Id -match $SearchString -or
                $_.Intune.Id -match $SearchString -or
                $_.OperatingSystem -match $SearchString -or
                $_.OwnerUPN -match $SearchString -or
                # Entra registered-owner display names (not always in OwnerUPN)
                ($_.Entra -and (
                    $_.Entra.RegisteredOwners | Where-Object {
                        $_.AdditionalProperties['displayName'] -match $SearchString
                    }
                )) -or
                # Intune-specific identifiers
                ($_.Intune -and (
                    $_.Intune.DeviceName -match $SearchString -or
                    $_.Intune.SerialNumber -match $SearchString -or
                    $_.Intune.EmailAddress -match $SearchString -or
                    $_.Intune.Imei -match $SearchString
                ))
            }

            if (($MatchingDevices | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    # show device info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                }

                $Device = $MatchingDevices | Select-Object -First 1
                if ($SeenIds.Add($Device.Entra.Id)) {
                    $ScriptDeviceObjects.Add($Device)
                }
            }
            elseif (($MatchingDevices | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    # show device info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($Device in $MatchingDevices) {
                        if ($SeenIds.Add($Device.Entra.Id)) {
                            $ScriptDeviceObjects.Add($Device)
                        }
                    }
                } elseif (-not $Script) {
                    $Msg = 'Multiple devices found. Refine search or use -AllMatches.'
                    Write-IRT $Msg -Level Error
                }
            }
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return [psobject[]]$ScriptDeviceObjects
        }

        if ( $ScriptDeviceObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}DeviceObjects"
                Value = @($ScriptDeviceObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}DeviceObjects"

            if ( $ScriptDeviceObjects.Count -gt 1 ) {
                $ScriptDeviceObjects | Format-Table $DisplayProperties
            }
        }
    }
}
#EndRegion '.\Public\Device\Find-IRTDevice.ps1' 140
#Region '.\Public\Device\Remove-IRTDevice.ps1' -1

function Remove-IRTDevice {
    <#
	.SYNOPSIS
	Permanently delete Entra and Intune device(s). Requires the user to type each
	device's display name as confirmation before deletion proceeds.

	.DESCRIPTION
	Removes the Entra directory object (Remove-MgDevice) and, when the device is
	Intune-enrolled, the Intune managed device (Remove-MgDeviceManagementManagedDevice)
	for each supplied device object.

	Before any deletion the user is shown the device's DisplayName, Entra ID,
	Intune ID (or '(not enrolled)'), and OS. The user must then type the
	DisplayName exactly to proceed. Use -Force to bypass this prompt (e.g. in
	automated remediation scripts). -WhatIf and -Confirm are also supported.

	.PARAMETER DeviceObject
	One or more combined Entra+Intune device objects as returned by Find-IRTDevice
	or stored in $IRT_DeviceObjects. If omitted, $IRT_DeviceObjects is used.

	.PARAMETER Force
	Skip the manual name-confirmation prompt. The SupportsShouldProcess gate
	(-WhatIf / -Confirm) still applies.

	.EXAMPLE
	Remove-IRTDevice
	Operates on $IRT_DeviceObjects. Prompts for name confirmation before each deletion.

	.EXAMPLE
	Find-IRTDevice DESKTOP-ABC123
	Remove-IRTDevice
	Find a device by name, then delete it (with confirmation prompt).

	.EXAMPLE
	Remove-IRTDevice -Force -WhatIf
	Show what would be deleted without prompting or actually deleting anything.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('DeleteDevice', 'DeleteDevices', 'RemoveDevice', 'RemoveDevices')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [switch] $Force
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $DeviceObject -or $DeviceObject.Count -eq 0 ) {

            # get from global variables
            $ScriptDeviceObjects = @( $Global:IRT_DeviceObjects )

            # if none found, exit
            if ( -not $ScriptDeviceObjects -or $ScriptDeviceObjects.Count -eq 0 ) {
                throw "No device objects passed or found in global variables."
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }
    }

    process {

        foreach ( $ScriptDeviceObject in $ScriptDeviceObjects ) {

            $EntraId = $ScriptDeviceObject.Entra?.Id
            $IntuneId = $ScriptDeviceObject.Intune?.Id
            $DisplayName = $ScriptDeviceObject.DisplayName

            if ( -not $EntraId ) {
                Write-IRT "No Entra device object found for: $DisplayName. Skipping." -Level Warn
                continue
            }

            Write-IRT ''
            Write-IRT "Device to delete:" -Level Warn
            Write-IRT "  Display Name : $DisplayName"
            Write-IRT "  Entra ID     : $EntraId"
            Write-IRT "  Intune ID    : $(if ($IntuneId) { $IntuneId } else { '(not enrolled)' })"
            Write-IRT "  OS           : $($ScriptDeviceObject.OperatingSystem)"
            Write-IRT ''

            # --- manual name confirmation (unless -Force) ---
            if ( -not $Force ) {

                $Confirmation = Read-Host ('Type the device name exactly to confirm deletion' +
                    ' (or press Enter to skip)')
                if ( $Confirmation -ne $DisplayName ) {
                    Write-IRT "Confirmation did not match '$DisplayName'. Skipping." -Level Warn
                    continue
                }
            }

            # --- SupportsShouldProcess gate (-WhatIf / -Confirm) ---
            if ( $PSCmdlet.ShouldProcess($DisplayName, 'Permanently delete device') ) {

                # delete Intune managed device first (if enrolled)
                if ( $IntuneId ) {
                    Write-IRT "Deleting Intune device: $DisplayName"
                    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneId
                    Write-IRT "Intune device deleted."
                }

                # delete Entra device object
                Write-IRT "Deleting Entra device: $DisplayName"
                Remove-MgDevice -DeviceId $EntraId
                Write-IRT "Entra device deleted."
            }
        }

        Write-IRT ''
    }
}
#EndRegion '.\Public\Device\Remove-IRTDevice.ps1' 121
#Region '.\Public\Device\Show-IRTDevice.ps1' -1

function Show-IRTDevice {
    <#
    .SYNOPSIS
    Displays Entra and Intune device properties for combined device objects produced by
    Find-IRTDevice.

    .NOTES
    Version: 1.1.0
    #>
    [Alias(
        'Show-IRTDevices',
        'Show-Device', 'Show-Devices',
        'ShowIRTDevice', 'ShowIRTDevices',
        'ShowDevice', 'ShowDevices'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # if not passed directly, fall back to global variable
        if ( -not $DeviceObject -or $DeviceObject.Count -eq 0 ) {
            $ScriptDeviceObjects = @( $Global:IRT_DeviceObjects )
            if ( -not $ScriptDeviceObjects -or $ScriptDeviceObjects.Count -eq 0 ) {
                throw "No device objects passed or found in global variables."
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }
    }

    process {

        foreach ($ScriptDeviceObject in $ScriptDeviceObjects) {

            $DeviceName = $ScriptDeviceObject.DisplayName
            $EntraId = $ScriptDeviceObject.Entra?.Id    # null for Intune-only devices
            $IntuneId = $ScriptDeviceObject.Intune?.Id   # Intune managed device ID

            # --- Entra device ---
            if ( $EntraId ) {
                try {
                    $GetDeviceParams = @{
                        DeviceId       = $EntraId
                        ExpandProperty = 'RegisteredOwners'
                        ErrorAction    = 'Stop'
                    }
                    $FullEntraDevice = Get-MgDevice @GetDeviceParams

                    $OwnerUpn = ($FullEntraDevice.RegisteredOwners | ForEach-Object {
                            $_.AdditionalProperties['userPrincipalName']
                        }) -join ', '
                    $AddMemberParams = @{
                        NotePropertyName  = 'RegisteredOwnerUPN'
                        NotePropertyValue = $OwnerUpn
                        Force             = $true
                    }
                    $FullEntraDevice | Add-Member @AddMemberParams

                    Write-IRT "Showing Entra device properties for: ${DeviceName}"
                    $FullEntraDevice | Show-GraphDeviceTree | Out-Host
                }
                catch {
                    $ErrMsg = $_.Exception.Message
                    Write-IRT "Failed to get Entra device object: $ErrMsg" -Level Error
                }
            }
            else {
                Write-IRT "No Entra record for: ${DeviceName}" -Level Warn
            }

            # --- Intune device ---
            if ( $IntuneId ) {
                try {
                    $GetIntuneParams = @{
                        ManagedDeviceId = $IntuneId
                        ErrorAction     = 'Stop'
                    }
                    $FullIntuneDevice = Get-MgDeviceManagementManagedDevice @GetIntuneParams

                    Write-IRT "Showing Intune device properties for: ${DeviceName}"
                    $FullIntuneDevice | Format-Tree -Depth 5 -OmitNullOrEmpty | Out-Host
                }
                catch {
                    $ErrMsg = $_.Exception.Message
                    Write-IRT "Failed to get Intune device object: $ErrMsg" -Level Error
                }
            }
            else {
                Write-IRT "Device is not enrolled in Intune." -Level Warn
            }
        }
    }
}
#EndRegion '.\Public\Device\Show-IRTDevice.ps1' 101
#Region '.\Public\Entra\Get-IRTEntraAuditLog.ps1' -1

function Get-IRTEntraAuditLog {
    <#
    .SYNOPSIS
    Downloads Entra ID (Azure AD) audit log events for one or more users.

    .DESCRIPTION
    Queries the Entra ID directory audit log via Microsoft Graph for activity related
    to the specified users over a configurable date range. Results are exported to an
    Excel workbook. Use -AllUsers to pull the full tenant audit log regardless of user.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER AllUsers
    Pull the full tenant audit log without filtering by user.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint instead of v1.0.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data instead of making new API calls.

    .EXAMPLE
    Get-IRTEntraAuditLog
    Downloads the last 30 days of Entra audit events for the user in the global session.

    .EXAMPLE
    Get-IRTEntraAuditLog -UserObject $User -Days 90
    Downloads 90 days of audit events for a specific user.

    .EXAMPLE
    Get-IRTEntraAuditLog -AllUsers -Start '2026-04-01' -End '2026-04-30'
    Downloads all tenant audit events for April 2026.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('EALog', 'EALogs', 'GetEALog', 'GetEALogs')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [int] $Days, # default set at DEFAULTDAYS
        [string] $Start,
        [string] $End,

        [switch] $AllUsers,
        [switch] $Beta,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $FilterStrings = [System.Collections.Generic.List[string]]::new()
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDateString = Get-Date -Format $FileNameDateFormat
        $FileNamePrefix = 'EntraAuditLogs'

        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = 30 #DEFAULTDAYS
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc

        # if -AllUsers wasn't user, find user objects
        if (-not $AllUsers) {

            # if user objects not passed directly, find global
            if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

                # get from global variables
                $ScriptUserObjects = Get-GlobalUserObject

                # if none found, exit
                if (-not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0) {
                    throw "No user objects passed or found in global variables."
                }
            }
            else {
                $ScriptUserObjects = $UserObject
            }
        }
        # if -AllUsers was used, create fake user object user loop will happen
        else {

            $ScriptUserObjects = @(
                [pscustomobject]@{
                    UserPrincipalName = 'AllUsers'
                }
            )
        }

        # get client domain name
        $DomainName = Get-DefaultDomain
    }

    process {

        foreach ($ScriptUserObject in $ScriptUserObjects) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserName = $UserEmail -split '@' | Select-Object -First 1
            $UserId = $ScriptUserObject.Id

            # build file names
            $XmlOutputPath =
            "${FileNamePrefix}_${Days}Days_${DomainName}_${UserName}_${FileNameDateString}.xml"

            # build filter string
            if (-not $AllUsers) {
                $FilterStrings.Add("targetResources/any(t:t/Id eq '${UserId}')")
            }
            if ($DateRange.RangeType -eq 'Relative') {
                if ($Days -ne 30) { # don't use filter if date range is maximum
                    $FilterStrings.Add( "activityDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRange.RangeType -eq 'Absolute') {
                $FilterStrings.Add( "activityDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "activityDateTime le $($DateRange.EndString)" )
            }
            $FilterString = $FilterStrings -join " and "

            ### get logs
            # user messages
            Write-IRT "Retrieving ${Days} days of Entra audit logs for ${UserEmail}."
            Write-Verbose "${FunctionName}: Filter string: ${FilterString}"
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Get-MgAuditLogDirectoryAudit $Elapsed"

            # query logs
            $GetParams = @{
                All    = $true
                Filter = $FilterString
            }
            if ($Beta) {
                [System.Collections.Generic.List[PSObject]]$Logs =
                Get-MgBetaAuditLogDirectoryAudit @GetParams
            }
            else {
                [System.Collections.Generic.List[PSObject]]$Logs =
                Get-MgAuditLogDirectoryAudit @GetParams
            }

            # show count
            $Count = ($Logs | Measure-Object).Count
            if ($Count -gt 0) {
                Write-IRT "Retrieved ${Count} logs."
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Warn
                continue
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    UserObject     = $ScriptUserObject
                    UserEmail      = $UserEmail
                    UserName       = $UserName
                    StartDate      = $StartDateUtc.ToLocalTime()
                    EndDate        = $EndDateUtc.ToLocalTime()
                    Days           = $Days
                    DomainName     = $DomainName
                    FileNamePrefix = $FileNamePrefix
                }
            )

            # export to xml
            if ($Xml) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
                Write-IRT "Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }

            $ShowParams = @{
                Logs   = $Logs
                Open   = $Open
                Cached = $Cached
            }
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Show-IRTEntraAuditLog $Elapsed"
            Show-IRTEntraAuditLog @ShowParams
        }
    }
}
#EndRegion '.\Public\Entra\Get-IRTEntraAuditLog.ps1' 222
#Region '.\Public\Entra\Get-IRTEntraSignInLog.ps1' -1

function Get-IRTEntraSignInLog {
    <#
    .SYNOPSIS
    Downloads user sign in logs.

    .DESCRIPTION
    Retrieves Entra ID interactive sign-in logs via Microsoft Graph for one or more users,
    a set of IP addresses, or all users in the tenant. Enriches each log entry with
    IP geolocation data and human-readable Entra error descriptions, then exports results
    to an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    .PARAMETER UserObject
    One or more user objects whose sign-in logs to retrieve. Mutually exclusive with
    -AllUsers and -IpAddress. Falls back to global session objects if omitted.

    .PARAMETER AllUsers
    Retrieve sign-in logs for all users in the tenant. Mutually exclusive with -UserObject
    and -IpAddress.

    .PARAMETER IpAddress
    One or more IP addresses to filter sign-in logs by source IP. Mutually exclusive with
    -UserObject and -AllUsers.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER NonInteractive
    Retrieve non-interactive sign-in logs instead of interactive logs.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER IpInfo
    Enrich results with IP geolocation data. Default: $true.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Get-IRTEntraSignInLog
    Downloads the last 30 days of sign-in logs for the user in the global session.

    .EXAMPLE
    Get-IRTEntraSignInLog -UserObject $User -Days 90
    Downloads 90 days of sign-in logs for a specific user.

    .EXAMPLE
    Get-IRTEntraSignInLog -IpAddress '203.0.113.5' -Days 14
    Finds all sign-ins from a specific IP over the last 14 days.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.1.2
    1.1.2 - Added graceful exit when no logs are found.
    1.1.1 - Added test timers.
    #>
    [Alias('GetSILog', 'GetSILogs', 'SILog', 'SILogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'UserObject')]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [Parameter(ParameterSetName = 'IpAddress')]
        [string[]] $IpAddress,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        [switch] $NonInteractive,

        [boolean] $Beta = $true,
        [boolean] $Excel = $true,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {
        Update-IRTToken -Service 'Graph'

        #region BEGIN

        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # constants
        $ParameterSet = $PSCmdlet.ParameterSetName

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $ScriptUserObjects = Get-GlobalUserObject

                    # if none found, exit
                    if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                        $Msg = 'No user objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used,' +
                            ' no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'IpAddress' {
                $ScriptUserObjects = [System.Collections.Generic.List[pscustomobject]]::new()
                foreach ($IpAddress in $IpAddress) {
                    [void]$ScriptUserObjects.Add(
                        [pscustomobject]@{
                            UserPrincipalName = $IpAddress
                        }
                    )
                }
            }
            'AllUsers' {
                $null = $AllUsers  # switch controls parameter set; value not needed
                # build user object with null principal name
                $ScriptUserObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = 'AllUsers'
                    }
                )
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        #region DATE RANGE

        # API bug with filters may be fixed?
        # https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3146
        $DefaultDays = if ($NonInteractive) { 3 } else { 30 } # DEFAULTDAYS

        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            # users
            switch ( $ParameterSet ) {
                'UserObject' {
                    $Target = $ScriptUserObject.UserPrincipalName -split '@' |
                        Select-Object -First 1
                    $FilterStrings.Add( "UserId eq '$($ScriptUserObject.Id)'" )
                }
                'IpAddress' {
                    $Target = $ScriptUserObject.UserPrincipalName
                    $FilterStrings.Add( "ipAddress eq '$($ScriptUserObject.UserPrincipalName)'" )
                }
                'AllUsers' {
                    $Target = $DomainName
                    # don't add a user filter
                }
            }

            # build file names # must be after target is set
            if ( $NonInteractive ) {
                $FileNamePrefix = 'NonInteractiveLogs'
            }
            else {
                $FileNamePrefix = 'SignInLogs'
            }
            $FileNameDateFormat = "yy-MM-dd_HH-mm"
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}" +
            "_${Target}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleType = if ($NonInteractive) { 'Non-Interactive' } else { 'Interactive' }
            $SheetTitle = "${TitleType} sign-in logs for ${Target}." +
            " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            # time range
            if ($DateRangeType -eq 'Relative') {
                if ($Days -ne 30) { # don't use filter if date range is maximum
                    $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRangeType -eq 'Absolute') {
                $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "createdDateTime le $($DateRange.EndString)" )
            }

            # non interactive
            if ( $NonInteractive ) {
                $FilterStrings.Add( "signInEventTypes/any(t: t eq 'NonInteractiveUser')" )
            }
            $FilterString = $FilterStrings -join " and "

            #region QUERY LOGS
            # user messages
            if ( $NonInteractive ) {
                Write-IRT "Retrieving ${Days} days of noninteractive sign-in logs for ${Target}."
            }
            else {
                Write-IRT "Retrieving ${Days} days of sign-in logs for ${Target}."
            }
            Write-Verbose "${FunctionName}: Filter string: '${FilterString}'"
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Get-MgAuditLogSignIn $Elapsed"

            # query logs
            if ($Beta) { # default is to use beta, which returns more information
                # $GetProperties = @( # FIXME going to see how much slower pulling all properties is
                #     'AppDisplayName'
                #     'AuthenticationProtocol'
                #     'CorrelationID'
                #     'CreatedDateTime'
                #     'DeviceDetail'
                #     'IpAddress'
                #     'Location'
                #     'ResourceId'
                #     'Status'
                #     # 'UniqueTokenIdentifier'
                #     'UserAgent'
                #     'UserPrincipalName'
                # )
                $GetParams = @{
                    Filter = $FilterString
                    # Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs =
                Get-MgBetaAuditLogSignIn @GetParams  # | Select-Object $GetProperties
            }
            else { # if $Beta = $false
                # $GetProperties = @( # FIXME going to see how much slower pulling all properties is
                #     'AppDisplayName'
                #     'CorrelationID'
                #     'CreatedDateTime'
                #     'DeviceDetail'
                #     'IpAddress'
                #     'Location'
                #     'ResourceId'
                #     'Status'
                #     'UniqueTokenIdentifier'
                #     'UserAgent'
                #     'UserPrincipalName'
                # )
                $GetParams = @{
                    Filter = $FilterString
                    # Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs =
                Get-MgAuditLogSignIn @GetParams  # | Select-Object $GetProperties
            }

            if (($Logs | Measure-Object).Count -eq 0 ) {
                Write-IRT "No logs found for ${Target} for past ${Days} days. Exiting." -Level Error
                continue
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata = $true
                    FileNamePrefix = $FileNamePrefix
                    FileName = $FileNameBase
                    Title = $SheetTitle
                }
            )

            #region OUTPUT

            # show count, export
            $LogCount = ($Logs | Measure-Object).Count
            if ($LogCount -gt 0) {
                Write-IRT "Retrieved ${LogCount} logs."

                # export to xml
                if ($Xml) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
                    Write-IRT "Saving logs to: ${XmlOutputPath}"
                    $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
                }

                # export excel spreadsheet
                if ($Excel) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Show-IRTEntraSignInLog $Elapsed"
                    $Params = @{
                        Logs   = $Logs
                        IpInfo = $IpInfo
                        Open   = $Open
                    }
                    Show-IRTEntraSignInLog @Params
                }
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Error
            }
        }
    }
}
#EndRegion '.\Public\Entra\Get-IRTEntraSignInLog.ps1' 354
#Region '.\Public\Entra\Get-IRTNonInteractiveSignIn.ps1' -1

function Get-IRTNonInteractiveSignIn {
    <#
    .SYNOPSIS
    Downloads non-interactive Entra ID sign-in logs for one or more users.

    .DESCRIPTION
    A convenience wrapper around Get-IRTEntraSignInLog that sets -NonInteractive automatically.
    Non-interactive sign-ins include token refresh events, legacy protocol logins, and
    service-to-service calls - often missed during investigations that focus only on
    interactive sign-ins.

    Date range and output behavior are identical to Get-IRTEntraSignInLog.
    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Days
    Number of days back to search.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Script
    Return raw objects instead of exporting to Excel. Default: $false.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .EXAMPLE
    Get-IRTNonInteractiveSignIn
    Downloads non-interactive sign-in logs for the user in the global session.

    .EXAMPLE
    Get-IRTNonInteractiveSignIn -UserObject $User -Days 30
    Downloads 30 days of non-interactive sign-ins for a specific user.

    .OUTPUTS
    None by default. PSCustomObject[] when -Script is $true.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('GetNILog', 'GetNILogs', 'NILog', 'NILogs')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [int] $Days,
        [boolean] $Beta = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Script = $false,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $Params = @{
            UserObjects = $UserObject
            NonInteractive = $true
            Days = $Days
            Xml = $Xml
            Beta = $Beta
            Open = $Open
        }
        if ( $Script ) {
            $Params['Script'] = $true
        }
    }

    process {

        # run command
        Get-IRTEntraSignInLog @Params
    }
}
#EndRegion '.\Public\Entra\Get-IRTNonInteractiveSignIn.ps1' 84
#Region '.\Public\Entra\Get-IRTServicePrincipalSignInLog.ps1' -1

function Get-IRTServicePrincipalSignInLog {
    <#
    .SYNOPSIS
    Downloads service principal sign-in logs.

    .DESCRIPTION
    Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
    service principals or all service principals in the tenant. Enriches each log entry
    with IP geolocation data and human-readable Entra error descriptions, then exports
    results to an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. Use Find-IRTServicePrincipal first to populate that global variable.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects whose sign-in logs to retrieve. Mutually
    exclusive with -AllServicePrincipals. Falls back to global session objects if omitted.

    .PARAMETER AllServicePrincipals
    Retrieve sign-in logs for all service principals in the tenant. Mutually exclusive
    with -ServicePrincipalObject.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER IpInfo
    Enrich results with IP geolocation data. Default: $true.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Test
    Enable stopwatch timing output.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Find-IRTServicePrincipal MyApp
    Get-IRTServicePrincipalSignInLog
    Two-step workflow: find the SP then download its sign-in logs.

    .EXAMPLE
    Get-IRTServicePrincipalSignInLog -ServicePrincipalObject $SP -Days 90
    Downloads 90 days of sign-in logs for a specific service principal.

    .EXAMPLE
    Get-IRTServicePrincipalSignInLog -AllServicePrincipals -Days 7
    Downloads 7 days of sign-in logs for all service principals in the tenant.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('GetSPSILog', 'GetSPSILogs', 'SPSILog', 'SPSILogs')]
    [CmdletBinding(DefaultParameterSetName = 'ServicePrincipalObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'ServicePrincipalObject')]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [Parameter(ParameterSetName = 'AllServicePrincipals')]
        [switch] $AllServicePrincipals,

        # relative date range
        [int] $Days,
        # absolute date range
        [string] $Start,
        [string] $End,

        [boolean] $Beta = $true,
        [boolean] $Excel = $true,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {
        Update-IRTToken -Service 'Graph'

        #region BEGIN

        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # resolve service principal objects
        switch ($ParameterSet) {
            'ServicePrincipalObject' {
                if (($ServicePrincipalObject | Measure-Object).Count -gt 0) {
                    $ScriptSPObjects = $ServicePrincipalObject
                }
                else {
                    $ScriptSPObjects = @($Global:IRT_ServicePrincipalObjects)
                    if (-not $ScriptSPObjects -or $ScriptSPObjects.Count -eq 0) {
                        $Msg = 'No service principal objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                }
            }
            'AllServicePrincipals' {
                $null = $AllServicePrincipals
                $ScriptSPObjects = @(
                    [pscustomobject]@{
                        DisplayName = 'AllServicePrincipals'
                        Id          = $null
                    }
                )
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        #region DATE RANGE

        $DefaultDays = 30

        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc
    }

    process {

        foreach ($ScriptSPObject in $ScriptSPObjects) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            switch ($ParameterSet) {
                'ServicePrincipalObject' {
                    $Target = $ScriptSPObject.DisplayName
                    $FilterStrings.Add( "servicePrincipalId eq '$($ScriptSPObject.Id)'" )
                }
                'AllServicePrincipals' {
                    $Target = $DomainName
                    # no SP filter
                }
            }

            # build file names -- must be after target is set
            $FileNamePrefix = 'SPSignInLogs'
            $FileNameDateFormat = 'yy-MM-dd_HH-mm'
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $FileNameBase =
            "${FileNamePrefix}_${Days}Days_${DomainName}_${Target}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = 'M/d/yy h:mmtt'
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $SheetTitle = "Service principal sign-in logs for ${Target}." +
            " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            # sign-in event type filter
            $FilterStrings.Add( "signInEventTypes/any(t: t eq 'servicePrincipal')" )

            # time range
            if ($DateRangeType -eq 'Relative') {
                if ($Days -ne 30) {
                    $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRangeType -eq 'Absolute') {
                $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "createdDateTime le $($DateRange.EndString)" )
            }

            $FilterString = $FilterStrings -join ' and '

            #region QUERY LOGS

            Write-IRT "Retrieving ${Days} days of service principal sign-in logs for ${Target}."
            Write-Verbose "${FunctionName}: Filter string: '${FilterString}'"
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Get-MgAuditLogSignIn $Elapsed"

            if ($Beta) {
                $GetParams = @{
                    Filter = $FilterString
                    All    = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs =
                Get-MgBetaAuditLogSignIn @GetParams
            }
            else {
                $GetParams = @{
                    Filter = $FilterString
                    All    = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgAuditLogSignIn @GetParams
            }

            if (($Logs | Measure-Object).Count -eq 0) {
                Write-IRT "No logs found for ${Target} for past ${Days} days. Exiting." -Level Error
                continue
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    FileNamePrefix = $FileNamePrefix
                    FileName       = $FileNameBase
                    Title          = $SheetTitle
                }
            )

            #region OUTPUT

            $LogCount = ($Logs | Measure-Object).Count
            if ($LogCount -gt 0) {
                Write-IRT "Retrieved ${LogCount} logs."

                # export to xml
                if ($Xml) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
                    Write-IRT "Saving logs to: ${XmlOutputPath}"
                    $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
                }

                # export excel spreadsheet
                if ($Excel) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Show-IRTServicePrincipalSignIn $Elapsed"
                    $Params = @{
                        Logs   = $Logs
                        IpInfo = $IpInfo
                        Open   = $Open
                    }
                    Show-IRTServicePrincipalSignIn @Params
                }
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Error
            }
        }
    }
}
#EndRegion '.\Public\Entra\Get-IRTServicePrincipalSignInLog.ps1' 269
#Region '.\Public\Entra\Show-IRTEntraAuditLog.ps1' -1

function Show-IRTEntraAuditLog {
    <#
	.SYNOPSIS
    Shows Entra audit logs in terminal, or saves as an excel spreadsheet.

	.NOTES
	Version: 1.2.1
    1.2.1 - Updates to use new get-graphobject functions.
    1.2.0 - Many small updates to standardize across IR functions. Updated to readable date format.
	#>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [switch] $Cached
    )

    begin {
        # get logs from file if xml path used
        if ( $XmlPath ) {

            $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
            [System.Collections.Generic.List[PSObject]]$Log = Import-Clixml -Path $ResolvedXmlPath
        }
        elseif ( -not $Log ) {

            # run import-logs to get file name
            $ImportParams = @{
                Pattern    = "^EntraAuditLogs_Raw_.*\.xml$"
                ReturnPath = $true
            }
            $ResolvedXmlPath = Import-LogFile @ImportParams

            # use path to import logs
            [System.Collections.Generic.List[PSObject]]$Log = Import-Clixml -Path $ResolvedXmlPath
        }

        #region METADATA
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)

            # $UserEmail = $Metadata.UserEmail
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
            $FileNamePrefix = $Metadata.FileNamePrefix
        }
        else {
            Write-IRT "No Metadata found." -Level Error -FunctionName $Function
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $TitleDateFormat = "M/d/yy h:mmtt"
        $TitleStartDate = $StartDate.ToLocalTime().ToString($TitleDateFormat)
        $TitleEndDate = $EndDate.ToLocalTime().ToString($TitleDateFormat)
        # if allusers, use domain as username
        if ( $UserName -eq 'AllUsers' ) {
            $UserName = $DomainName
        }
        $WorksheetTitle = "Entra audit logs for ${UserName}." +
        " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

        #region CONSTANTS

        $Function = $MyInvocation.MyCommand.Name
        # $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $WorksheetName = 'EntraAudit'
        $Groups = Request-GraphGroup -Cached:$Cached
        $Roles = Request-DirectoryRole -Cached:$Cached
        $RoleTemplates = Request-DirectoryRoleTemplate -Cached:$Cached
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
        $Users = Request-GraphUser -Cached:$Cached

        # event date formatting
        $RawDateProperty = 'ActivityDateTime'
        $DateColumnHeader = 'DateTime'
        $DisplayProperties = @(
            'Raw'
            $DateColumnHeader
            'OperationType'
            'ActivityDisplayName'
            'InitiatedBy'
            'InitiatedByIp'
            'Target'
            'ModifiedProperties'
            'Details'
            'Result'
            'ResultReason'
        )

    }

    process {
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()

        # process each log
        for ($i = 0; $i -lt ($Log | Measure-Object).Count; $i++) {

            # variables
            $Target = $null
            $TargetString = $null
            $TargetStrings = [System.Collections.Generic.list[string]]::new()
            $AllTargets = $null
            $ModifiedStrings = [System.Collections.Generic.list[string]]::new()
            $InitiatedByStrings = [System.Collections.Generic.list[string]]::new()
            $DetailsString = $null
            $DetailStrings = [System.Collections.Generic.list[string]]::new()

            $LogEntry = $Log[$i]
            $Row = [PSCustomObject]@{}

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Raw'
                Value      = $Raw
            }
            $Row | Add-Member @AddParams

            # DateTime
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }
            $AddParams = @{
                MemberType  = 'NoteProperty'
                Name        = $DateColumnHeader
                Value       = $DateTime
            }
            $Row | Add-Member @AddParams

            # operationtype
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'OperationType'
                Value      = $LogEntry.OperationType
            }
            $Row | Add-Member @AddParams

            # category
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Category'
                Value      = $LogEntry.Category
            }
            $Row | Add-Member @AddParams

            # ActivityDisplayName
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ActivityDisplayName'
                Value      = $LogEntry.ActivityDisplayName
            }
            $Row | Add-Member @AddParams

            ### initiated by
            # if user, get perferred property
            if ( $LogEntry.InitiatedBy.User.UserPrincipalName ) {
                $InitiatedByString = $LogEntry.InitiatedBy.User.UserPrincipalName
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            elseif ( $LogEntry.InitiatedBy.User.Id ) {
                $User = $Users | Where-Object { $_.Id -eq $LogEntry.InitiatedBy.User.Id }
                if ( $User ) {
                    $InitiatedByString = $User.UserPrincipalName
                }
                else {
                    $InitiatedByString = $LogEntry.InitiatedBy.User.Id
                }
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            # if app, get preferred property
            if ( $LogEntry.InitiatedBy.App.DisplayName ) {
                $InitiatedByString = $LogEntry.InitiatedBy.App.DisplayName
                $InitiatedByStrings.Add( "App: ${InitiatedByString}" )

            }
            elseif ( $LogEntry.InitiatedBy.App.ServicePrincipalId ) {
                $ServicePrincipal = $ServicePrincipals |
                    Where-Object { $_.Id -eq $LogEntry.InitiatedBy.App.ServicePrincipalId }
                if ( $ServicePrincipal ) {
                    $InitiatedByString = $ServicePrincipal.DisplayName
                }
                else {
                    $InitiatedByString = $LogEntry.InitiatedBy.App.ServicePrincipalId
                }
                $InitiatedByStrings.Add( "App: ${InitiatedByString}" )
            }

            # join strings if multiple
            $AllInitiatedByStrings = $InitiatedByStrings -join ', '
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'InitiatedBy'
                Value      = $AllInitiatedByStrings
            }
            $Row | Add-Member @AddParams

            # initiatedby user ip
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'InitiatedByIp'
                Value      = $LogEntry.InitiatedBy.User.IPAddress
            }
            $Row | Add-Member @AddParams

            # get target information
            foreach ( $Resource in $LogEntry.TargetResources ) {

                # resource name
                $ResourceType = $Resource.Type
                if ( $ResourceType ) {
                    switch ( $ResourceType ) {
                        'Directory' {
                            $Target = $Resource.DisplayName
                        }
                        'Group' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $Group = $Groups | Where-Object { $_.Id -eq $Resource.Id }
                                $Target = $Group.DisplayName
                            }
                        }
                        'N/A' {
                            $Target = $Resource.Id
                        }
                        'Other' {
                            $Target = $Resource.DisplayName
                        }
                        'Policy' {
                            $Target = $Resource.DisplayName
                        }
                        'Request' {
                            $Target = $Resource.Id
                        }
                        'Role' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $Role = $Roles | Where-Object { $_.Id -eq $Resource.Id }
                                if ( -not $Role ) {
                                    $Role = $RoleTemplates | Where-Object { $_.Id -eq $Resource.Id }
                                }
                                $Target = $Role.DisplayName
                            }
                        }
                        'ServicePrincipal' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $ServicePrincipal = $ServicePrincipals |
                                    Where-Object { $_.Id -eq $Resource.Id }
                                $Target = $ServicePrincipal.DisplayName
                            }
                        }
                        'User' {
                            if ( $Resource.UserPrincipalName ) {
                                $Target = $Resource.UserPrincipalName
                            }
                            else {
                                $User = $Users | Where-Object { $_.Id -eq $Resource.Id }
                                $Target = $User.UserPrincipalName
                            }
                        }
                        default {
                            $Target = $Resource.Id
                        }
                    }
                    $TargetString = "${ResourceType}: ${Target}"
                    $TargetStrings.Add( $TargetString )
                }

                # modified properties
                if ( $Resource.ModifiedProperties ) {
                    $ModifiedStrings.Add( "Target: ${TargetString}" )
                    foreach ( $Property in $Resource.ModifiedProperties ) {
                        $Name = $null
                        $Old = $null
                        $New = $null
                        $Name = $Property.DisplayName
                        $Old = $Property.OldValue
                        $New = $Property.NewValue
                        $ModifiedString = "Property: '${Name}', Old: '${Old}', New: '${New}'"
                        $ModifiedStrings.Add( $ModifiedString )
                    }
                }
            }
            # add target info
            $TargetStrings = $TargetStrings | Sort-Object -Unique
            $AllTargets = $TargetStrings -join ', '
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Target'
                Value      = $AllTargets
            }
            $Row | Add-Member @AddParams
            # add modified properties
            $AllModifiedStrings = $ModifiedStrings -join "`n"
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ModifiedProperties'
                Value      = $AllModifiedStrings
            }
            $Row | Add-Member @AddParams

            # AdditionalDetails
            foreach ( $Detail in $LogEntry.AdditionalDetails ) {

                # variables
                $Key = $Detail.Key
                $AppId = $null
                $Value = $null

                # translate ids into human names
                switch ( $Key ) {
                    'AppId' {
                        $AppId = $Detail.Value
                        $Value = ( $ServicePrincipals |
                                Where-Object { $_.AppId -eq $AppId } ).DisplayName
                    }
                    'AppOwnerOrganizationId' {
                        $AppOwnerOrganizationId = $Detail.Value
                        try {
                            $TenantInfo = Get-IRTTenantOwner -TenantId $AppOwnerOrganizationId
                            if ( $TenantInfo.DisplayName ) {
                                $Value = $TenantInfo.DisplayName
                            }
                            else {
                                $Value = $Detail.Value
                            }
                        }
                        catch {
                            $Value = $Detail.Value
                        }
                    }
                    default {
                        $Value = $Detail.Value
                    }
                }

                # add string to list of strings
                $DetailStrings.Add( "${Key}: ${Value}" )
            }
            # join list into one string
            $DetailsString = $DetailStrings -join ', '
            # add final string to object
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Details'
                Value      = $DetailsString
            }
            $Row | Add-Member @AddParams

            # Result
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Result'
                Value      = $LogEntry.Result
            }
            $Row | Add-Member @AddParams

            # ResultReason
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ResultReason'
                Value      = $LogEntry.ResultReason
            }
            $Row | Add-Member @AddParams

            # add to list
            $Rows.Add($Row)
        }

        # select just relevant properties
        $OutputTable = $OutputTable | Select-Object $DisplayProperties

        # export spreadsheet
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $WorksheetName
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            AutoSize      = $true
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-Error "Unable to open new Excel document."
            if ( Get-YesNo "Try closing open files." ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    throw "Unable to open new Excel document. Exiting."
                }
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($IpInfo) { Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'InitiatedByIp' }
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        if ($Worksheet.Tables.Count -gt 0) {

            $TableStartColumn = ($workSheet.Tables.Address | Select-Object -First 1).Start.Column |
                Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row

            #region CELL COLORING

            # if cell matches EXACTLY, make background RED
            $Strings = @(
                'Add app role assignment grant to user'
                'Add member to role'
                'Change password (self-service)'
                'Change user password'
                'User registered all required security info'
                'User registered security info'
            )
            foreach ( $String in $Strings ) {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                    RuleType        = 'Equal'
                    ConditionValue  = $String
                    BackgroundColor = 'LightPink'
                }
                Add-ConditionalFormatting @CFParams
            }

            # if cell matches EXACTLY, make background YELLOW
            $Strings = @(
                'User started security info registration'
            )
            foreach ( $String in $Strings ) {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                    RuleType        = 'Equal'
                    ConditionValue  = $String
                    BackgroundColor = 'LightGoldenRodYellow'
                }
                Add-ConditionalFormatting @CFParams
            }

            # if cell CONTAINS text anywhere, make background BLUE
            $Strings = @(
                'AppOwnerOrganizationId: Microsoft'
            )
            foreach ( $String in $Strings ) {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $String
                    BackgroundColor = 'LightBlue'
                }
                Add-ConditionalFormatting @CFParams
            }

            #region COLUMN WIDTH

            $ColumnWidths = @{
                'Raw'                = 8
                $DateColumnHeader    = 26
                'ActivityDisplayName' = 25
                'InitiatedBy'        = 45
                'InitiatedByIp'      = 17
                'Target'             = 45
                'ModifiedProperties' = 25
                'Details'            = 25
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # set date format
            $FmtParams = @{
                Worksheet = $Worksheet
                Range = "B:B"
                NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
            }
            Set-ExcelRange @FmtParams

            # set font and size
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            try {
                Set-ExcelRange @SetParams
            } catch {}

            # add left side border
            $BorderParams = @{
                Worksheet = $Worksheet
                Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

        } # end if ($Worksheet.Tables.Count -gt 0)

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}" -FunctionName $Function
        if ( $Open ) {
            Write-IRT "Opening Excel." -FunctionName $Function
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
#EndRegion '.\Public\Entra\Show-IRTEntraAuditLog.ps1' 554
#Region '.\Public\Entra\Show-IRTEntraSignInLog.ps1' -1

function Show-IRTEntraSignInLog {
    <#
	.SYNOPSIS
	Processes Sign in log .XML file into Excel spreadsheet.

	.NOTES
	Version: 1.1.3
    1.1.3 - Added timers/progress for testing.
	#>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'CreatedDateTime'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Import-CliXml $Elapsed"
                [System.Collections.Generic.List[PSObject]]$Log =
                Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                $ErrorParams = @{
                    Category    = 'ReadError'
                    Message     = "Error importing from ${XmlPath}."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        #region Metadata
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + ".xlsx"

        # get worksheet title from metadata
        $WorksheetTitle = $Metadata.Title
    }

    process {

        #region ROW LOOP

        $RowCount = ($Log | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Row loop starting (${RowCount} rows) $Elapsed"
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $LogEntry = $Log[$i]

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }

            # IpAddress
            $IpText = $LogEntry.IpAddress

            # application display name / resource id
            if ( $LogEntry.AppDisplayName ) {
                $AppDisplayName = $LogEntry.AppDisplayName
            }
            else {
                $AppDisplayName = $LogEntry.ResourceId
            }

            # compress trust
            $Trust = Convert-TrustType -TrustType $LogEntry.DeviceDetail.TrustType

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw = $Raw
                    $DateColumnHeader = $DateTime
                    UserPrincipalName = $LogEntry.UserPrincipalName
                    Error = ConvertTo-HumanErrorDescription -ErrorCode $LogEntry.Status.ErrorCode
                    IpAddress = $IpText
                    City = $LogEntry.Location.City
                    State = $LogEntry.Location.State
                    Co = $LogEntry.Location.CountryOrRegion
                    Application = $AppDisplayName
                    Browser = $LogEntry.DeviceDetail.Browser
                    OS = $LogEntry.DeviceDetail.OperatingSystem
                    Trust = $Trust
                    UserAgent = $LogEntry.UserAgent
                    Session = $LogEntry.CorrelationId
                    Token = $LogEntry.UniqueTokenIdentifier
                })

            if ($VerbosePreference -ne 'SilentlyContinue' -and ($i % 100 -eq 0)) {
                $Percent = [int]( ($i / $RowCount ) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
            }
        }

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed
        }

        #region EXPORT SPREADSHEET
        Write-Verbose "${FunctionName}: Export-Excel $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $Metadata.FileNamePrefix
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            # AutoSize      = $true # apparently very slow?
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-Error "Unable to open new Excel document."
            if ( Get-YesNo "Try closing open files." ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    throw "Unable to open new Excel document. Exiting."
                }
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column |
            Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $IpAddressColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'IpAddress' }).Id |
                Convert-DecimalToExcelColumn
        $ApplicationColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Application' }).Id |
                Convert-DecimalToExcelColumn
        $UserAgentColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'UserAgent' }).Id |
                Convert-DecimalToExcelColumn

        #region CELL COLORING

        # ip address enrichment and conditional formatting
        if ($IpInfo) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Add-IpInfoToSheet $Elapsed"
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'
        }

        # applications
        $Strings = @(
            'Azure Active Directory PowerShell'
            'Microsoft Azure CLI'
            'Microsoft Exchange REST API Based Powershell'
            'Microsoft Graph Command Line Tools'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${ApplicationColumn}:${ApplicationColumn}"
                RuleType        = 'Equal'
                ConditionValue  = $String
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }

        # user agents
        $Strings = @(
            'axios'
            'BAV2ROPC'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${UserAgentColumn}:${UserAgentColumn}"
                RuleType        = 'ContainsText'
                ConditionValue  = $String
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'               = 8
            $DateColumnHeader   = 26
            'UserPrincipalName' = 30
            'Error'             = 25
            'IpAddress'         = 20
            'City'              = 10
            'State'             = 10
            'Co'                = 6
            'Application'       = 25
            'Browser'           = 20
            'OS'                = 12
            'Trust'             = 12
            'UserAgent'         = 150
            'Session'           = 10
            'Token'             = 10
        }
        foreach ($ColName in $ColumnWidths.Keys) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
            if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
        }

        #region FORMATTING

        # set date format
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-ExcelRange @FmtParams

        # set text wrapping on ip address column
        $WrapParams = @{
            Worksheet = $Worksheet
            Range = "${IpAddressColumn}:${IpAddressColumn}"
            WrapText = $true
        }
        Set-ExcelRange @WrapParams

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = $Font
        }
        try {
            Set-ExcelRange @SetParams
        } catch {}

        # add left side border
        $BorderParams = @{
            Worksheet = $Worksheet
            Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        # set row height
        # $HeightParams = @{
        #     Worksheet = $Worksheet
        #     Row = ($TableStartRow..$EndRow)
        #     Height = 15
        # }
        # Set-ExcelRow @HeightParams
        for ( $i = $TableStartRow; $i -le $EndRow; $i++ ) {
            $Row = $Worksheet.Row($i)
            $Row.Height = 15
            $Row.CustomHeight = $true
        }

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-IRT "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
#EndRegion '.\Public\Entra\Show-IRTEntraSignInLog.ps1' 317
#Region '.\Public\Entra\Show-IRTServicePrincipalSignIn.ps1' -1

function Show-IRTServicePrincipalSignIn {
    <#
    .SYNOPSIS
    Processes service principal sign-in log objects into an Excel spreadsheet.

    .DESCRIPTION
    Takes service principal sign-in log objects produced by Get-IRTServicePrincipalSignInLog
    (or imported from a raw XML export) and renders them into a formatted Excel workbook.
    Enriches IP addresses with geolocation data when -IpInfo is enabled.

    .PARAMETER Log
    A list of service principal sign-in log objects with a metadata entry at index 0.
    Produced by Get-IRTServicePrincipalSignInLog. Mutually exclusive with -XmlPath.

    .PARAMETER XmlPath
    Path to a raw XML file exported by Get-IRTServicePrincipalSignInLog. Mutually
    exclusive with -Log.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER IpInfo
    Enrich IP addresses with geolocation data. Default: $true.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .OUTPUTS
    None. Results are written to an Excel workbook.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string]  $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string]  $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'CreatedDateTime'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Import-CliXml $Elapsed"
                [System.Collections.Generic.List[PSObject]]$Log =
                Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                $ErrorParams = @{
                    Category    = 'ReadError'
                    Message     = "Error importing from ${XmlPath}."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        #region Metadata
        if ($Log[0].Metadata) {
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + '.xlsx'

        # get worksheet title from metadata
        $WorksheetTitle = $Metadata.Title
    }

    process {

        #region ROW LOOP

        $RowCount = ($Log | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Row loop starting (${RowCount} rows) $Elapsed"
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $LogEntry = $Log[$i]

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }

            $ErrorDesc = ConvertTo-HumanErrorDescription -ErrorCode $LogEntry.Status.ErrorCode
            [void]$Rows.Add([PSCustomObject]@{
                    Raw                  = $Raw
                    $DateColumnHeader    = $DateTime
                    ServicePrincipalName = $LogEntry.ServicePrincipalName
                    AppDisplayName       = $LogEntry.AppDisplayName
                    ResourceDisplayName  = $LogEntry.ResourceDisplayName
                    Error                = $ErrorDesc
                    IpAddress            = $LogEntry.IpAddress
                    City                 = $LogEntry.Location.City
                    State                = $LogEntry.Location.State
                    Co                   = $LogEntry.Location.CountryOrRegion
                    Session              = $LogEntry.CorrelationId
                    Token                = $LogEntry.UniqueTokenIdentifier
                })

            if ($VerbosePreference -ne 'SilentlyContinue' -and ($i % 100 -eq 0)) {
                $Percent = [int]( ($i / $RowCount) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
            }
        }

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed
        }

        #region EXPORT SPREADSHEET

        Write-Verbose "${FunctionName}: Export-Excel $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $Metadata.FileNamePrefix
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-Error "Unable to open new Excel document."
            if ( Get-YesNo "Try closing open files." ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    throw "Unable to open new Excel document. Exiting."
                }
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($IpInfo) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Add-IpInfoToSheet $Elapsed"
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ($workSheet.Tables.Address | Select-Object -First 1).Start.Column |
            Convert-DecimalToExcelColumn
        $TableStartRow = ($workSheet.Tables.Address | Select-Object -First 1).Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $IpAddressColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'IpAddress' }).Id |
                Convert-DecimalToExcelColumn

        #region CELL COLORING

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'                 = 8
            $DateColumnHeader     = 26
            'ServicePrincipalName'= 30
            'AppDisplayName'      = 25
            'ResourceDisplayName' = 30
            'Error'               = 25
            'IpAddress'           = 20
            'City'                = 10
            'State'               = 10
            'Co'                  = 6
            'Session'             = 10
            'Token'               = 10
        }
        foreach ($ColName in $ColumnWidths.Keys) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
            if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
        }

        #region FORMATTING

        # set date format
        $FmtParams = @{
            Worksheet    = $Worksheet
            Range        = 'B:B'
            NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-ExcelRange @FmtParams

        # set text wrapping on ip address column
        $WrapParams = @{
            Worksheet = $Worksheet
            Range     = "${IpAddressColumn}:${IpAddressColumn}"
            WrapText  = $true
        }
        Set-ExcelRange @WrapParams

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = $Font
        }
        try {
            Set-ExcelRange @SetParams
        } catch {}

        # add left side border
        $BorderParams = @{
            Worksheet   = $Worksheet
            Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft  = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        # set row height
        for ($i = $TableStartRow; $i -le $EndRow; $i++) {
            $Row = $Worksheet.Row($i)
            $Row.Height = 15
            $Row.CustomHeight = $true
        }

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-IRT "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
#EndRegion '.\Public\Entra\Show-IRTServicePrincipalSignIn.ps1' 275
#Region '.\Public\Mailbox\Add-IRTMailboxFullAccess.ps1' -1

function Add-IRTMailboxFullAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('FullAccess')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo,

        [switch] $Remove
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $GrantAccessToList = [System.Collections.Generic.List[string]]::new()

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        # verify connected to exchange
        try {
            $Domain = Get-AcceptedDomain
        }
        catch {}
        if ( -not $Domain ) {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
    }

    process {

        #region CURRENT USER

        if ($GrantAccessTo) {
            # normalise to list
            [void]$GrantAccessToList.Add($GrantAccessTo)
        }
        else {
            try {
                $Accounts = @((Get-ConnectionInformation).UserPrincipalName)
            }
            catch {
                $_
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "${Function}: Unable to detect currently connected Exchange" +
                    ' account. Specify with -GrantAccessTo.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }

            # if not empty, add to list
            foreach ($a in $Accounts) {
                if (-not [string]::IsNullOrWhiteSpace($a)) {
                    [void]$GrantAccessToList.Add($a)
                }
            }
        }

        if ($GrantAccessToList.Count -lt 1) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "${Function}: Unable to detect currently connected Exchange" +
                ' account. Specify with -GrantAccessTo.'
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
        elseif ($GrantAccessToList.Count -gt 1) {

            # remove duplicates
            $HashSet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Object in $GrantAccessToList) { [void]$HashSet.Add($Object) }
            $GrantAccessToList = @($HashSet)

            # if more than one option, have user choose
            if ( $GrantAccessToList.Count -gt 1 ) {
                $MenuParams = @{
                    Title = "Choose account to receive full access to mailbox."
                    Options = $GrantAccessToList
                    List = $true
                }
                $GrantAccessTo = Build-Menu @MenuParams
            }
            else {
                $GrantAccessTo = $GrantAccessToList | Select-Object -First 1
            }
        }
        else {
            $GrantAccessTo = $GrantAccessToList | Select-Object -First 1
        }

        #region USER LOOP

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            if ($Remove) {
                # remove access
                Write-IRT "Removing access to ${UserEmail} from ${GrantAccessTo}"
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    Confirm = $false
                }
                $null = Remove-MailboxPermission @Params
            }
            else {
                # add access
                Write-IRT "Adding access to ${UserEmail} to ${GrantAccessTo}"
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    InheritanceType = 'All'
                }
                $null = Add-MailboxPermission @Params
            }

            # show users who have access to target mailbox
            Write-IRT "Showing users who have access to ${UserEmail}"
            $Properties = @(
                'User'
                'AccessRights'
                'IsInherited'
                'InheritanceType'
            )
            $MailboxPermissions = Get-MailboxPermission -Identity $UserEmail
            $MailboxPermissions | Format-Table $Properties -AutoSize
        }
    }
}
#EndRegion '.\Public\Mailbox\Add-IRTMailboxFullAccess.ps1' 180
#Region '.\Public\Mailbox\Get-IRTInboxRule.ps1' -1

function Get-IRTInboxRule {
    <#
    .SYNOPSIS
    Retrieves and displays Exchange Online inbox rules for one or more users.

    .DESCRIPTION
    Fetches all inbox rules for each provided user via Exchange Online and exports them
    to a formatted Excel workbook. Each rule row includes its enabled state, name,
    description, and a pre-built deletion command for quick remediation.

    Disabled rules are highlighted in the Excel output. Falls back to
    $Global:IRT_UserObjects if no -UserObject is passed. Requires an active Exchange
    Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Get-IRTInboxRule
    Retrieves and exports inbox rules for the user in the global session.

    .EXAMPLE
    Get-IRTInboxRule -UserObject $User
    Retrieves inbox rules for a specific user.

    .OUTPUTS
    None. Results are exported to an Excel file and optionally displayed in the console.

    .NOTES
    Version: 1.1.6
    1.1.6 - Added column borders, raw json. Fixed bugs.
    1.1.5 - Added rule to highlight disabled rules.
    #>
    [Alias('InboxRule', 'InboxRules')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $WorksheetName = 'InboxRules'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = Get-Date -Format $FileNameDateFormat
        $EventDateFormat = 'MM/dd/yy hh:mm:sstt'
        $EventDateString = Get-Date -Format $EventDateFormat
        $DisplayProperties = @(
            'Raw'
            'Enabled'
            'Name'
            'Description'
            'DeleteCommand'
        )

        # if user objects not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # get client domain name for file output
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            # get username
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # build file name
            $XmlOutputPath = "InboxRules_Raw_${DomainName}_${UserName}_${FileDateString}.xml"
            $ExcelOutputPath = "InboxRules_${DomainName}_${UserName}_${FileDateString}.xlsx"

            # build worksheet title
            $WorksheetTitle = "Inbox rules for ${UserEmail} as of ${EventDateString}"

            # get rules
            Write-IRT "Getting Inbox rules for ${UserEmail}"
            $OutputTable = Get-InboxRule -Mailbox $UserEmail
            if ( @( $OutputTable ).Count -eq 0 ) {
                Write-IRT "No inbox rules found for ${UserEmail}." -Level Warn
                continue
            }

            #region ROW LOOP

            for ($i = 0; $i -lt $OutputTable.Count; $i++) {

                $Row = $OutputTable[$i]

                # Raw
                $Raw = $Row | ConvertTo-Json -Depth 10
                $AddParams = @{
                    MemberType = 'NoteProperty'
                    Name       = 'Raw'
                    Value      = $Raw
                }
                $Row | Add-Member @AddParams

                # DeleteCommand
                $Identity = $Row.Identity
                $DeleteCommand = "Remove-InboxRule -Identity '${Identity}'"
                $AddMemberParams = @{
                    MemberType  = 'NoteProperty'
                    Name        = 'DeleteCommand'
                    Value       = $DeleteCommand
                }
                $Row | Add-Member @AddMemberParams
            }

            # strip working table down to just desired properties
            $OutputTable = $OutputTable | Select-Object $DisplayProperties

            # export raw data
            if ($Xml) {
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $RawOutputTable | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            #region EXPORT SHEET
            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorksheetName
                Title         = $WorksheetTitle
                TableStyle    = $TableStyle
                AutoSize      = $true
                FreezeTopRow  = $true
                Passthru      = $true
            }
            try {
                $Workbook = $OutputTable |
                    Select-Object $DisplayProperties |
                    Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to open new Excel document."
                if ( Get-YesNo "Try closing open files." ) {
                    try {
                        $Workbook = $OutputTable | Export-Excel @ExcelParams
                    }
                    catch {
                        throw "Unable to open new Excel document. Exiting."
                    }
                }
            }
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

            # get table ranges
            $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $WorkSheet.Dimension.Start.Row
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1
            #     ).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            $EnabledColumn = (
                $Worksheet.Tables[0].Columns |
                    Where-Object { $_.Name -eq 'Enabled' }
                ).Id | Convert-DecimalToExcelColumn
                $DescriptionColumn = (
                    $Worksheet.Tables[0].Columns |
                        Where-Object { $_.Name -eq 'Description' }
                    ).Id | Convert-DecimalToExcelColumn

                    #region CELL COLORING

                    # if enabled column is 'FALSE', make background blue
                    $EnabledRange = "${EnabledColumn}${TableStartRow}:${EnabledColumn}${EndRow}"
                    $CFParams = @{
                        Worksheet       = $WorkSheet
                        Address         = $EnabledRange
                        RuleType        = 'ContainsText'
                        ConditionValue  = 'FALSE'
                        BackgroundColor = 'LightBlue'
                    }
                    Add-ConditionalFormatting @CFParams

                    $DescRange = "${DescriptionColumn}${TableStartRow}" +
                    ":${DescriptionColumn}${EndRow}"

                    # if description column contains text, make background red
                    $Strings = @(
                        'phish'
                        'spam'
                        'compromise'
                        'hack'
                        'stolen'
                        'Conversation History'
                        'RSS Feeds'
                    )
                    foreach ( $String in $Strings ) {

                        $CFParams = @{
                            Worksheet       = $WorkSheet
                            Address         = $DescRange
                            RuleType        = 'ContainsText'
                            ConditionValue  = $String
                            BackgroundColor = 'LightPink'
                        }
                        Add-ConditionalFormatting @CFParams
                    }

                    # if description column CONTAINS text, make background BLUE
                    $Strings = @(
                        "move the message to folder 'Inbox'"
                    )
                    foreach ( $String in $Strings ) {
                        $CFParams = @{
                            Worksheet       = $WorkSheet
                            Address         = $DescRange
                            RuleType        = 'ContainsText'
                            ConditionValue  = $String
                            BackgroundColor = 'LightBlue'
                        }
                        Add-ConditionalFormatting @CFParams
                    }


                    #region COLUMN WIDTH

                    $ColumnWidths = @{
                        'Raw' = 8
                    }
                    foreach ($ColName in $ColumnWidths.Keys) {
                        $Col = ($Worksheet.Tables[0].Columns |
                                Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # set text wrapping in description column
            $WrappingParams = @{
                Worksheet = $Worksheet
                Range     = $DescRange
                WrapText  = $true
            }
            Set-ExcelRange @WrappingParams

            # set font and size
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            Set-ExcelRange @SetParams

            # add left side border
            $BorderParams = @{
                Worksheet = $Worksheet
                Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            #region OUTPUT

            # save and close
            Write-IRT "Exporting to: ${ExcelOutputPath}"
            if ( $Open ) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
#EndRegion '.\Public\Mailbox\Get-IRTInboxRule.ps1' 312
#Region '.\Public\Mailbox\Open-IRTMailboxInOwa.ps1' -1

function Open-IRTMailboxInOwa {
    <#
	.SYNOPSIS
	Opens user mailbox in OWA in a browser.

	.NOTES
	Version: 1.1.0
    1.1.0 - Added Clipboard option.
	#>
    [Alias('OpenMailbox')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [ValidateSet( 'msedge', 'chrome', 'firefox', 'brave', 'default' )]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $ToClipboard
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        # verify connected to exchange
        try {
            $null = Get-AcceptedDomain
        }
        catch {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
    }

    process {

        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            $OwaHost = if ($Global:IRT_Session.Environment -in @('GCC High', 'DoD', 'USGov')) {
                'outlook.office365.us'
            } else {
                'outlook.office.com'
            }
            $OWAUrl = "https://${OwaHost}/mail/${UserEmail}/?offline=disabled"

            [pscustomobject]@{
                OWAUrl = $OWAUrl
            }

            if (-not $ToClipboard) {
                $Params = @{
                    Browser = $Browser
                    Url = $OWAUrl
                }
                if ($Private) {
                    $Params['Private'] = $true
                }
                Open-Browser @Params
            }
        }

        if ($ToClipboard -and ($ScriptUserObjects | Measure-Object).Count -eq 1) {
            Set-Clipboard -Value $OWAUrl
            Write-IRT "OWA URL copied to clipboard."
        }
    }
}
#EndRegion '.\Public\Mailbox\Open-IRTMailboxInOwa.ps1' 108
#Region '.\Public\Mailbox\Remove-IRTMailboxFullAccess.ps1' -1

function Remove-IRTMailboxFullAccess {
    <#
	.SYNOPSIS
	Remove full access to the target user's mailbox

	.NOTES
	Version: 1.0.0
	#>
    [Alias('RemoveFullAccess')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo
    )

    begin {
        Update-IRTToken -Service 'Exchange'
    }

    process {

        $Params = @{
            Remove = $true
        }
        if ($UserObject) {
            $Params['UserObject'] = $UserObject
        }
        if ($GrantAccessTo) {
            $Params['GrantAccessTo'] = $GrantAccessTo
        }
        $Target = if ($UserObject) {
            ($UserObject | Select-Object -First 1).UserPrincipalName
        } else {
            $GrantAccessTo
        }
        if ($PSCmdlet.ShouldProcess($Target, 'Remove full mailbox access')) {
            Add-IRTMailboxFullAccess @Params
        }
    }
}
#EndRegion '.\Public\Mailbox\Remove-IRTMailboxFullAccess.ps1' 44
#Region '.\Public\Mailbox\Show-IRTMailbox.ps1' -1

function Show-IRTMailbox {
    <#
    .SYNOPSIS
    Displays mailbox properties.

    .DESCRIPTION
    Retrieves Exchange Online mailbox configuration and permissions for one or more users
    and displays the results in the console. Includes quota settings, forwarding rules,
    litigation hold status, and current mailbox permissions.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed. Requires an active
    Exchange Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Cached
    Use pre-cached Exchange data where available instead of making new API calls.

    .EXAMPLE
    Show-IRTMailbox
    Displays mailbox details for the user in the global session.

    .EXAMPLE
    Show-IRTMailbox -UserObject $User
    Displays mailbox details for a specific user.

    .OUTPUTS
    None. Results are displayed in the console.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('ShowMailbox')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $GuidPattern = '\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b'

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }
    }

    process {
        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # get user mailbox info
            $UserPrincipalName = $ScriptUserObject.UserPrincipalName
            try {
                $Params = @{
                    UserPrincipalName = $UserPrincipalName
                    PropertySets = 'All'
                    ErrorAction = 'Stop'
                }
                $Mailbox = Get-EXOMailbox @Params
            }
            catch {}
            if ( -not $Mailbox ) {
                Write-IRT "No mailbox for ${UserPrincipalName}" -Level Warn
                continue
            }

            # if forwarding address is GUID, look up user
            if ( $Mailbox.ForwardingAddress -match $GuidPattern ) {

                $UserGuid = $Mailbox.ForwardingAddress

                # get user object
                $Users = Request-GraphUser -Cached:$Cached
                $MatchingUser = $Users | Where-Object { $_.Id -eq $UserGuid }

                $ForwardingAddress = $MatchingUser.Mail
            }
            else {
                $ForwardingAddress = $Mailbox.ForwardingAddress
            }

            # convert dates to local
            try {
                $WhenCreatedLocal = $Mailbox.WhenCreatedUTC.ToLocalTime()
                $WhenChangedLocal = $Mailbox.WhenChangedUTC.ToLocalTime()
            }
            catch {}

            Write-IRT "Showing Mailbox information for: ${UserPrincipalName}"
            $OutputTable = [PSCustomObject]@{
                IsMailboxEnabled      = $Mailbox.IsMailboxEnabled
                AuditEnabled          = $Mailbox.AuditEnabled
                AuditLogAgeLimit      = $Mailbox.AuditLogAgeLimit
                DisplayName           = $Mailbox.DisplayName
                PrimarySmtpAddress    = $Mailbox.PrimarySmtpAddress
                EmailAddresses        = $Mailbox.EmailAddresses
                WhenCreated           = $WhenCreatedLocal
                WhenChanged           = $WhenChangedLocal
                ForwardingAddress     = $ForwardingAddress
                ForwardingSmtpAddress = $Mailbox.ForwardingSmtpAddress
                DeliverToMailboxAndForward = $Mailbox.DeliverToMailboxAndForward
                LitigationHoldEnabled = $Mailbox.LitigationHoldEnabled
                RetentionHoldEnabled = $Mailbox.RetentionHoldEnabled
                UsageLocation = $Mailbox.UsageLocation
            }
            $OutputTable | Format-List | Out-Host

            Write-IRT "Showing users who have delegated access to: ${UserPrincipalName}"
            $PermissionDisplayProperties = @(
                "User"
                "AccessRights"
                "IsInherited"
                "Deny"
                "InheritanceType"
            )
            $Permissions = Get-EXOMailboxPermission -Identity $UserPrincipalName
            $Permissions | Format-Table $PermissionDisplayProperties -AutoSize | Out-Host
        }
    }
}
#EndRegion '.\Public\Mailbox\Show-IRTMailbox.ps1' 148
#Region '.\Public\Mailbox\Show-IRTMailboxAccess.ps1' -1

function Show-IRTMailboxAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('MailboxAccess', 'ShowAccess', 'ShowFullAccess')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            # show users who have access to target mailbox
            Write-IRT "Showing users who have access to ${UserEmail}"
            $Properties = @(
                'User'
                'AccessRights'
                'IsInherited'
                'InheritanceType'
            )
            $MailboxPermissions = Get-MailboxPermission -Identity $UserEmail
            $MailboxPermissions | Format-Table $Properties -AutoSize
        }
    }
}
#EndRegion '.\Public\Mailbox\Show-IRTMailboxAccess.ps1' 73
#Region '.\Public\MessageTrace\Get-IRTMessageTrace.ps1' -1

function Get-IRTMessageTrace {
    <#
    .SYNOPSIS
    Downloads incoming and outgoing message trace for specified user, or all users.

    .DESCRIPTION
    Retrieves Exchange Online message trace records for one or more users over a configurable
    date range and exports results to Excel. Accepts user objects, email addresses, or an
    -AllUsers switch for tenant-wide queries.

    Supports both the modern V2 API (large result sets via background jobs) and the legacy
    V1 endpoint. Date range defaults to the last 10 days when no -Days, -Start, or -End
    is specified.

    .PARAMETER UserObject
    One or more user objects to trace. Mutually exclusive with -UserEmail and -AllUsers.
    Falls back to global session objects if omitted.

    .PARAMETER UserEmail
    One or more email addresses to trace. Mutually exclusive with -UserObject and -AllUsers.

    .PARAMETER AllUsers
    Query message trace for all users in the tenant. Mutually exclusive with -UserObject
    and -UserEmail.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER ResultLimit
    Maximum number of records to return. Default: 50000.

    .PARAMETER Variable
    Save results to a session variable for downstream use. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER Quiet
    Suppress progress output.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .EXAMPLE
    Get-IRTMessageTrace
    Downloads message trace for the user in the global session (last 10 days).

    .EXAMPLE
    Get-IRTMessageTrace -UserObject $User -Days 30
    Downloads 30 days of message trace for a specific user.

    .EXAMPLE
    Get-IRTMessageTrace -AllUsers -Start '2026-04-01' -End '2026-04-30'
    Downloads all tenant message trace for April 2026.

    .OUTPUTS
    None. Results are exported to Excel and stored in a session variable.

    .NOTES
    Version: 1.5.0
    1.5.0 - Integrated V1 and V2 into same function.
    1.4.0 - Switched to separate get/show functions. Updated to passing objects, not files.
        Added global variables.
    #>
    [Alias('MessageTrace')]
    [CmdletBinding( DefaultParameterSetName = 'UserObject' )]
    param (
        [Parameter(ParameterSetName = 'UserObject', Position = 0)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'UserEmail')]
        [Alias('UserEmails')]
        [string[]] $UserEmail,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [int] $Days, # default set at DEFAULTDAYS
        [string] $Start,
        [string] $End,

        [int] $ResultLimit = 50000,

        [boolean] $Variable = $true,
        [boolean] $Excel = $true,
        [switch] $Quiet,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'Received'
        $FileNamePrefix = 'MessageTrace'

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $ScriptUserObjects = Get-GlobalUserObject

                    # if none found, exit
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used, ' +
                            'no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'UserEmail' {
                # variables
                $ScriptUserObjects = [System.Collections.Generic.list[psobject]]::new()

                foreach ( $Email in $UserEmail ) {

                    # create object with userprincipalname property
                    $ScriptUserObjects.Add(
                        [pscustomobject]@{
                            UserPrincipalName = $Email
                        }
                    )
                }
            }
            'AllUsers' {
                # build user object with null principal name
                $ScriptUserObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = $null
                    }
                )
                $AllUsers = $true
            }
        }


        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = 10 #DEFAULTDAYS
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc

        #region VERIFY COMMAND
        # verify Get-MessageTraceV2 is available
        try {
            [void](Get-Command Get-MessageTraceV2 -ErrorAction 'Stop')
        }
        catch {
            # if there was an error, revert to V1
            $WarningParams = @{
                Message = 'Get-MessageTraceV2 command not available in this tenant or' +
                ' ExchangeOnlineManagement version. Running Get-MessageTrace instead.'
            }
            Write-Warning @WarningParams

            $V1 = $true

            # change date ranges to 10 days max
            if ($DateRangeType -eq 'Absolute') {
                $NowUtc = (Get-Date).ToUniversalTime()
                if ($StartDateUtc -lt $NowUtc.AddDays(-10)) {
                    $WarningParams = @{
                        Message = "-StartDate is more than 10 days ago. Changing to 10 days ago."
                    }
                    Write-Warning @WarningParams
                    $StartDateUtc = $NowUtc.AddDays(-10)
                }
                if ($EndDateUtc -le $StartDateUtc) {
                    $ErrorParams = @{
                        Category    = 'LimitsExceeded'
                        Message     = "-EndDate must be greater than -StartDate."
                        ErrorAction = 'Stop'
                    }
                    Write-Error @ErrorParams
                }
                # recalculate $Days to match the adjusted date range
                $Days = [Int]([Math]::Ceiling(($EndDateUtc - $StartDateUtc).TotalDays))
            }
            else {
                if ($Days -gt 10) {
                    $WarningParams = @{
                        Message = 'Get-MessageTrace can only search back 10 days.' +
                        ' Changing -Days to 10.'
                    }
                    Write-Warning @WarningParams
                    $Days = 10
                    $StartDateUtc = (Get-Date).AddDays(-10).ToUniversalTime()
                }
            }
        }

        # get client domain name for file output
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-AcceptedDomain $Elapsed"
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1
    }

    process {

        #region USER LOOP

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $AllMessages = [System.Collections.Generic.List[psobject]]::new()

            if ( $AllUsers ) {
                $UserName = 'AllUsers'
            }
            else {

                # verify user has mailbox. if not, exit.
                $Mailbox = $null
                try {
                    $Params = @{
                        UserPrincipalName = $ScriptUserObject.UserPrincipalName
                        ErrorAction       = 'Stop'
                    }
                    $Mailbox = Get-EXOMailbox @Params
                }
                catch {}
                if (-not $Mailbox) {
                    Write-IRT "No mailbox for $($ScriptUserObject.UserPrincipalName)" -Level Warn
                    if ($Global:IRT_WaitFlags) {
                        $Global:IRT_WaitFlags.MessageTraceUserDone = $true
                    }
                    continue
                }

                $UserName = $ScriptUserObject.UserPrincipalName -split '@' | Select-Object -First 1

                $LoopUserEmails = [System.Collections.Generic.HashSet[string]]::new()
                [void]$LoopUserEmails.Add($ScriptUserObject.UserPrincipalName)

                # get all user email addresses
                if (-not $ScriptUserObject.ProxyAddresses) {
                    $ScriptUserObject = $ScriptUserObject | Get-FullUserObject
                }

                $EmailPattern = "\b[a-zA-Z0-9\._%+-]+@([a-zA-Z0-9.-]+\.)[a-zA-Z]{2,6}\b"
                foreach ($p in $ScriptUserObject.ProxyAddresses) {
                    $e = $p | Select-String -Pattern $EmailPattern -AllMatches |
                        ForEach-Object { $_.Matches.Value }
                    if ($e) {
                        [void]$LoopUserEmails.Add($e)
                    }
                }
            }

            # build file name
            $FileNameDateFormat = "yy-MM-dd_HH-mm"
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $XmlOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileNameDateString}.xml"

            ### request message trace records
            if ( $AllUsers ) {

                Write-IRT "Getting message trace records for all users."
                [System.Collections.Generic.List[psobject]]$AllMessages = if ($V1) {
                    $Params = @{
                        StartDate   = $StartDateUtc
                        EndDate     = $EndDateUtc
                        ResultLimit = $ResultLimit
                        Quiet       = $Quiet
                    }
                    Request-MessageTraceV1 @Params
                }
                else {
                    $Params = @{
                        Days        = $Days #FIXME update to use start/end dates instead of days
                        ResultLimit = $ResultLimit
                        Quiet       = $Quiet
                    }
                    Request-MessageTrace @Params
                }
            }
            else {

                $InnerType = 'System.Collections.Generic.List[psobject]'
                $ListOfLists = New-Object "System.Collections.Generic.List[$InnerType]"

                foreach ($UserEmail in $LoopUserEmails) {
                    # get sender records
                    if (-not $Quiet) {
                        Write-IRT "Requesting message trace records with sender: ${UserEmail}"
                    }
                    $Messages = if ($V1) {
                        $Params = @{
                            SenderAddress = $UserEmail
                            StartDate     = $StartDateUtc
                            EndDate       = $EndDateUtc
                            ResultLimit   = $ResultLimit
                            Quiet         = $Quiet
                        }
                        Request-MessageTraceV1 @Params
                    }
                    else {
                        $Params = @{
                            SenderAddress = $UserEmail
                            # FIXME: update to use start/end dates instead of days
                            Days          = $Days
                            ResultLimit   = $ResultLimit
                            Quiet         = $Quiet
                        }
                        Request-MessageTrace @Params
                    }
                    if (($Messages | Measure-Object).Count -gt 0) {
                        $ListOfLists.Add([System.Collections.Generic.List[psobject]]@($Messages))
                    }
                    # get recipient records
                    if (-not $Quiet) {
                        Write-IRT "Requesting message trace records with recipient: ${UserEmail}"
                    }
                    $Messages = if ($V1) {
                        $Params = @{
                            RecipientAddress = $UserEmail
                            StartDate        = $StartDateUtc
                            EndDate          = $EndDateUtc
                            ResultLimit      = $ResultLimit
                            Quiet            = $Quiet
                        }
                        Request-MessageTraceV1 @Params
                    }
                    else {
                        $Params = @{
                            RecipientAddress = $UserEmail
                            # FIXME: update to use start/end dates instead of days
                            Days             = $Days
                            ResultLimit      = $ResultLimit
                            Quiet            = $Quiet
                        }
                        Request-MessageTrace @Params
                    }
                    if (($Messages | Measure-Object).Count -gt 0) {
                        $ListOfLists.Add([System.Collections.Generic.List[psobject]]@($Messages))
                    }
                }

                if ($ListOfLists.Count -eq 0) {
                    # exit if no messages returned
                    Write-IRT "0 total messages retrieved. Exiting." -Level Warn
                    if ($Global:IRT_WaitFlags) {
                        $Global:IRT_WaitFlags.MessageTraceUserDone = $true
                    }
                    continue
                }
                elseif ($ListOfLists.Count -eq 1) {
                    $AllMessages = $ListOfLists[0]
                }
                else {
                    # merge lists together
                    $MergeParams = @{
                        PropertyName = $RawDateProperty
                        Lists        = $ListOfLists
                        Descending   = $true
                    }
                    $AllMessages = [System.Collections.Generic.List[psobject]](
                        Merge-ListOnDate @MergeParams
                    )
                }
            }

            # exit if no messages found
            if (($AllMessages | Measure-Object).Count -eq 0) {
                Write-IRT "No messages found. Exiting." -Level Warn
                if ($Global:IRT_WaitFlags) {
                    if ($AllUsers) { $Global:IRT_WaitFlags.MessageTraceAllUsersDone = $true }
                    else { $Global:IRT_WaitFlags.MessageTraceUserDone = $true }
                }
                continue
            }

            #region METADATA

            # add metadata to results
            $StartDate = (Get-Date).AddDays($Days * -1)
            $EndDate = Get-Date
            $AllMessages.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    UserObject     = $ScriptUserObject
                    UserEmails     = $LoopUserEmails
                    UserName       = $UserName
                    StartDate      = $StartDate
                    EndDate        = $EndDate
                    Days           = $Days
                    DomainName     = $DomainName
                    FileNamePrefix = $FileNamePrefix
                }
            )

            #region OUTPUT

            # export to variables
            if ($Variable) {
                # build table by normalized InternetMessageId
                $Table = @{}
                foreach ($Message in $AllMessages) {
                    if (-not $Message.Metadata) {
                        $NormalizedId = ($Message.MessageId -replace '[<>]', '').Trim()
                        if ($NormalizedId) {
                            $Table[$NormalizedId] = $Message
                        }
                    }
                }

                # merge into global synchronized hashtable
                foreach ($Key in $Table.Keys) {
                    $Global:IRT_MessageTraceTable[$Key] = $Table[$Key]
                }
                if ($Global:IRT_WaitFlags) {
                    if ($AllUsers) { $Global:IRT_WaitFlags.MessageTraceAllUsersDone = $true }
                    else { $Global:IRT_WaitFlags.MessageTraceUserDone = $true }
                }
                Write-Verbose "${FunctionName}: Table key count: $($Table.Count)"
            }

            # export raw data
            if ($Xml) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Export-CliXml $Elapsed"
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $AllMessages | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            if ($Script) {
                Write-Output $AllMessages
                return
            }

            # create excel sheet
            if ($Excel) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Show-IRTMessageTrace $Elapsed"
                $Params = @{
                    Messages   = $AllMessages
                    TableStyle = $TableStyle
                    Font       = $Font
                }
                Show-IRTMessageTrace @Params
            }
        }
    }
}
#EndRegion '.\Public\MessageTrace\Get-IRTMessageTrace.ps1' 479
#Region '.\Public\MessageTrace\Show-IRTMessageTrace.ps1' -1

function Show-IRTMessageTrace {
    <#
	.SYNOPSIS
	Processes message trace data and creates spreadsheet.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding( DefaultParameterSetName = 'Objects' )]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ParameterSetName = 'Objects')]
        [Alias('Messages')]
        [System.Collections.Generic.List[PSObject]] $Message,

        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $TitleDateFormat = "M/d/yy h:mmtt"
        $RawDateProperty = 'Received'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Import-CliXml $Elapsed"
                $Message = [System.Collections.Generic.List[PSObject]](
                    Import-CliXml -Path $ResolvedXmlPath
                )
            }
            catch {
                $_
                Write-IRT "Error importing from ${XmlPath}." -Level Error
                return
            }
        }

        # import metadata
        if ($Message[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Message[0]
            $Message.RemoveAt(0)

            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
            $FileNamePrefix = $Metadata.FileNamePrefix
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # exit if no messages found
        if (($Message | Measure-Object).Count -eq 0) {
            Write-IRT "No messages found. Exiting" -Level Error
            return
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $StartString = $StartDate.ToString($TitleDateFormat).ToLower()
        $EndString = $EndDate.ToString($TitleDateFormat).ToLower()
        if ($null -eq $Username) {
            $WorksheetTitle = "Message Trace for ${DomainName}. Covers ${Days} days," +
            " from ${StartString} to ${EndString}."
        }
        else {
            $WorksheetTitle = "Message Trace for ${Username}. Covers ${Days} days," +
            " from ${StartString} to ${EndString}."
        }
    }

    process {
        # exit if no messages
        if (($Message | Measure-Object).Count -eq 0) {
            Write-IRT "No messages. Exiting." -Level Error
        }

        #region ROW LOOP

        $RowCount = $Message.Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Row loop starting (${RowCount} rows) $Elapsed"
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $m = $Message[$i]

            # Raw
            $Raw = $m | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($m.$RawDateProperty) {
                $DateTime = $m.$RawDateProperty.ToLocalTime()
            }

            $Rows.Add([pscustomobject]@{
                    Raw               = $Raw
                    $DateColumnHeader = $DateTime
                    Status            = $m.Status
                    SenderAddress     = $m.SenderAddress
                    RecipientAddress  = $m.RecipientAddress
                    Subject           = $m.Subject
                    FromIP            = $m.FromIP
                    ToIP              = $m.ToIP
                    MessageTraceId    = $m.MessageTraceId
                    MessageId         = $m.MessageId
                })

            if ($VerbosePreference -ne 'SilentlyContinue' -and ($i % 1000 -eq 0)) {
                $Percent = [int]( ($i / $RowCount ) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
            }
        }

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed
        }

        #region EXPORT EXCEL
        Write-Verbose "${FunctionName}: Export-Excel $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $FileNamePrefix
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            # AutoSize      = $true # apparently very slow?
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            $_
            Write-IRT "Error while opening Excel document." -Level Error
            if ( Get-YesNo "Try again?" ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    $_
                    Write-IRT "Error while opening Excel document. Exiting." -Level Error
                    return
                }
            }
            else {
                return
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($IpInfo) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Add-IpInfoToSheet $Elapsed"
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'FromIP', 'ToIP'
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = (
            $Worksheet.Tables.Address | Select-Object -First 1
        ).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ($Worksheet.Tables | Select-Object -First 1).Address.Start.Row + 1
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $SenderColumn = (
            $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'SenderAddress' }
        ).Id | Convert-DecimalToExcelColumn
        $RecipientColumn = (
            $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'RecipientAddress' }
        ).Id | Convert-DecimalToExcelColumn

        #region BOLD OTHER EMAIL

        # FIXME idea here was to make it clearer at a glance whether the email was sent or
        # received by the user. Not sure if this is the best way though.

        # if ($UserEmails) {
        #     # helper: make "=AND(LEN($A2)>0, $A2<>\"me1\", $A2<>\"me2\", ...)" for
        #     #     a column's anchor cell
        #     function New-CfNotMeFormula {
        #         param([Parameter(Mandatory)][string]$ColumnLetter,
        #             [Parameter(Mandatory)][int]$StartRow)

        #         # anchor column absolute, row relative: $A2
        #         $anchor = "`$${ColumnLetter}$StartRow"

        #         # comparisons: $A2<> "alias"
        #         $comparisons = $UserEmails.ForEach({
        #             '{0}<>""{1}""' -f $anchor, ($_ -replace '"','""')
        #         })

        #         # skip blanks, and only bold when value is not any of my addresses
        #         return '=AND(LEN({0})>0,{1})' -f $anchor, ($comparisons -join ',')
        #     }

        #     # sender column rule
        #     $FormulaSender = New-CfNotMeFormula -ColumnLetter $SenderColumn
        #         -StartRow $TableStartRow
        #     $CfParamsSender = @{
        #         WorkSheet      = $Worksheet
        #         Address        = "${SenderColumn}${TableStartRow}:${SenderColumn}${EndRow}"
        #         RuleType       = 'Expression'
        #         ConditionValue = $FormulaSender
        #         Bold           = $true
        #     }
        #     Add-ConditionalFormatting @CfParamsSender

        #     # recipient column rule
        #     $FormulaRecipient = New-CfNotMeFormula -ColumnLetter $RecipientColumn
        #         -StartRow $TableStartRow
        #     $CfParamsRecipient = @{
        #         WorkSheet      = $Worksheet
        #         Address        = "${RecipientColumn}${TableStartRow}:${RecipientColumn}${EndRow}"
        #         RuleType       = 'Expression'
        #         ConditionValue = $FormulaRecipient
        #         Bold           = $true
        #     }
        #     Add-ConditionalFormatting @CfParamsRecipient
        # }

        #region SAME TO/FROM

        $CfParams = @{
            WorkSheet        = $Worksheet
            Address          = "${SenderColumn}${TableStartRow}:${RecipientColumn}${EndRow}"
            RuleType         = 'Expression'
            ConditionValue   = "=`$${SenderColumn}${TableStartRow}" +
            "=`$${RecipientColumn}${TableStartRow}"
            BackgroundColor  = 'LightYellow'
        }
        Add-ConditionalFormatting @CfParams

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'              = 8
            $DateColumnHeader  = 26
            'Status'           = 15
            'SenderAddress'    = 30
            'RecipientAddress' = 30
            'Subject'          = 100
            'FromIp'           = 20
            'ToIp'             = 20
            'MessageTraceId'   = 200
        }
        foreach ($ColName in $ColumnWidths.Keys) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
            if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
        }

        #region FORMATTING

        # set date format
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-ExcelRange @FmtParams

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = $Font
        }
        Set-ExcelRange @SetParams

        # add left side border
        $BorderParams = @{
            Worksheet = $Worksheet
            Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        $Workbook | Close-ExcelPackage -Show
    }
}
#EndRegion '.\Public\MessageTrace\Show-IRTMessageTrace.ps1' 313
#Region '.\Public\OnPremAd\Copy-IRTFunction.ps1' -1

function Copy-IRTFunction {
    <#
    .SYNOPSIS
    Copies IRT helper functions to the clipboard for use on remote machines.

    .DESCRIPTION
    Retrieves function definitions from the loaded module in memory and
    concatenates them into a single pasteable script, then sends the result
    to the clipboard via Set-Clipboard.

    A bootstrap block that initialises $Global:IRT_Config (using the current
    session's color preferences as defaults) is prepended automatically.

    The default set includes:
      - Write-IRT, Get-RandomPassword
      - Format-Tree and all of its private helpers
      - All On-Prem AD functions

    Use -FunctionName to include additional functions beyond the default set.

    .PARAMETER FunctionName
    One or more additional function names to include beyond the default set.
    Accepts pipeline input.

    .EXAMPLE
    Copy-IRTFunction

    Copies the default set of IRT helper functions to the clipboard.

    .EXAMPLE
    Copy-IRTFunction -FunctionName 'Get-IRTMessageTrace'

    Copies the default set plus Get-IRTMessageTrace.

    .EXAMPLE
    'Get-IRTInboxRule', 'Get-IRTMessageTrace' | Copy-IRTFunction

    Copies the default set plus both named functions via the pipeline.

    .OUTPUTS
    None. Output is sent to the clipboard.

    .NOTES
    Version: 2.0.0

    #>
    [Alias(
        'Copy-IRTFunctions', 'CopyIRTFunctions', 'CopyIRTFunction', 'IRTFunction', 'IRTFunctions')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]] $FunctionName
    )

    begin {
        $DefaultFunctions = @(
            # Core helpers
            'Write-IRT'
            'Get-RandomPassword'
            # Format-Tree and its private helpers (all compiled into the module)
            'Format-Tree'
            'Get-Indent'
            'Get-PropertyName'
            'Out-Print'
            'Resolve-Json'
            'Test-HasVisible'
            'Test-IsEmptyScalar'
            'Test-IsScalar'
            'Write-NameEllipsis'
            'Write-NameValue'
            # On-prem AD functions
            'Disable-IRTAdUser'
            'Enable-IRTAdUser'
            'Find-IRTAdDevice'
            'Find-IRTAdOu'
            'Find-IRTAdUser'
            'Find-IRTDomainController'
            'Get-IRTAdAdminUser'
            'Push-IRTAdSync'
            'Reset-IRTAdUserPassword'
            'Show-IRTAdDevice'
            'Show-IRTAdOus'
            'Show-IRTAdUser'
        )

        $Queue = [System.Collections.Generic.List[string]]::new()
        foreach ($F in $DefaultFunctions) { $Queue.Add($F) }
    }

    process {
        foreach ($F in $FunctionName) {
            if ($Queue -notcontains $F) { $Queue.Add($F) }
        }
    }

    end {
        # Resolve current color values (or fallbacks) at copy-time so the pasted
        # code carries the user's preferences onto the remote machine.
        $infoColor = if ($Global:IRT_Config?.InfoColor) {
            $Global:IRT_Config.InfoColor
        } else { 'DarkCyan' }
        $warnColor = if ($Global:IRT_Config?.WarnColor) {
            $Global:IRT_Config.WarnColor
        } else { 'Yellow' }
        $errorColor = if ($Global:IRT_Config?.ErrorColor) {
            $Global:IRT_Config.ErrorColor
        } else { 'Red' }

        $Bootstrap = @"
if (-not `$Global:IRT_Config) {
    `$Global:IRT_Config = [PSCustomObject]@{
        InfoColor  = '$infoColor'
        WarnColor  = '$warnColor'
        ErrorColor = '$errorColor'
    }
}
"@

        $Builder = [System.Text.StringBuilder]::new()
        $null = $Builder.AppendLine($Bootstrap)

        $Resolved = 0
        foreach ($Name in $Queue) {
            $GcParams = @{
                Name        = $Name
                CommandType = 'Function'
                ErrorAction = 'SilentlyContinue'
            }
            $Cmd = Get-Command @GcParams
            if (-not $Cmd) {
                Write-IRT "Function not found in session: $Name" -Level Warn
                continue
            }
            $null = $Builder.AppendLine("function $Name {")
            $null = $Builder.AppendLine($Cmd.Definition)
            $null = $Builder.AppendLine('}')
            $null = $Builder.AppendLine()
            $Resolved++
        }

        if ($Resolved -eq 0) {
            Write-IRT 'No functions could be resolved.' -Level Warn
            return
        }

        $FmtParams = @{
            Content    = $Builder.ToString()
            Script     = $true
            Comments   = $true
            EmptyLines = $true
            Whitespace = $true
        }
        $Formatted = Format-Powershell @FmtParams
        Set-Clipboard -Value $Formatted
        Write-IRT "Copied $Resolved function(s) to clipboard."
    }
}
#EndRegion '.\Public\OnPremAd\Copy-IRTFunction.ps1' 159
#Region '.\Public\OnPremAd\Disable-IRTAdUser.ps1' -1

function Disable-IRTAdUser {
    <#
    .SYNOPSIS
    Disable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $false. Disables one or
    more AD user accounts, re-fetches each account to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to disable. Falls back to global session objects if omitted.

    .EXAMPLE
    Disable-IRTAdUser
    Disables the user(s) in the global session.

    .EXAMPLE
    Disable-IRTAdUser -UserObject $AdUser
    Disables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias(
        'Disable-IRTAdUsers',
        'Disable-AdUser', 'Disable-AdUsers',
        'DisableIRTAdUser', 'DisableIRTAdUsers',
        'DisableAdUser', 'DisableAdUsers',
        'Lock-IRTAdUser', 'Lock-IRTAdUsers',
        'Lock-AdUser', 'Lock-AdUsers',
        'LockIRTAdUser', 'LockIRTAdUsers',
        'LockAdUser', 'LockAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-AdUserEnabled @Params
}
#EndRegion '.\Public\OnPremAd\Disable-IRTAdUser.ps1' 56
#Region '.\Public\OnPremAd\Enable-IRTAdUser.ps1' -1

function Enable-IRTAdUser {
    <#
    .SYNOPSIS
    Enable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $true. Re-enables one or
    more disabled AD user accounts, re-fetches each to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to enable. Falls back to global session objects if omitted.

    .EXAMPLE
    Enable-IRTAdUser
    Re-enables the user(s) in the global session.

    .EXAMPLE
    Enable-IRTAdUser -UserObject $AdUser
    Re-enables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias(
        'Enable-IRTAdUsers',
        'Enable-AdUser', 'Enable-AdUsers',
        'EnableIRTAdUser', 'EnableIRTAdUsers',
        'EnableAdUser', 'EnableAdUsers',
        'Unlock-IRTAdUser', 'Unlock-IRTAdUsers',
        'Unlock-AdUser', 'Unlock-AdUsers',
        'UnlockIRTAdUser', 'UnlockIRTAdUsers',
        'UnlockAdUser', 'UnlockAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-AdUserEnabled @Params
}
#EndRegion '.\Public\OnPremAd\Enable-IRTAdUser.ps1' 56
#Region '.\Public\OnPremAd\Find-IRTAdDevice.ps1' -1

function Find-IRTAdDevice {
    <#
    .SYNOPSIS
    Finds a local AD computer by Name, DNSHostName, SamAccountName, Description,
    or ObjectGUID.

    .DESCRIPTION
    Searches Active Directory for computers matching one or more search strings. The search
    is applied across Name, DNSHostName, SamAccountName, Description, and ObjectGUID.

    If a single computer is found, the full AD object is retrieved and stored in
    $Global:IRT_DeviceObject. Use -VarPrefix to change the variable name
    (e.g. 'Target' > $Global:IRT_TargetDeviceObject). For multiple matches the results are
    displayed but no global is set. Use -Script to suppress global side effects and
    return objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER VarPrefix
    Optional prefix inserted after 'IRT_' in the global variable name
    (e.g. 'Target' > $Global:IRT_TargetDeviceObject). Useful when working with multiple
    devices simultaneously.

    .PARAMETER Script
    Return objects directly and suppress global variable assignment. Use when calling from
    scripts or the playbook.

    .EXAMPLE
    Find-IRTAdDevice DESKTOP-ABC123
    Finds computers matching 'DESKTOP-ABC123' and sets the global device object if exactly
    one match.

    .EXAMPLE
    Find-IRTAdDevice desktop-abc123.contoso.com
    Searches by DNS host name.

    .EXAMPLE
    $Devices = Find-IRTAdDevice -Search 'DESKTOP-ABC123','LAPTOP-XYZ789' -Script
    Returns matching computer objects for two search strings without setting globals.

    .OUTPUTS
    None by default (sets global variables).
    Microsoft.ActiveDirectory.Management.ADComputer[] when -Script is used.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Find-IRTAdDevices',
        'Find-AdDevice', 'Find-AdDevices',
        'FindIRTAdDevice', 'FindIRTAdDevices',
        'FindAdDevice', 'FindAdDevices'
    )]
    [OutputType([System.Collections.Generic.List[psobject]])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script
    )

    begin {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $ScriptDeviceObjects = [System.Collections.Generic.List[PsObject]]::new()
        $GetProperties = @(
            'DNSHostName'
            'Enabled'
            'Name'
            'ObjectGUID'
            'OperatingSystem'
            'OperatingSystemVersion'
            'SamAccountName'
            'servicePrincipalName '
        )
        $DisplayProperties = @(
            'Enabled'
            'Name'
            'SamAccountName'
            'DNSHostName'
            'OperatingSystem'
            'ObjectGUID'
        )

        $Computers = Get-AdComputer -Filter * -Property $GetProperties
    }

    process {

        foreach ($SearchString in $Search) {

            $MatchingComputers = [System.Collections.Generic.List[PsObject]]::new()

            foreach ($Computer in $Computers) {

                if ( $Computer.Name -match $SearchString -or
                    $Computer.DNSHostName -match $SearchString -or
                    $Computer.SamAccountName -match $SearchString -or
                    $Computer.servicePrincipalName -match $SearchString -or
                    $Computer.ObjectGUID -match $SearchString
                ) {
                    $MatchingComputers.Add( $Computer )
                }
            }

            if (($MatchingComputers | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingComputers | Format-Table $DisplayProperties
                }

                $FullDeviceObject = Get-AdComputer -Identity $MatchingComputers[0] -Property *

                $ScriptDeviceObjects.Add( ( $FullDeviceObject | Select-Object -First 1 ) )
            }
            elseif (($MatchingComputers | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingComputers | Format-Table $DisplayProperties
                    Write-IRT 'Multiple computers found. Refine search.' -Level Error
                }
            }
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        if ($Script) {
            return $ScriptDeviceObjects
        }

        if (($ScriptDeviceObjects | Measure-Object).Count -eq 1) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}DeviceObject"
                Value = $ScriptDeviceObjects | Select-Object -First 1
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$Global:IRT_${VarPrefix}DeviceObject"
        }
        elseif (($ScriptDeviceObjects | Measure-Object).Count -gt 1) {

            Write-IRT 'Multiple computers found. Refine search.' -Level Error
            $ScriptDeviceObjects | Format-Table $DisplayProperties
        }
    }
}
#EndRegion '.\Public\OnPremAd\Find-IRTAdDevice.ps1' 164
#Region '.\Public\OnPremAd\Find-IRTAdOu.ps1' -1

function Find-IRTAdOu {
    <#
    .SYNOPSIS
    Makes finding specific OUs easier.

    .DESCRIPTION
    Searches all Active Directory Organizational Units for entries matching the -Search
    string. The search is applied against Name (regex), CanonicalName (exact), and
    DistinguishedName (exact). If exactly one match is found it is stored in
    $Global:OuObject and displayed; multiple or zero results produce a warning.

    .PARAMETER Search
    String to search for. Tested as a regex against Name and as an exact match against
    CanonicalName and DistinguishedName.

    .PARAMETER Script
    Return the matching OU object directly instead of printing it and setting the global
    variable. Useful when calling from scripts.

    .EXAMPLE
    Find-IRTAdOu 'Workstations'
    Finds all OUs with 'Workstations' in their name and sets $Global:OuObject if exactly one match.

    .EXAMPLE
    $Ou = Find-IRTAdOu -Search 'contoso.com/Workstations' -Script
    Returns the OU object directly for use in a script.

    .OUTPUTS
    None by default (sets $Global:OuObject and writes to console).
    Microsoft.ActiveDirectory.Management.ADOrganizationalUnit when -Script is used.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Find-IRTAdOus',
        'Find-AdOu', 'Find-AdOus',
        'FindIRTAdOu', 'FindIRTAdOus',
        'FindAdOu', 'FindAdOus'
    )]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string] $Search,
        [switch] $Script
    )

    begin {
        $Properties = @(
            'Name'
            'CanonicalName'
            'DistinguishedName'
        )
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # find users whos displayname or email matches search
        $Ous = Get-ADOrganizationalUnit -Filter * -Properties $Properties

        # find matching ous
        $MatchingOus = $Ous | Where-Object {
            $_.Name -match $Search -or
            $_.CanonicalName -eq $Search -or
            $_.DistinguishedName -eq $Search
        }

        # if one ou found
        if (@($MatchingOus).Count -eq 1) {
            if ($Script) {
                # return object
                return $MatchingOus
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties

                # set variable
                New-Variable -Name "OuObject" -Value $MatchingOus -Scope 'Global'
                Write-IRT "Created `$Global:OuObject."
            }
        }
        # if multiple ous found
        elseif (@($MatchingOus).Count -gt 1) {
            if ($Script) {

                # show ou info
                $MatchingOus | Format-Table $Properties | Out-Default

                # tell user to try again
                Write-IRT 'Multiple Ous found. Search again.' -Level Error
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties

                # tell user to try again
                Write-IRT 'Multiple Ous found. Search again.' -Level Error
            }
        }
        # if no users found, tell user to search again
        else {
            if ($Script) {
                # tell user to try again
                Write-IRT "$Search not found. Try a different search." -Level Error
            }
            else {
                # tell user to try again
                Write-IRT "$Search not found. Try a different search." -Level Error
            }
        }
    }
}
#EndRegion '.\Public\OnPremAd\Find-IRTAdOu.ps1' 121
#Region '.\Public\OnPremAd\Find-IRTAdUser.ps1' -1

function Find-IRTAdUser {
    <#
    .SYNOPSIS
    Finds local AD user by DisplayName, Name, UserPrincipalName, ProxyAddresses,
    SamAccountName, or ObjectGUID.

    .DESCRIPTION
    Searches Active Directory for users matching one or more search strings. The search is
    applied across DisplayName, Name, UserPrincipalName, ProxyAddresses (email extracted
    by regex), SamAccountName, and ObjectGUID.

    If a single user is found, the full AD object is retrieved and stored in
    $Global:IRT_UserObject. Use -VarPrefix to change the variable name
    (e.g. 'Admin' > $Global:IRT_AdminUserObject). For multiple matches the results are
    displayed but no global is set. Use -Script to suppress global side effects and
    return objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER VarPrefix
    Optional prefix inserted after 'IRT_' in the global variable name
    (e.g. 'Admin' > $Global:IRT_AdminUserObject). Useful when working with multiple users
    simultaneously.

    .PARAMETER Script
    Return objects directly and suppress global variable assignment. Use when calling from
    scripts or the playbook.

    .EXAMPLE
    Find-IRTAdUser flast
    Finds users matching 'flast' and sets the global user object if exactly one match.

    .EXAMPLE
    Find-IRTAdUser flast@contoso.com
    Searches by email address.

    .EXAMPLE
    $Users = Find-IRTAdUser -Search 'flast','jsmith' -Script
    Returns matching user objects for two search strings without setting globals.

    .OUTPUTS
    None by default (sets global variables).
    Microsoft.ActiveDirectory.Management.ADUser[] when -Script is used.

    .NOTES
    Version: 1.2.1
    1.2.1 - Fixed bug where script was passing collections of user objects rather than user objects.
    1.2.0 - Major rewrite.
    #>
    [Alias(
        'Find-IRTAdUsers',
        'Find-AdUser', 'Find-AdUsers',
        'FindIRTAdUser', 'FindIRTAdUsers',
        'FindAdUser', 'FindAdUsers'
    )]
    [OutputType([System.Collections.Generic.List[psobject]])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script
    )

    begin {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
        $GetProperties = @(
            'DisplayName'
            'Enabled'
            'Name'
            'ObjectGUID'
            'ProxyAddresses'
            'SamAccountName'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'Enabled'
            'DisplayName'
            'Name'
            'SamAccountName'
            'UserPrincipalName'
            'ObjectGUID'
        )
        $EmailPattern = "[A-Za-z0-9._%+-]{1,63}@(?:[A-Za-z0-9.-]+\.)+[A-Za-z]{2,6}"

        # find users whos displayname or email matches search
        $Users = Get-AdUser -Filter * -Property $GetProperties
    }

    process {

        foreach ($SearchString in $Search) {

            $MatchingUsers = [System.Collections.Generic.List[PsObject]]::new()

            # find matching users
            foreach ($User in $Users) {

                # extract emails from proxy addresses
                $ProxyEmails = $User.ProxyAddresses |
                    Select-String -Pattern $EmailPattern -AllMatches |
                    ForEach-Object { $_.Matches.Value }

                # if matching, add to list
                if ( $User.DisplayName -match $SearchString -or
                    $User.Name -match $SearchString -or
                    $User.UserPrincipalName -match $SearchString -or
                    $ProxyEmails -match $SearchString -or
                    $User.SamAccountName -match $SearchString -or
                    $User.ObjectGUID -match $SearchString
                ) {
                    $MatchingUsers.Add( $User )
                }
            }

            if (($MatchingUsers | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                # get full user object
                $FullUserObject = Get-AdUser -Identity $MatchingUsers[0] -Property *

                # add user to array
                $ScriptUserObjects.Add( ( $FullUserObject | Select-Object -First 1 ) )
            }
            elseif (($MatchingUsers | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                    Write-IRT 'Multiple users found. Refine search.' -Level Error
                }
            }
            # if no users found
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return $ScriptUserObjects
        }

        # if one user
        if (($ScriptUserObjects | Measure-Object).Count -eq 1) {

            # set objects
            $VariableParams = @{
                Name  = "IRT_${VarPrefix}UserObject"
                Value = $ScriptUserObjects | Select-Object -First 1
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$Global:IRT_${VarPrefix}UserObject"
        }
        elseif (($ScriptUserObjects | Measure-Object).Count -gt 1) {

            Write-IRT 'Multiple users found. Refine search.' -Level Error
            $ScriptUserObjects | Format-Table $DisplayProperties
        }
    }
}
#EndRegion '.\Public\OnPremAd\Find-IRTAdUser.ps1' 183
#Region '.\Public\OnPremAd\Find-IRTDomainController.ps1' -1

function Find-IRTDomainController {
    <#
    .SYNOPSIS
    Lists the names of all domain controllers in the current AD domain.

    .DESCRIPTION
    Queries Active Directory for all domain controllers via Get-ADDomainController
    and returns their computer names. Requires the ActiveDirectory RSAT module and
    a reachable domain controller; exits with an error if AD is unavailable.

    .EXAMPLE
    Find-IRTDomainController
    Returns the Name of every domain controller in the domain.

    .EXAMPLE
    $DCs = Find-IRTDomainController
    Captures the list of DC names for use in a loop or downstream command.

    .OUTPUTS
    Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
    #>
    [Alias(
        # DomainController
        'FindIRTDomainController', 'Find-IRTDomainControllers', 'FindIRTDomainControllers',
        'Find-DomainController', 'FindDomainController',
        'Find-DomainControllers', 'FindDomainControllers',
        # DC
        'Find-DC', 'FindDC', 'Find-DCs', 'FindDCs',
        'DC', 'DCs'
    )]
    param()

    if ( -not ( Test-AdAvailable ) ) {
        Write-Error 'ActiveDirectory RSAT module not available.'
        return
    }

    Get-ADDomainController -Filter * | Select-Object Name
}
#EndRegion '.\Public\OnPremAd\Find-IRTDomainController.ps1' 40
#Region '.\Public\OnPremAd\Get-IRTAdAdminUser.ps1' -1

function Get-IRTAdAdminUser {
    <#
    .SYNOPSIS
    Displays a list of admin users.

    .DESCRIPTION
    Retrieves all Active Directory users where AdminCount equals 1 (the standard AD
    attribute set by SDProp for accounts that have been members of privileged groups).
    Results are sorted by Enabled status then LastLogonDate descending, and include each
    user's group memberships.

    Use -Csv to export the results to a CSV file in C:\Temp.

    .PARAMETER Csv
    Export results to a CSV file instead of displaying them in the console.

    .EXAMPLE
    Get-IRTAdAdminUser
    Displays all AdminCount=1 users in a formatted table.

    .EXAMPLE
    Get-IRTAdAdminUser -Csv
    Exports the list to AdAdminUsers_<domain>_<date>.csv in C:\Temp.

    .OUTPUTS
    None (console table) by default.
    CSV file when -Csv is used.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Get-IRTAdAdminUsers',
        'Get-AdAdminUser', 'Get-AdAdminUsers',
        'GetIRTAdAdminUser', 'GetIRTAdAdminUsers',
        'GetAdAdminUser', 'GetAdAdminUsers',
        'GetAdAdmins', 'AdAdmins'
    )]
    [CmdletBinding()]
    param (
        [switch] $Csv
    )

    begin {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $CustomObjects = [System.Collections.Generic.List[PSObject]]::new()
        $AdminUsers = Get-ADUser -Filter { AdminCount -eq 1 } -Property *
        $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $DomainName = $Domain.Forest -split '\.' | Select-Object -First 1
        $DateString = Get-Date -Format "yy-MM-dd"
        $ExportFileName = "AdAdminUsers_${DomainName}_${DateString}.csv"
        $ExportPath = Join-Path -Path "${env:SystemDrive}\Temp\" -ChildPath $ExportFileName
    }

    process {

        # sort users by enabled then last log on
        $AdminUsers = $AdminUsers | Sort-Object Enabled, LastLogOnDate -Descending

        foreach ( $User in $AdminUsers ) {

            # get group display names
            $UserGroups = ( $User.MemberOf | Get-AdGroup ).Name | Sort-Object

            # check for last logondate before trying to convert to local time to avoid errors
            if ( $User.LastLogOnDate ) {
                $LastLogOnDate = $User.LastLogOnDate.ToLocalTime()
            }
            else {
                $LastLogOnDate = $null
            }

            # create custom object for user
            $CustomObject = [pscustomobject]@{
                Enabled           = $User.Enabled
                LastLogOnDate     = $LastLogOnDate
                DisplayName       = $User.DisplayName
                SamAccountName    = $User.SamAccountName
                UserPrincipalName = $User.UserPrincipalName
                MemberOf          = $UserGroups -join ', '
                DistinguishedName = $User.DistinguishedName
            }
            $CustomObjects.Add( $CustomObject )
        }

        # show table in terminal
        $CustomObjects | Format-Table -AutoSize

        # if csv, output table to file
        if ( $Csv ) {
            Write-IRT "Exporting CSV to: ${ExportPath}"
            $CustomObjects | Export-Csv -Path $ExportPath -NoTypeInformation
        }
    }
}
#EndRegion '.\Public\OnPremAd\Get-IRTAdAdminUser.ps1' 102
#Region '.\Public\OnPremAd\Push-IRTAdSync.ps1' -1

function Push-IRTAdSync {
    <#
    .SYNOPSIS
    Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle.

    .DESCRIPTION
    Triggers an AD-to-Entra delta sync as quickly as possible. The execution path is:

    1. If running on a domain controller, fires 'repadmin /syncall /AdeP' to force
       intra-AD replication first.
    2. If the ADSync service is running locally, invokes Start-ADSyncSyncCycle directly
       and exits.
    3. Otherwise, discovers candidate servers (DCs first, then other enabled AD computers
       by last logon) in parallel using a runspace pool and invokes the sync cycle
       remotely on the first server found to have the service.

    Domain admin credentials are cached in $Global:Storage for the session.
    Use -ResetCredentials to force a re-prompt.

    .PARAMETER ResetCredentials
    Clear the cached domain admin credentials and prompt again before connecting.

    .PARAMETER SyncServer
    Target one or more specific server names directly, bypassing AD discovery.

    .PARAMETER ThrottleLimit
    Maximum number of parallel runspaces used for server discovery. Default: 20.

    .EXAMPLE
    Push-IRTAdSync
    Automatically discovers and triggers a delta sync.

    .EXAMPLE
    Push-IRTAdSync -SyncServer 'sync01.contoso.com'
    Triggers sync on a known server without discovery.

    .EXAMPLE
    Push-IRTAdSync -ResetCredentials
    Re-prompts for domain admin credentials before syncing.

    .OUTPUTS
    None. Progress is written to the console.

    .NOTES
    Version: 2.0.0
    2.0.0 - Parallel server discovery via runspace pool (ping, open session, service check).
            Added -SyncServer parameter to target specific servers directly, bypassing AD query.
            Added -ThrottleLimit parameter.
    #>
    [Alias(
        'Push-IRTAdSyncs',
        'Push-AdSync', 'Push-AdSyncs',
        'PushIRTAdSync', 'PushIRTAdSyncs',
        'PushAdSync', 'PushAdSyncs',
        'AdSync', 'SyncAd'
    )]
    [CmdletBinding()]
    param(
        [Alias('Reset', 'ResetPassword')]
        [switch] $ResetCredentials,

        [Alias('SyncServers')]
        [string[]] $SyncServer,

        [ValidateRange(1, 50)]
        [int] $ThrottleLimit = 20
    )

    process {

        if (Test-RunningOnDomainController) {
            Write-IRT "Pushing AD replication..."
            $null = repadmin /syncall /AdeP
        }
        else {
            Write-IRT "Not running on a domain controller. Skipping AD replication." -Level Warn
        }

        # if sync service is running on this server, push sync locally
        $SyncService = Get-Service -Name 'adsync' -ErrorAction SilentlyContinue
        if ($SyncService) {
            Write-IRT "Pushing sync."
            Start-ADSyncSyncCycle -PolicyType Delta
            return
        }
        Write-IRT "Adsync service not running on this device."

        if (-not (Get-YesNo "Search for server running adsync?")) {
            return
        }

        # build the ordered candidate server list
        if ($SyncServer) {
            # user supplied explicit targets - skip AD query, RSAT check, and DC check entirely
            $ServerNamesInQueryOrder = $SyncServer
        }
        else {
            # require AD RSAT for discovery
            if (-not (Test-AdAvailable)) {
                $Msg = "Active Directory can't be reached from this device. " +
                "Specify hostnames with -SyncServer."
                Write-IRT $Msg -Level Error
                return
            }

            # query AD for all enabled servers
            $QueryParams = @{
                Filter     = "OperatingSystem -like '*server*' -and Enabled -eq 'true'"
                Properties = 'Name', 'OperatingSystem', 'LastLogOnDate'
            }
            $ServerNames = (
                Get-AdComputer @QueryParams | Sort-Object LastLogOnDate -Descending
            ).Name

            # domain controllers first, then remaining servers by last logon date
            $DomainControllerNames = (Get-ADDomainController -Filter *).Name
            $NonDCServerNames = $ServerNames |
                Where-Object { $_ -notin $DomainControllerNames }
            $ServerNamesInQueryOrder = $DomainControllerNames + $NonDCServerNames
        }

        # request credentials from user
        if (-not $Global:Storage -or $ResetCredentials) {

            $UserName = Read-Host "Enter domain admin username"
            $Password = Read-Host -AsSecureString "Enter domain admin password"

            $CredParams = @{
                TypeName     = 'System.Management.Automation.PSCredential'
                ArgumentList = @($UserName, $Password)
            }
            try {
                $Global:Storage = New-Object @CredParams -ErrorAction Stop
            }
            catch {
                $_
                throw "Unable to build credential object."
            }
        }
        $Credentials = $Global:Storage

        # close any existing sessions
        Get-PSSession | Remove-PSSession

        ########################################################################
        # parallel discovery: ping + open session + check adsync service

        $DiscoveryScriptBlock = {
            param(
                [string] $ComputerName,
                [System.Management.Automation.PSCredential] $Credentials
            )

            $Result = [PSCustomObject]@{
                ComputerName  = $ComputerName
                Reachable     = $false
                SessionOpened = $false
                AdsyncPresent = $false
                Session       = $null
                Error         = $null
            }

            # ping
            try {
                $Reply = ([System.Net.NetworkInformation.Ping]::new()).Send($ComputerName, 1000)
                $Result.Reachable = $Reply.Status -eq 'Success'
            }
            catch {
                $Result.Reachable = $false
            }

            if (-not $Result.Reachable) { return $Result }

            # open session
            try {
                $SessionParams = @{
                    ComputerName = $ComputerName
                    Credential   = $Credentials
                    ErrorAction  = 'Stop'
                }
                $Result.Session = New-PSSession @SessionParams
                $Result.SessionOpened = $true
            }
            catch {
                $Result.Error = "Session failed: $_"
                return $Result
            }

            # check for adsync service
            try {
                $Result.AdsyncPresent = Invoke-Command -Session $Result.Session -ScriptBlock {
                    [bool](Get-Service 'adsync' -ErrorAction SilentlyContinue)
                }
            }
            catch {
                $Result.Error = "Service check failed: $_"
            }

            # close session now if adsync is not present - only keep sessions where adsync was found
            if (-not $Result.AdsyncPresent) {
                Remove-PSSession -Session $Result.Session -ErrorAction SilentlyContinue
                $Result.Session = $null
            }

            return $Result
        }

        $Pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
            1, $ThrottleLimit
        )
        $Runspaces = [System.Collections.Generic.List[hashtable]]::new()
        $Pool.Open()

        try {
            foreach ($ComputerName in $ServerNamesInQueryOrder) {
                $ComputerName = ($ComputerName -split '\.')[0]
                if ([string]::IsNullOrWhiteSpace($ComputerName)) { continue }

                $PS = [System.Management.Automation.PowerShell]::Create()
                $PS.RunspacePool = $Pool
                $null = $PS.AddScript($DiscoveryScriptBlock)
                $null = $PS.AddArgument($ComputerName).AddArgument($Credentials)
                $RSEntry = @{
                    ComputerName = $ComputerName
                    PS           = $PS
                    Handle       = $PS.BeginInvoke()
                }
                $Runspaces.Add($RSEntry)
            }

            $Total = $Runspaces.Count
            $Done = 0
            $Synced = $false

            # process runspaces in priority order;
            # EndInvoke blocks per entry while others keep running
            foreach ($RS in $Runspaces) {

                $ProgressParams = @{
                    Activity        = 'Discovering sync server'
                    Status          = "$Done of $Total servers checked"
                    PercentComplete = [math]::Floor( ( $Done / $Total ) * 100 )
                }
                Write-Progress @ProgressParams

                $DiscoveryResult = ($RS.PS.EndInvoke($RS.Handle))[0]
                $RS.PS.Dispose()
                $RS.PS = $null
                $Done++

                $CN = $RS.ComputerName

                if (-not $DiscoveryResult.Reachable) {
                    Write-IRT "Pinging ${CN}: FAILED." -Level Warn
                    continue
                }

                if (-not $DiscoveryResult.SessionOpened) {
                    $Msg = "Opening session on ${CN} failed: $($DiscoveryResult.Error)"
                    Write-IRT $Msg -Level Warn
                    continue
                }

                if (-not $DiscoveryResult.AdsyncPresent) {
                    Write-IRT "Adsync service not present on ${CN}."
                    continue
                }

                # adsync found - attempt push
                Write-IRT "Adsync service found on ${CN}. Pushing sync..."
                try {
                    $SyncResult = Invoke-Command -Session $DiscoveryResult.Session -ScriptBlock {
                        [string]( Start-ADSyncSyncCycle -PolicyType Delta ).Result
                    }

                    if ($SyncResult -eq 'Success') {
                        Write-IRT "Sync pushed successfully on ${CN}."
                        $Synced = $true
                    }
                    else {
                        Write-IRT "Sync failed on ${CN} (result: $SyncResult)." -Level Error
                    }
                }
                catch {
                    Write-IRT "Sync failed on ${CN}: $_" -Level Error
                }
                finally {
                    Remove-PSSession -Session $DiscoveryResult.Session -ErrorAction SilentlyContinue
                }

                if ($Synced) { break }
            }

            if (-not $Synced) {
                $Msg = 'No adsync server was found or sync could not be pushed on any server.'
                Write-IRT $Msg -Level Error
            }
        }
        finally {
            Write-Progress -Activity 'Discovering sync server' -Completed

            # stop and dispose any runspaces not yet processed (e.g. after an early break)
            foreach ($RS in $Runspaces) {
                if ($null -ne $RS.PS) {
                    try { $RS.PS.Stop() } catch {}
                    $RS.PS.Dispose()
                }
            }

            $Pool.Close()
            $Pool.Dispose()

            # remove any sessions that leaked from unprocessed runspaces
            Get-PSSession | Remove-PSSession
        }
    }
}
#EndRegion '.\Public\OnPremAd\Push-IRTAdSync.ps1' 318
#Region '.\Public\OnPremAd\Reset-IRTAdUserPassword.ps1' -1

function Reset-IRTAdUserPassword {
    <#
    .SYNOPSIS
    Resets an Active Directory user's password.

    .DESCRIPTION
    Resets the on-premises AD password for one or more users. Exactly one of the three
    password mode switches must be specified:

      -RandomCharacters     Generates a random password (default length: 30 characters)
                            and sets it immediately. The new password is printed to the
                            console via [Console]::WriteLine so it is NOT captured in
                            PowerShell transcripts.

      -Custom               Prompts the operator to enter a password interactively via
                            Read-Host -AsSecureString. The password is set immediately.

      -ForceChangePasswordNextSignIn
                            Does not set a new password. Instead, sets
                            ChangePasswordAtLogon = $true on the account, which forces
                            the user to choose a new password on their next login.

    If no -UserObjects is supplied, the function falls back to the global session objects
    stored via Get-AdGlobalUserObject. An error is thrown if neither source yields a user.

    After the reset, updated account properties are retrieved and displayed as a table.
    If running on a domain controller, intra-AD replication is triggered via repadmin.
    If the ADSync service is local, an Azure AD delta sync is started.

    Supports -WhatIf and -Confirm via SupportsShouldProcess.

    .PARAMETER UserObjects
    One or more AD user objects whose passwords will be reset. Falls back to
    global session objects if omitted.

    .PARAMETER RandomCharacters
    Generates a random password of the specified length (default: 30 characters) and
    applies it to the account. The password is written directly to the console (bypassing
    transcript logging) so it can be recorded securely by the operator.

    .PARAMETER Length
    The length of the randomly generated password. Only valid with -RandomCharacters.
    Must be at least 4 characters. Defaults to 30.

    .PARAMETER Custom
    Prompts the operator to enter a custom password via Read-Host -AsSecureString.

    .PARAMETER ForceChangePasswordNextSignIn
    Sets ChangePasswordAtLogon = $true on the account without changing the current
    password. The user will be required to set a new password on their next sign-in.

    .EXAMPLE
    Reset-IRTAdUserPassword -RandomCharacters
    Generates and sets a random password for the user in the global session.

    .EXAMPLE
    Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters
    Resets the password for a specific user object using a random password.

    .EXAMPLE
    Reset-IRTAdUserPassword -Custom
    Prompts the operator to enter a custom password for the global session user.

    .EXAMPLE
    Reset-IRTAdUserPassword -UserObjects $User -ForceChangePasswordNextSignIn
    Forces the user to set a new password on their next sign-in, without changing
    the current password.

    .EXAMPLE
    Reset-IRTAdUserPassword -RandomCharacters -Length 48
    Resets the password using a random 48-character password.

    .EXAMPLE
    Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters -WhatIf
    Shows what would happen without actually resetting the password.

    .OUTPUTS
    None. Updated user properties are displayed as a formatted table in the console.

    .NOTES
    Version: 1.1.0
    1.1.0 - Added ForceChangePasswordNextSignIn parameter set. Removed default parameter
            set; operator must now explicitly choose a password mode. Added -Length
            parameter. Renamed to Reset-IRTAdUserPassword.
    1.0.0 - Initial version as Reset-AdUserPassword.
    #>
    [Alias('ResetAdPassword', 'ResetAdPasswords', 'Reset-AdPassword')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0)]
        [Alias('UserObject')]
        [psobject[]] $UserObjects,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [Alias('Random')]
        [switch] $RandomCharacters,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [ValidateRange(4, [int]::MaxValue)]
        [int] $Length = 30,

        [Parameter(ParameterSetName = 'Custom')]
        [switch] $Custom,

        [Parameter(ParameterSetName = 'ForceChangePasswordNextSignIn')]
        [switch] $ForceChangePasswordNextSignIn
    )

    begin {
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $UserProperties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
            'PasswordLastSet'
        )

        # if not passed directly, find global
        if (-not $UserObjects -or $UserObjects.Count -eq 0) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if (-not $ScriptUserObjects) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }
    }

    process {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        Write-IRT ''

        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $Username = $ScriptUserObject.SamAccountName
            $ResetPassword = $true

            switch ($true) {
                $Custom {
                    $Password = Read-Host -AsSecureString "Enter new password for ${Username}"
                    break
                }
                $ForceChangePasswordNextSignIn {
                    $ResetPassword = $false
                    $ShouldChange = $PSCmdlet.ShouldProcess($Username,
                        'Force password change at next sign-in')
                    if ($ShouldChange) {
                        $SetParams = @{
                            Identity              = $ScriptUserObject
                            ChangePasswordAtLogon = $true
                            Server                = $env:ComputerName
                        }
                        Set-ADUser @SetParams
                    }
                    break
                }
                $RandomCharacters {
                    $PlainTextPassword = Get-RandomPassword $Length
                    $ConvertParams = @{
                        String      = $PlainTextPassword
                        AsPlainText = $true
                        Force       = $true
                    }
                    $Password = ConvertTo-SecureString @ConvertParams
                    Write-IRT "${Username} new password:"
                    # Console WriteLine prevents password from being recorded in logs/transcripts
                    [Console]::WriteLine($PlainTextPassword)
                }
            }

            if ($ResetPassword) {
                $ResetParams = @{
                    Identity    = $ScriptUserObject
                    Reset       = $true
                    NewPassword = $Password
                    Server      = $env:ComputerName
                }
                if ($PSCmdlet.ShouldProcess($Username, 'Reset password')) {
                    Set-AdAccountPassword @ResetParams
                }
            }

            # get new object to show result
            Write-IRT "Getting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $UserProperties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add($NewObject)
        }

        # show results
        $OutputObjects | Format-Table $UserProperties

        # push ad replication
        if (Test-RunningOnDomainController) {
            Write-IRT "Pushing AD replication."
            $null = & repadmin /syncall $env:ComputerName /APed *>&1
        }
        else {
            Write-Warning "Not running on a domain controller; skipping replication push."
        }

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ($SyncService) {
            Write-IRT "Pushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            $Msg = "Azure sync isn't running on this server. " +
            "Run Push-IRTAdSync, or duplicate actions in M365."
            Write-IRT $Msg -Level Error
        }
    }
}
#EndRegion '.\Public\OnPremAd\Reset-IRTAdUserPassword.ps1' 230
#Region '.\Public\OnPremAd\Show-IRTAdDevice.ps1' -1

function Show-IRTAdDevice {
    <#
    .SYNOPSIS
    Displays AD computer properties.

    .DESCRIPTION
    Retrieves all properties of an on-premises AD computer object, converts every DateTime
    value to local time, and displays the result with Format-Tree. Falls back to
    $Global:IRT_DeviceObject if no -DeviceObject is passed.

    .PARAMETER DeviceObject
    One or more AD computer objects to display. Falls back to $Global:IRT_DeviceObject
    if omitted.

    .EXAMPLE
    Show-IRTAdDevice
    Displays info for the device in $Global:IRT_DeviceObject.

    .EXAMPLE
    Show-IRTAdDevice -DeviceObject $AdComputer
    Displays info for a specific AD computer object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Show-IRTAdDevices',
        'Show-AdDevice', 'Show-AdDevices',
        'ShowIRTAdDevice', 'ShowIRTAdDevices',
        'ShowAdDevice', 'ShowAdDevices'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [psobject[]] $DeviceObject
    )

    begin {

        if (-not $DeviceObject -or $DeviceObject.Count -eq 0) {

            if ($Global:IRT_DeviceObject) {
                $ScriptDeviceObjects = @($Global:IRT_DeviceObject)
            }
            else {
                throw ('No device object passed and $Global:IRT_DeviceObject is not set. ' +
                    'Run Find-IRTAdDevice first.')
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }
    }

    process {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        $ExcludeProperty = @(
            'codePage'
            'createTimeStamp'
            'dSCorePropagationData'
            'DoesNotRequirePreAuth'
            'HomedirRequired'
            'instanceType'
            'lastLogon'
            'lastLogonTimestamp'
            'localPolicyFlags'
            'MNSLogonAccount'
            'modifyTimeStamp'
            'msDS-SupportedEncryptionTypes'
            'msDS-User-Account-Control-Computed'
            'nTSecurityDescriptor'
            'objectSid'
            'primaryGroupID'
            'PropertyCount'
            'PropertyNames'
            'sDRightsEffective'
            'SID'
            'TrustedForDelegation'
            'TrustedToAuthForDelegation'
            'uSNChanged'
            'uSNCreated'
        )

        foreach ($Device in $ScriptDeviceObjects) {

            $FullObject = $Device | Get-AdComputer -Property *

            # replace partial object in global with full object
            if ($Global:IRT_DeviceObject -and
                $Global:IRT_DeviceObject.ObjectGUID -eq $FullObject.ObjectGUID
            ) {
                $Global:IRT_DeviceObject = $FullObject
            }

            $FileTimeProperties = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@(
                    'accountExpires'
                    'badPasswordTime'
                    'lastLogon'
                    'lastLogonTimestamp'
                    'lockoutTime'
                    'pwdLastSet'
                ),
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $Props = [ordered]@{}
            foreach ($Prop in ($FullObject.PSObject.Properties | Sort-Object Name)) {
                # convert DateTime objects to local time
                if ($Prop.Value -is [DateTime]) {
                    $Props[$Prop.Name] = $Prop.Value.ToLocalTime()
                }
                # convert Int64 objects to human readable time
                elseif ($Prop.Value -is [long] -and $FileTimeProperties.Contains($Prop.Name)) {
                    if ($Prop.Value -eq 0 -or $Prop.Value -eq [Int64]::MaxValue) {
                        $Props[$Prop.Name] = 'Never'
                    }
                    else {
                        $Props[$Prop.Name] = [DateTime]::FromFileTime($Prop.Value).ToLocalTime()
                    }
                }
                else {
                    $Props[$Prop.Name] = $Prop.Value
                }
            }

            $FormatParams = @{
                Depth           = 5
                OmitNullOrEmpty = $true
                ExcludeProperty = $ExcludeProperty
            }
            [PSCustomObject]$Props | Format-Tree @FormatParams
            Write-IRT 'Note: all dates are displayed in local time.'
        }
    }
}
#EndRegion '.\Public\OnPremAd\Show-IRTAdDevice.ps1' 145
#Region '.\Public\OnPremAd\Show-IRTAdOus.ps1' -1

function Show-IRTAdOus {
    <#
    .SYNOPSIS
    Shows a list of all OUs with a count of users and devices.

    .DESCRIPTION
    Lists all Organizational Units in the current AD domain, sorted by CanonicalName.
    For each OU, counts users and computers directly inside it (OneLevel scope) and
    displays the results in a formatted table.

    Output objects use the custom type 'ShowAdOus' with a DefaultDisplayPropertySet
    so Format-Table shows CanonicalName, Name, Users, Computers, and DistinguishedName
    by default.

    .EXAMPLE
    Show-IRTAdOus
    Lists all OUs with user and computer counts.

    .EXAMPLE
    Show-IRTAdOus | Where-Object { $_.Users -gt 0 }
    Returns only OUs that contain at least one user.

    .OUTPUTS
    PSCustomObject[] (type: ShowAdOus)

    .NOTES
    Version: 1.0.1
    #>
    [Alias(
        'Show-IRTAdOu',
        'Show-AdOu', 'Show-AdOus',
        'ShowIRTAdOu', 'ShowIRTAdOus',
        'ShowAdOu', 'ShowAdOus',
        'AdOus'
    )]
    [CmdletBinding()]
    param (
    )

    begin {
        # custom output view
        $Params = @{
            TypeName                  = 'ShowAdOus'
            DefaultDisplayPropertySet = 'CanonicalName', 'Name', 'Users',
            'Computers', 'DistinguishedName'
            Force                     = $true
        }
        Update-TypeData @Params
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # get all ous
        $Ous = Get-ADOrganizationalUnit -Properties CanonicalName -Filter * |
            Sort-Object CanonicalName

        # create display objects
        foreach ( $Ou in $Ous ) {

            $UserCount = @(
                Get-AdUser -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel
            ).Count
            if ( $UserCount -le 0 ) {
                $UserCount = '-'
            }

            $ComputerCount = @(
                Get-AdComputer -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel
            ).Count
            if ( $ComputerCount -le 0 ) {
                $ComputerCount = '-'
            }

            [pscustomobject]@{
                PSTypeName   = 'ShowAdOus'
                CanonicalName     = $Ou.CanonicalName
                Name              = Split-Path $Ou.CanonicalName -Leaf
                Users             = $UserCount
                Computers         = $ComputerCount
                DistinguishedName = $Ou.DistinguishedName
            }
        }
    }
}
#EndRegion '.\Public\OnPremAd\Show-IRTAdOus.ps1' 90
#Region '.\Public\OnPremAd\Show-IRTAdUser.ps1' -1

function Show-IRTAdUser {
    <#
    .SYNOPSIS
    Displays AD user properties.

    .DESCRIPTION
    Retrieves all properties of an on-premises AD user object, converts every DateTime
    value to local time, and displays the result with Format-Tree. Falls back to
    $Global:IRT_UserObject (via Get-AdGlobalUserObject) if no -UserObjects is passed.

    .PARAMETER UserObjects
    One or more AD user objects to display. Falls back to global session objects if omitted.

    .EXAMPLE
    Show-IRTAdUser
    Displays info for the user(s) in the global session.

    .EXAMPLE
    Show-IRTAdUser -UserObjects $AdUser
    Displays info for a specific AD user object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Switched to Format-Tree with dynamic DateTime conversion.
    1.1.2 - Added pwdLastSet
    #>
    [Alias(
        'Show-IRTAdUsers',
        'Show-AdUser', 'Show-AdUsers',
        'ShowIRTAdUser', 'ShowIRTAdUsers',
        'ShowAdUser', 'ShowAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects
    )

    begin {

        # if not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        $ExcludeProperty = @(
            'c'
            'co'
            'codePage'
            'countryCode'
            'createTimeStamp'
            'dSCorePropagationData'
            'DoesNotRequirePreAuth'
            'extensionName'
            'HomedirRequired'
            'instanceType'
            'l'
            'lastLogon'
            'lastLogonTimestamp'
            'localPolicyFlags'
            'MNSLogonAccount'
            'modifyTimeStamp'
            'msExchALObjectVersion'
            'msDS-SupportedEncryptionTypes'
            'msDS-User-Account-Control-Computed'
            'nTSecurityDescriptor'
            'objectSid'
            'primaryGroupID'
            'PropertyCount'
            'PropertyNames'
            'sAMAccountType'
            'sDRightsEffective'
            'SID'
            'TrustedForDelegation'
            'TrustedToAuthForDelegation'
            'userAccountControl'
            'userParameters'
            'uSNChanged'
            'uSNCreated'
        )

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # get user object with all properties
            $FullObject = $ScriptUserObject | Get-AdUser -Property *

            $FileTimeProperties = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@(
                    'accountExpires'
                    'badPasswordTime'
                    'lastLogon'
                    'lastLogonTimestamp'
                    'lockoutTime'
                    'msExchLastExchangeChangedTime'
                    'msDS-UserPasswordExpiryTimeComputed'
                    'pwdLastSet'
                ),
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $Props = [ordered]@{}
            foreach ($Prop in ($FullObject.PSObject.Properties | Sort-Object Name)) {
                # convert DateTime objects to local time
                if ($Prop.Value -is [DateTime]) {
                    $Props[$Prop.Name] = $Prop.Value.ToLocalTime()
                }
                # Convert Int64 objects to human readable time
                elseif ($Prop.Value -is [long] -and $FileTimeProperties.Contains($Prop.Name)) {
                    if ($Prop.Value -eq 0 -or $Prop.Value -eq [Int64]::MaxValue) {
                        $Props[$Prop.Name] = 'Never'
                    }
                    else {
                        $Props[$Prop.Name] = [DateTime]::FromFileTime($Prop.Value).ToLocalTime()
                    }
                }
                else {
                    $Props[$Prop.Name] = $Prop.Value
                }
            }

            $FormatParams = @{
                Depth           = 5
                OmitNullOrEmpty = $true
                ExcludeProperty = $ExcludeProperty
            }
            [PSCustomObject]$Props | Format-Tree @FormatParams
            Write-IRT 'Note: all dates are displayed in local time.'
        }
    }
}
#EndRegion '.\Public\OnPremAd\Show-IRTAdUser.ps1' 153
#Region '.\Public\Role\Get-IRTAdminRole.ps1' -1

function Get-IRTAdminRole {
    <#
    .SYNOPSIS
    Reports all Entra ID directory role members for the tenant.

    .DESCRIPTION
    Retrieves every Entra ID (Azure AD) directory role and its members, including users,
    service principals, and groups. When a group holds a role, its members are expanded
    inline so the report is always a flat list of effective principals.

    Output defaults to formatted console tables grouped by object type (Users, Service
    Principals, Groups). Use -Excel to export a formatted .xlsx workbook instead.

    .PARAMETER Cached
    Use pre-cached Graph data instead of making new API calls. Speeds up repeated runs
    during the same session.

    .PARAMETER Script
    Return raw PSCustomObject results instead of printing to the console. Useful when
    calling this function from scripts or the playbook.

    .PARAMETER Excel
    Export results to a formatted Excel workbook (.xlsx) in the current directory.

    .PARAMETER Highlight
    One or more strings to search across Id, DisplayName, UserPrincipalName, and
    Description. Matching rows are flagged with '>>>' in a Match column.

    .PARAMETER TableStyle
    Excel table style name. Defaults to the value in IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Font name for the Excel workbook. Defaults to the value in IRT_Config.ExcelFont.

    .PARAMETER Open
    When exporting to Excel, open the file immediately after writing. Default: $true.

    .EXAMPLE
    Get-IRTAdminRole
    Displays all role members grouped by type in the console.

    .EXAMPLE
    Get-IRTAdminRole -Excel -Highlight 'jsmith@contoso.com'
    Exports an Excel report and flags any row matching 'jsmith@contoso.com'.

    .EXAMPLE
    $RoleMembers = Get-IRTAdminRole -Script
    Returns raw objects for further processing.

    .OUTPUTS
    None (console output) by default.
    System.Collections.Generic.List[PSCustomObject] when -Script is used.
    #>
    [Alias('GetAdmins')]
    [CmdletBinding()]
    param(
        [switch] $Cached,
        [switch] $Script,
        [switch] $Excel,
        [string[]] $Highlight,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'

        $CustomObjects = [System.Collections.Generic.List[pscustomobject]]::new()
        $WorksheetName = 'AdminRoles'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = Get-Date -Format $FileNameDateFormat


        # ensure ById caches are populated for Get-UnknownObject lookups
        Request-GraphUser -Return 'none' -Cached:$Cached
        Request-GraphGroup -Return 'none' -Cached:$Cached
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
        Request-DirectoryRole -Return 'none' -Cached:$Cached
    }

    process {

        $RoleObjects = Request-DirectoryRole -Cached:$Cached
        $MemberIds = $RoleObjects.Members.Id | Sort-Object -Unique

        foreach ( $MemberId in $MemberIds ) {

            $MemberRoles = (
                $RoleObjects | Where-Object { $MemberId -in $_.Members.Id }
            ).DisplayName -join ', '
            $Object = Get-UnknownObject -Id $MemberId
            $NrmParams = @{
                Id          = $MemberId
                Role        = $MemberRoles
                RoleSource  = 'Direct Assignment'
                GraphObject = $Object
            }
            $CustomObject = New-RoleMemberObject @NrmParams
            $CustomObjects.Add( $CustomObject )

            # expand group members inline (nested groups not possible with M365 role assignments)
            if ( $CustomObject.ObjectType -eq 'Group' ) {
                foreach ( $GroupMemberId in ( Get-MgGroupMember -GroupId $MemberId ).Id ) {
                    $GroupMember = Get-UnknownObject -Id $GroupMemberId
                    $GrpParams = @{
                        Id          = $GroupMemberId
                        Role        = $MemberRoles
                        RoleSource  = "Group: $($Object.DisplayName)"
                        GraphObject = $GroupMember
                    }
                    $CustomObjects.Add( ( New-RoleMemberObject @GrpParams ) )
                }
            }
        }
    }

    end {

        $SortObjectType = @{
            Expression = 'ObjectType'
            Descending = $true
        }
        $SortAccountEnabled = @{
            Expression = 'AccountEnabled'
            Descending = $true
        }
        $CustomObjects = $CustomObjects | Sort-Object $SortObjectType, $SortAccountEnabled

        # add highlight match column
        if ( $Highlight ) {
            $HighlightPattern = $Highlight -join '|'
            foreach ( $Obj in $CustomObjects ) {
                $IsMatch = (
                    ( $Obj.Id -match $HighlightPattern ) -or
                    ( $Obj.DisplayName -match $HighlightPattern ) -or
                    ( $Obj.PSObject.Properties['UserPrincipalName'] -and
                    $Obj.UserPrincipalName -match $HighlightPattern ) -or
                    ( $Obj.PSObject.Properties['Description'] -and
                    $Obj.Description -match $HighlightPattern )
                )
                $AddParams = @{
                    MemberType = 'NoteProperty'
                    Name       = 'Match'
                    Value      = $(if ( $IsMatch ) { '>>>' } else { '' })
                }
                $Obj | Add-Member @AddParams
            }
        }

        if ( $Script ) {
            return $CustomObjects
        }

        # display properties per object type
        $DisplayProperties = [ordered]@{
            'User'             = @(
                'AccountEnabled'
                'DisplayName'
                'UserPrincipalName'
                'RoleSource'
                'Roles'
            )
            'ServicePrincipal' = @(
                'AccountEnabled'
                'DisplayName'
                'ServicePrincipalType'
                'RoleSource'
                'Roles'
            )
            'Group'            = @(
                'DisplayName'
                'RoleSource'
                'Roles'
            )
        }
        $TypeLabels = @{
            'User'             = 'Users with admin roles:'
            'ServicePrincipal' = 'Service Principals with admin roles:'
            'Group'            = 'Groups with admin roles:'
        }

        if ( $Highlight ) {
            foreach ( $TypeKey in @( $DisplayProperties.Keys ) ) {
                $DisplayProperties[$TypeKey] = @( 'Match' ) + $DisplayProperties[$TypeKey]
            }
        }

        if ( -not $Excel ) {
            foreach ( $TypeKey in $DisplayProperties.Keys ) {
                Write-IRT "$($TypeLabels[$TypeKey])"
                $TypeObjects = $CustomObjects | Where-Object { $_.ObjectType -eq $TypeKey }
                if ( $TypeObjects ) {
                    $TypeObjects |
                        Format-Table -AutoSize -Property $DisplayProperties[$TypeKey] |
                        Out-Host
                }
                else {
                    Write-IRT "None" -NoFunctionName -NoColor
                }
            }
        }

        if ( $Excel ) {

            $DomainName = Get-DefaultDomain
            $ExcelOutputPath = "AdminRoles_${DomainName}_${FileDateString}.xlsx"
            $TitleDateString = Get-Date -Format 'MM/dd/yy HH:mm'

            Write-IRT "Exporting Excel: ${ExcelOutputPath}"

            $Workbook = $null
            $LabelRow = 3

            foreach ( $TypeKey in $DisplayProperties.Keys ) {

                $TypeObjects = @( $CustomObjects | Where-Object { $_.ObjectType -eq $TypeKey } )
                $Columns = $DisplayProperties[$TypeKey]

                if ( $TypeObjects.Count -gt 0 ) {

                    $SectionParams = @{
                        WorkSheetname = $WorksheetName
                        TableName     = "Table${TypeKey}"
                        TableStyle    = $TableStyle
                        StartRow      = $LabelRow + 1
                        AutoSize      = $true
                        Passthru      = $true
                    }
                    if ( $null -eq $Workbook ) {
                        $SectionParams['Path'] = $ExcelOutputPath
                    }
                    else {
                        $SectionParams['ExcelPackage'] = $Workbook
                    }

                    try {
                        $Workbook = $TypeObjects |
                            Select-Object -Property $Columns |
                            Export-Excel @SectionParams
                    }
                    catch {
                        Write-Error "Unable to write Excel section: ${TypeKey}"
                        if ( $Workbook ) { $Workbook | Close-ExcelPackage }
                        return
                    }

                    $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
                    $TableStartRow = $LabelRow + 1
                    $TableEndRow = $LabelRow + 1 + $TypeObjects.Count

                    # section label (written after export so worksheet exists)
                    $Worksheet.Cells[$LabelRow, 1].Value = $TypeLabels[$TypeKey]
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12

                    # conditional formatting: Match column
                    if ( $Highlight ) {
                        $MatchColId = (
                            $Worksheet.Tables["Table${TypeKey}"].Columns |
                                Where-Object { $_.Name -eq 'Match' }
                        ).Id
                        if ( $MatchColId ) {
                            $MatchCol = $MatchColId | Convert-DecimalToExcelColumn
                            $MatchFmtParams = @{
                                Worksheet       = $Worksheet
                                Address         = "${MatchCol}${TableStartRow}" +
                                ":${MatchCol}${TableEndRow}"
                                RuleType        = 'ContainsText'
                                ConditionValue  = '>>>'
                                BackgroundColor = 'LightPink'
                            }
                            Add-ConditionalFormatting @MatchFmtParams
                        }
                    }

                    # conditional formatting: AccountEnabled = FALSE
                    $AEColId = (
                        $Worksheet.Tables["Table${TypeKey}"].Columns |
                            Where-Object { $_.Name -eq 'AccountEnabled' }
                    ).Id
                    if ( $AEColId ) {
                        $AECol = $AEColId | Convert-DecimalToExcelColumn
                        $AEFmtParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${AECol}${TableStartRow}:${AECol}${TableEndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = 'FALSE'
                            BackgroundColor = 'LightBlue'
                        }
                        Add-ConditionalFormatting @AEFmtParams
                    }

                    $LabelRow = $TableEndRow + 2

                }
                else {

                    # write label and (none) directly if workbook already exists
                    if ( $null -ne $Workbook ) {
                        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
                        $Worksheet.Cells[$LabelRow, 1].Value = $TypeLabels[$TypeKey]
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12
                        $Worksheet.Cells[$LabelRow + 1, 1].Value = '(none)'
                    }
                    $LabelRow += 3
                }
            }

            if ( $null -eq $Workbook ) {
                Write-IRT "No admin role members found." -Level Warn
                return
            }

            # column widths
            $ColumnWidths = @{
                'Match'             = 8
                'Enabled'           = 12
                'DisplayName'       = 30
                'UserPrincipalName' = 40
                'RoleSource'        = 30
                'Roles'             = 80
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # font across entire used range
            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
            $SheetEnd = $Worksheet.Dimension.End.Address
            Set-ExcelRange -Worksheet $Worksheet -Range "A1:${SheetEnd}" -FontName $Font

            # sheet title (written last so font override sticks)
            $Worksheet.Cells[1, 1].Value = "Admin roles for ${DomainName} as of ${TitleDateString}"
            $Worksheet.Cells[1, 1].Style.Font.Bold = $true
            $Worksheet.Cells[1, 1].Style.Font.Size = 16

            # save and close
            if ( $Open ) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
#EndRegion '.\Public\Role\Get-IRTAdminRole.ps1' 351
#Region '.\Public\ServicePrincipal\Find-IRTRiskyServicePrincipal.ps1' -1

function Find-IRTRiskyServicePrincipal {
    <#
    .SYNOPSIS
    Identifies potentially malicious OAuth applications registered in the tenant.

    .DESCRIPTION
    Checks all service principals in the tenant against a configurable list of threat
    intelligence feeds to find known malicious OAuth app IDs. For each match, displays
    app details, the source feed, and the users who have granted consent to the app.

    Also reports on tenant-level app registration and user consent policies.

    New feeds can be added to the $ThreatFeeds array in the begin block.
    Each feed requires: Name, Url, Parser (scriptblock), AppIdField, and DisplayProperties.

    Requires the PSToml module for feeds that use TOML format.

    .PARAMETER Cached
    Use pre-cached Graph service principal and OAuth grant data instead of making new
    API calls. Speeds up repeated runs during the same session.

    .EXAMPLE
    Find-IRTRiskyServicePrincipal
    Queries all threat intelligence feeds and reports any matches in the tenant.

    .EXAMPLE
    Find-IRTRiskyServicePrincipal -Cached
    Same as above but uses cached Graph data from the current session.

    .OUTPUTS
    None. Results are written to the console.

    .NOTES
    Requires an active Graph connection with appropriate permissions.
    Threat intelligence feeds are fetched live from GitHub at runtime.
    #>
    [Alias('RiskyApps', 'RiskySPs',
        'FindRiskySP', 'FindRiskySPs',
        'FindRiskyApp', 'FindRiskyApps',
        'FindRiskyApplication', 'FindRiskyApplications',
        'FindRiskyServicePrincipal', 'FindRiskyServicePrincipals',
        'FindRiskyEnterpriseApp', 'FindRiskyEnterpriseApps',
        'Find-RiskyApplication')]
    param (
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # variables
        $UserDisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'UserPrincipalName'
            'Id'
        )
        $ThreatFeeds = @(
            @{
                Name              = 'Huntress RogueApps'
                Url               = 'https://raw.githubusercontent.com/' +
                'huntresslabs/rogueapps/refs/heads/main/data/rogueapps.toml'
                Parser            = {
                    param($r)
                    ($r | ConvertFrom-Toml).apps | ForEach-Object { [PSCustomObject]$_ }
                }
                AppIdField        = 'appId'
                DisplayProperties = @('appDisplayName', 'description', 'tags', 'references')
                Apps              = $null
            }
            @{
                Name              = 'Syne/randomaccess3'
                Url               = 'https://raw.githubusercontent.com/' +
                'randomaccess3/detections/refs/heads/main/' +
                'M365_Oauth_Apps/MaliciousOauthAppDetections.json'
                Parser            = { param($r) ($r | ConvertFrom-Json).Applications }
                AppIdField        = 'AppId'
                DisplayProperties = @('Name', 'Description', 'Categories', 'References')
                Apps              = $null
            }
        )
        $FoundApps = $false

        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
        $PermissionGrants = Request-GraphOauth2Grant -Cached:$Cached
        $Users = Request-GraphUser -Cached:$Cached
    }

    process {
        ### show settings
        Write-IRT "Tenant App settings:"
        $AuthPolicy = Get-MgPolicyAuthorizationPolicy
        $DefaultRolePermissions = $AuthPolicy.DefaultUserRolePermissions
        $PoliciesAssigned = $DefaultRolePermissions.PermissionGrantPoliciesAssigned |
            Where-Object { $_ -match 'ManagePermissionGrantsForSelf' }
        $Output = [PSCustomObject]@{
            UsersAllowedToCreateApps     = $DefaultRolePermissions.AllowedToCreateApps
            UsersAllowedToConsentForApps = [bool]$PoliciesAssigned
        }
        $Output | Format-List | Out-Host


        # fetch threat feeds
        foreach ($Feed in $ThreatFeeds) {
            $Feed.Apps = & $Feed.Parser (Invoke-WebRequest -Uri $Feed.Url).Content
        }

        # build combined list
        $SusAppIds = @(foreach ($Feed in $ThreatFeeds) {
                $Feed.Apps | ForEach-Object { $_.$($Feed.AppIdField) }
            }) | Sort-Object -Unique

        # find risky apps
        $RiskyApps = $ServicePrincipals | Where-Object { $_.AppId -in $SusAppIds }

        foreach ($RiskyApp in $RiskyApps) {

            $FoundApps = $true

            # find permission grants for the app
            $AppGrants = $PermissionGrants | Where-Object { $_.ClientId -eq $RiskyApp.Id }

            # show app information
            Write-IRT "App Information:"
            foreach ($Feed in $ThreatFeeds) {
                $FeedInfo = $Feed.Apps | Where-Object { $_.$($Feed.AppIdField) -eq $RiskyApp.AppId }
                if ($FeedInfo) {
                    $ExprHash = @{
                        Name       = 'Source'
                        Expression = { $Feed.Name }
                    }
                    $Properties = $Feed.DisplayProperties + @($ExprHash)
                    $FeedInfo | Select-Object $Properties | Format-List | Out-Host
                    break
                }
            }

            # show users who have the app
            Write-IRT "Users who have this app:"
            $Users |
                Where-Object { $_.Id -in $AppGrants.PrincipalId } |
                Format-Table $UserDisplayProperties |
                Out-Host
        }

        if ($FoundApps -eq $false) {
            Write-IRT "No risky apps found."
        }
    }
}
#EndRegion '.\Public\ServicePrincipal\Find-IRTRiskyServicePrincipal.ps1' 150
#Region '.\Public\ServicePrincipal\Find-IRTServicePrincipal.ps1' -1

function Find-IRTServicePrincipal {
    <#
    .SYNOPSIS
    Finds service principals in the tenant by display name, app ID, or object ID.
    Creates $IRT_ServicePrincipalObjects.

    .DESCRIPTION
    Searches all service principals cached from the tenant against one or more search
    strings. A match is attempted against DisplayName, AppDisplayName, AppId, and Id
    using regular-expression matching (-match), so partial strings and regex patterns
    are both accepted.

    When exactly one match is found for a search string, the service principal is added
    to the result collection and a summary table is displayed. When multiple matches are
    found, the table is shown but nothing is saved -- refine the search to a single
    match, or use -AllMatches to add all of them. When no match is found, an error
    message is displayed.

    On success, results are stored in $Global:IRT_ServicePrincipalObjects (or
    $Global:IRT_<VarPrefix>ServicePrincipalObjects when -VarPrefix is supplied). Pass
    -Script to suppress all console output and return the objects directly instead.

    .PARAMETER Search
    One or more search strings. Each is matched against DisplayName, AppDisplayName,
    AppId, and Id using -match (regex-capable, case-insensitive).

    .PARAMETER VarPrefix
    Optional prefix inserted into the global variable name:
    $Global:IRT_<VarPrefix>ServicePrincipalObjects. Useful when working with multiple
    service principals simultaneously.

    .PARAMETER Cached
    Use service principal data already cached in $Global:IRT_ServicePrincipals from a
    previous call instead of fetching fresh data from Graph.

    .PARAMETER Script
    Suppresses all console output and returns matched objects directly as an array.
    Used by playbook scripts that need the objects without interactive display.

    .PARAMETER AllMatches
    When specified, adds all objects that match a given search string instead of
    rejecting the search when more than one result is found. Results are deduplicated
    by object ID, so overlapping search strings that resolve to the same service
    principal produce only one entry in the output.

    .EXAMPLE
    Find-IRTServicePrincipal MyApp
    Find a single service principal by display name.

    .EXAMPLE
    Find-IRTServicePrincipal -Search MyApp,AnotherApp
    Find multiple service principals in one call.

    .EXAMPLE
    Find-IRTServicePrincipal -Search 00000003-0000-0000-c000-000000000000
    Find by full or partial AppId (Microsoft Graph in this example).

    .EXAMPLE
    Find-IRTServicePrincipal -Search bf7573a5844f
    Find by partial object ID.

    .EXAMPLE
    Find-IRTServicePrincipal MyApp -Script
    Return the matched object directly without console output or setting the global variable.

    .OUTPUTS
    None by default. Sets $Global:IRT_ServicePrincipalObjects.
    With -Script: [object[]] of matched service principal objects.

    .NOTES
    Version: 1.1.0
    1.1.0 - Added -AllMatches to collect all matching service principals and deduplicate results.

    By default, fresh data is fetched from Graph on every call. Pass -Cached to
    skip the network request and reuse data already stored in
    $Global:IRT_ServicePrincipals from a previous call.
    #>
    [Alias(
        # ServicePrincipal
        'Find-IRTServicePrincipals',
        'Find-ServicePrincipal', 'Find-ServicePrincipals',
        'FindIRTServicePrincipal', 'FindIRTServicePrincipals',
        'FindServicePrincipal', 'FindServicePrincipals',
        # SP
        'Find-IRTSP', 'Find-IRTSPs',
        'Find-SP', 'Find-SPs',
        'FindIRTSP', 'FindIRTSPs',
        'FindSP', 'FindSPs',
        # EnterpriseApplication
        'Find-IRTEnterpriseApplication', 'Find-IRTEnterpriseApplications',
        'Find-EnterpriseApplication', 'Find-EnterpriseApplications',
        'FindIRTEnterpriseApplication', 'FindIRTEnterpriseApplications',
        'FindEnterpriseApplication', 'FindEnterpriseApplications'
    )]
    [OutputType([object[]])]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Cached,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ScriptServicePrincipalObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'AppDisplayName'
            'ServicePrincipalType'
            'AppId'
            'Id'
        )

        # fetch fresh data by default; use cache only when -Cached is specified
        if ($Cached) {
            $AllServicePrincipals = Request-GraphServicePrincipal -Cached
        } else {
            $AllServicePrincipals = Request-GraphServicePrincipal
        }
    }

    process {

        Write-IRT ''

        foreach ( $SearchString in $Search ) {

            # match against display name, app display name, app ID, or object ID
            $MatchingServicePrincipals = $AllServicePrincipals | Where-Object {
                $_.DisplayName -match $SearchString -or
                $_.AppDisplayName -match $SearchString -or
                $_.AppId -match $SearchString -or
                $_.Id -match $SearchString
            }

            if (($MatchingServicePrincipals | Measure-Object).Count -eq 1) {

                if ( -not $Script ) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingServicePrincipals | Format-Table $DisplayProperties
                }

                $SP = $MatchingServicePrincipals | Select-Object -First 1
                if ($SeenIds.Add($SP.Id)) {
                    $ScriptServicePrincipalObjects.Add($SP)
                }
            }
            elseif (($MatchingServicePrincipals | Measure-Object).Count -gt 1) {

                if ( -not $Script ) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingServicePrincipals | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($SP in $MatchingServicePrincipals) {
                        if ($SeenIds.Add($SP.Id)) {
                            $ScriptServicePrincipalObjects.Add($SP)
                        }
                    }
                } elseif (-not $Script) {
                    $Msg = 'Multiple service principals found. Refine search or use -AllMatches.'
                    Write-IRT $Msg -Level Error
                }
            }
            else {
                if ( -not $Script ) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return @($ScriptServicePrincipalObjects)
        }

        if ( $ScriptServicePrincipalObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}ServicePrincipalObjects"
                Value = @($ScriptServicePrincipalObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}ServicePrincipalObjects"

            if ( $ScriptServicePrincipalObjects.Count -gt 1 ) {
                $ScriptServicePrincipalObjects | Format-Table $DisplayProperties
            }
        }
    }
}
#EndRegion '.\Public\ServicePrincipal\Find-IRTServicePrincipal.ps1' 201
#Region '.\Public\ServicePrincipal\Get-IRTServicePrincipal.ps1' -1

function Get-IRTServicePrincipal {
    <#
	.SYNOPSIS
	Displays all service principals in the tenant, or filters by a search term.

	.NOTES
	Version: 1.3.0
	1.3.0 - Added -Excel export option.
	#>
    [Alias('GetTenantServicePrincipal', 'GetTenantServicePrincipals',
        'GetTenantSP', 'GetTenantSPs',
        'GetTenantApp', 'GetTenantApps',
        'GetTenantApplication', 'GetTenantApplications',
        'GetTenantEnterpriseApp', 'GetTenantEnterpriseApps',
        'GetAllServicePrincipals', 'GetAllSP', 'GetAllSPs',
        'GetAllApps', 'GetAllApplications', 'GetAllEnterpriseApps',
        'Get-Apps', 'Get-ServicePrincipals', 'Get-EnterpriseApps', 'Get-Applications')]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    [CmdletBinding()]
    param (
        [string] $Search,
        [switch] $Cached,
        [switch] $Excel,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $TenantId = (Get-MgContext).TenantId
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached

        # custom default display view - no ps1xml needed
        $TypeDataParams = @{
            TypeName                  = 'IRT.TenantServicePrincipal'
            DefaultDisplayPropertySet = 'CreatedDateTime', 'AppDisplayName', 'AppOwner', 'AppId'
            Force                     = $true
        }
        Update-TypeData @TypeDataParams

        # --- Resolve AppOwnerOrganizationIds via Get-IRTTenantOwner ---
        # Collect unique foreign owner org GUIDs (skip current tenant and blanks)
        $foreignOwnerIds = $ServicePrincipals |
            Select-Object -ExpandProperty AppOwnerOrganizationId -Unique |
            Where-Object { $_ -and $_ -ne $TenantId }

        $ownerDisplayNames = @{}
        if ($foreignOwnerIds) {
            $foreignOwnerIds | Get-IRTTenantOwner -ErrorAction SilentlyContinue | ForEach-Object {
                # Prefer DisplayName; fall back to GUID if Graph was unavailable
                $ownerDisplayNames[$_.TenantId] = if ($_.DisplayName) {
                    $_.DisplayName } else { $_.TenantId
                }
            }
        }
    }

    process {

        if ( $Search ) {
            Write-IRT "Service principals matching: ${Search}"
            $MatchingServicePrincipals = $ServicePrincipals |
                Where-Object { $_.DisplayName -match $Search }
        }
        else {
            Write-IRT "All service principals:"
            $MatchingServicePrincipals = $ServicePrincipals
        }

        $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($ServicePrincipal in $MatchingServicePrincipals) {

            # change date to local time
            $CreatedDateTime = $ServicePrincipal.CreatedDateTime
            if ( $CreatedDateTime ) {
                $CreatedDateTime = $CreatedDateTime.ToLocalTime()
            }

            # resolve AppOwnerOrganizationId to a display name
            $OwnerOrgId = $ServicePrincipal.AppOwnerOrganizationId
            $AppOwner = if (-not $OwnerOrgId) {
                $null
            }
            elseif ($OwnerOrgId -eq $TenantId) {
                'Current Tenant'
            }
            elseif ($ownerDisplayNames.ContainsKey($OwnerOrgId)) {
                $ownerDisplayNames[$OwnerOrgId]
            }
            else {
                $OwnerOrgId
            }

            # display sp
            $OutputTable.Add( [pscustomobject]@{
                    PSTypeName           = 'IRT.TenantServicePrincipal'
                    CreatedDateTime      = $CreatedDateTime
                    AppDisplayName       = $ServicePrincipal.AppDisplayName
                    ServicePrincipalType = $ServicePrincipal.ServicePrincipalType
                    SignInAudience       = $ServicePrincipal.SignInAudience
                    ReplyUrls            = $ServicePrincipal.ReplyUrls
                    AppOwner             = $AppOwner
                    AppId                = $ServicePrincipal.AppId
                    Id                   = $ServicePrincipal.Id
                    AccountEnabled       = $ServicePrincipal.AccountEnabled
                } )
        }
    }

    end {

        if (-not $Excel) {
            $OutputTable
        }
        else {

            $DomainName = Get-DefaultDomain
            $FileNameDateFormat = 'yy-MM-dd_HH-mm'
            $FileDateString = Get-Date -Format $FileNameDateFormat
            $ExcelOutputPath = "ServicePrincipals_${DomainName}_${FileDateString}.xlsx"
            $TitleDateString = Get-Date -Format 'MM/dd/yy HH:mm'
            $WorksheetName = 'ServicePrincipals'

            Write-IRT "Exporting Excel: ${ExcelOutputPath}"

            $ExportData = $OutputTable | Select-Object -Property @(
                'CreatedDateTime'
                'AppDisplayName'
                'ServicePrincipalType'
                'SignInAudience'
                'AppOwner'
                'AppId'
                'Id'
                @{ Name = 'ReplyUrls'; Expression = { $_.ReplyUrls -join ', ' } }
            )

            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorksheetName
                TableName     = 'ServicePrincipals'
                TableStyle    = $TableStyle
                StartRow      = 3
                AutoSize      = $true
                Passthru      = $true
            }

            try {
                $Workbook = $ExportData | Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to write Excel file: ${ExcelOutputPath}"
                return
            }

            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
            $SheetEnd = $Worksheet.Dimension.End.Address

            Set-ExcelRange -Worksheet $Worksheet -Range "A1:${SheetEnd}" -FontName $Font

            $TitleText = if ($Search) {
                "Service principals matching '${Search}' for ${DomainName} as of ${TitleDateString}"
            }
            else {
                "All service principals for ${DomainName} as of ${TitleDateString}"
            }

            $Worksheet.Cells[1, 1].Value = $TitleText
            $Worksheet.Cells[1, 1].Style.Font.Bold = $true
            $Worksheet.Cells[1, 1].Style.Font.Size = 16

            if ($Open) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
#EndRegion '.\Public\ServicePrincipal\Get-IRTServicePrincipal.ps1' 185
#Region '.\Public\ServicePrincipal\Get-IRTTenantOwner.ps1' -1

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
                    Environment         = $cached.Environment
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
            $TenantCloud = Get-IRTTenantOidc -TenantId $Tid
            $cloudName = $TenantCloud?.Cloud

            if (-not $TenantCloud -and -not $graphSource) {
                Write-Warning "Tenant '$Tid' was not found."
                [pscustomobject]@{ TenantId = $Tid; Exists = $false }
                continue
            }

            $environment = $TenantCloud?.Environment

            # --- Output ---
            [pscustomobject]@{
                TenantId            = $tid
                Exists              = $true
                DisplayName         = $displayName
                DefaultDomain       = $defaultDomain
                FederationBrandName = $fedBrandName
                Environment         = $environment
                Cloud               = $cloudName
                GraphHost           = $TenantCloud?.msgraph_host
                TokenEndpoint       = $TenantCloud?.token_endpoint
                Source              = if ($graphSource) { 'Graph' } else { 'PublicEndpoints' }
            }

            # --- Update global table and queue for cache write ---
            if (-not $NoCache) {
                $cacheEntry = [pscustomobject]@{
                    TenantId            = $tid
                    DisplayName         = $displayName
                    DefaultDomain       = $defaultDomain
                    FederationBrandName = $fedBrandName
                    Environment         = $environment
                    Cloud               = $cloudName
                    GraphHost           = $TenantCloud?.msgraph_host
                    TokenEndpoint       = $TenantCloud?.token_endpoint
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
#EndRegion '.\Public\ServicePrincipal\Get-IRTTenantOwner.ps1' 232
#Region '.\Public\ServicePrincipal\Get-IRTUserServicePrincipal.ps1' -1

function Get-IRTUserServicePrincipal {
    <#
    .SYNOPSIS
    Displays user's Oauth2 permission grants. (Applications they have granted consent to)

    .DESCRIPTION
    Retrieves all OAuth2 permission grants for one or more Entra ID users and displays the
    applications they have personally consented to. Each row shows the app name, granted
    scopes, and the consent date if available.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more Entra ID user objects to query. Falls back to global session objects if
    omitted. Accepts pipeline input.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Cached
    Use pre-cached Graph service principal data instead of making new API calls.

    .EXAMPLE
    Get-IRTUserServicePrincipal
    Shows OAuth app consents for the user in the global session.

    .EXAMPLE
    Get-IRTUserServicePrincipal -UserObject $User
    Shows OAuth app consents for a specific user.

    .OUTPUTS
    None. Results are displayed in the console and optionally exported to Excel.
    #>
    [Alias('UserApps', 'UserSPs',
        'GetUserSP', 'GetUserSPs',
        'GetUserApp', 'GetUserApps',
        'GetUserApplication', 'GetUserApplications',
        'GetUserServicePrincipal', 'GetUserServicePrincipals',
        'GetUserEnterpriseApp', 'GetUserEnterpriseApps',
        'Get-UserApplication')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Open = $true,
        [switch] $Cached
    )

    # FIXME - Search UAL for user consent events to show dates?

    begin {
        Update-IRTToken -Service 'Graph'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'UserAppConsents'

        # if not passed directly, find global user object
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # get client domain name for file output
        $DomainName = Get-DefaultDomain

        # prefetch graph data once
        $Grants = Request-GraphOauth2Grant -Cached:$Cached
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserId = $ScriptUserObject.Id
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # filenames
            $DateStamp = Get-Date -Format $FileNameDateFormat
            $XmlOutputPath = "UserSPs_Raw_${DomainName}_${UserName}_${DateStamp}.xml"
            $ExcelOutputPath = "UserSPs_${DomainName}_${UserName}_${DateStamp}.xlsx"

            # worksheet title
            $TitleStamp = (Get-Date).ToString("M/d/yy h:mmtt").ToLower()
            $WorksheetTitle = "Application consent for ${UserEmail} on ${TitleStamp}."

            # filter down to grants that apply to user
            $UserGrants = $Grants | Where-Object { $_.PrincipalId -eq $UserId }

            foreach ( $Grant in $UserGrants ) {

                # find application
                $Client = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ClientId }
                $Resource = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ResourceId }

                # find friendly name, or revert to id
                $AppName = if ($Client -and $Client.DisplayName) {
                    $Client.DisplayName
                }
                else {
                    $Grant.ClientId
                }
                $ResourceName = if ($Resource -and $Resource.DisplayName) {
                    $Resource.DisplayName
                }
                else {
                    $Grant.ResourceId
                }

                # add row
                $OutputTable.Add(
                    [pscustomobject]@{
                        User        = $UserEmail
                        Application = $AppName
                        Resource    = $ResourceName
                        Scopes       = $Grant.Scope
                    }
                )
            }

            if (($OutputTable | Measure-Object).Count -eq 0) {
                Write-IRT "No user consent applications." -Level Warn
                continue
            }

            if ($Xml) {
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $UserGrants | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            #region EXCEL
            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorkSheetName
                Title         = $WorksheetTitle
                TableStyle    = $TableStyle
                AutoSize      = $true
                FreezeTopRow  = $true
                Passthru      = $true
            }
            try {
                $Workbook = $OutputTable |
                    Select-Object User, Application, Resource, Scope |
                    Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to open new Excel document."
                if (Get-YesNo "Try closing open files.") {
                    try {
                        $Workbook = $OutputTable |
                            Select-Object User, Application, Resource, Scope |
                            Export-Excel @ExcelParams
                    }
                    catch {
                        throw "Unable to open new Excel document. Exiting."
                    }
                }
                else {
                    throw
                }
            }

            # post-formatting
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]
            $SheetStartColumn = ($Worksheet.Dimension.Start.Column) | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = ($Worksheet.Dimension.End.Column)   | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row

            #region FORMATTING

            # set font and size for full used range
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            Set-ExcelRange @SetParams

            # add left side border
            $BorderParams = @{
                Worksheet = $Worksheet
                Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            #region OUTPUT

            # save and open/close
            Write-IRT "Exporting to: ${ExcelOutputPath}"
            if ($Open) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
#EndRegion '.\Public\ServicePrincipal\Get-IRTUserServicePrincipal.ps1' 227
#Region '.\Public\ServicePrincipal\Open-IRTTenantOwnerCSV.ps1' -1

function Open-IRTTenantOwnerCSV {
    <#
    .SYNOPSIS
    Opens the local tenant info cache CSV in the default application.

    .DESCRIPTION
    Opens $env:APPDATA\<ModuleName>\TenantOwnerInfo.csv in the system default
    application (typically Excel or Notepad), where <ModuleName> is resolved at
    runtime. If the file does not exist yet, a warning is displayed.

    .EXAMPLE
    Open-IRTTenantOwnerCSV

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param ()

    $moduleName = $MyInvocation.MyCommand.ModuleName
    $JpParams = @{
        Path                = $env:APPDATA
        ChildPath           = $moduleName
        AdditionalChildPath = 'TenantOwnerInfo.csv'
    }
    $cachePath = Join-Path @JpParams

    if (-not (Test-Path $cachePath)) {
        $Msg = "Tenant info cache not found at '$cachePath'. " +
        "Run Get-IRTTenantOwner first to populate it."
        Write-Warning $Msg
        return
    }

    Write-Verbose "Opening $cachePath"
    Start-Process $cachePath
}
#EndRegion '.\Public\ServicePrincipal\Open-IRTTenantOwnerCSV.ps1' 38
#Region '.\Public\ServicePrincipal\Open-IRTTenantSheet.ps1' -1

function Open-IRTTenantSheet {
    <#
    .SYNOPSIS
    Opens the tenants worksheet for editing. Creates it from the template if it doesn't exist.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Open-IRTTenantWorksheet', 'OpenIRTTenantWorksheet',
        'OpenIRTTenantSheet', 'IRTTenantSheet'
    )]
    [CmdletBinding()]
    param (
        [string] $TenantFile
    )

    begin {
        if (-not $TenantFile) {
            $TenantFile = $Global:IRT_Config.TenantsSheetPath
        }
    }

    process {

        if (-not ( Test-Path $TenantFile )) {

            $ConfigDir = Split-Path $TenantFile
            $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
            $TemplateParams = @{
                Path                = $ModuleRoot
                ChildPath           = 'Data'
                AdditionalChildPath = 'TenantsTemplate.xlsx'
            }
            $TemplateFile = Join-Path @TemplateParams

            if (-not (Test-Path $ConfigDir)) {
                $null = New-Item -ItemType Directory -Path $ConfigDir -Force
            }

            Copy-Item -Path $TemplateFile -Destination $TenantFile
            Write-IRT "Created tenants worksheet file from template: ${TenantFile}"
        }

        Invoke-Item $TenantFile
    }
}
#EndRegion '.\Public\ServicePrincipal\Open-IRTTenantSheet.ps1' 51
#Region '.\Public\ServicePrincipal\Show-IRTServicePrincipal.ps1' -1

function Show-IRTServicePrincipal {
    <#
    .SYNOPSIS
    Displays detailed service principal properties for objects produced by Find-ServicePrincipal.

    .DESCRIPTION
    Retrieves the full Graph service principal object using a curated property list and
    displays it as a formatted tree in the console via Show-GraphServicePrincipalTree.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. This lets you run Find-ServicePrincipal first to select a target, then run
    Show-IRTServicePrincipal with no arguments to display it.

    Properties retrieved include credentials (key and password certificates), OAuth2
    permission scopes, app roles, reply URLs, SSO settings, publisher verification,
    and all standard identity fields.

    After the property tree, four additional tables are displayed:
    - OAuth2 Permission Grants: delegated permissions the SP has been granted (user or
      admin consent), with the resource display name resolved from the resource ID.
    - App Role Assignments: application permissions (admin-consented app roles) assigned
      to the SP, with the role GUID resolved to the human-readable permission value.
    - Directory Role Memberships: Entra admin roles (e.g. Cloud Application Administrator)
      the SP has been assigned to. Uses the IRT_DirectoryRoles cache if populated.
    - App Role Assigned To: users, groups, and SPs that have been granted access to this app.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects to display. Falls back to
    $Global:IRT_ServicePrincipalObjects if omitted.

    .PARAMETER Cached
    Pass -Cached to all Request-* calls so previously fetched Graph data is reused
    instead of making new API calls. Without this switch, each Request-* call fetches
    fresh data from Graph.

    .EXAMPLE
    Find-ServicePrincipal MyApp
    Show-IRTServicePrincipal
    Two-step workflow: find then display.

    .EXAMPLE
    Show-IRTServicePrincipal
    Display info for the service principal already stored in the global session.

    .EXAMPLE
    Show-IRTServicePrincipal -ServicePrincipalObject $SP
    Display info for a specific service principal object passed directly.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.3.0
    #>
    [Alias(
        'Show-IRTServicePrincipals',
        'Show-ServicePrincipal',
        'ShowIRTServicePrincipal', 'ShowIRTServicePrincipals',
        'ShowServicePrincipal', 'ShowServicePrincipals',
        'ShowSP', 'ShowSPs',
        'ShowApp', 'ShowApps',
        'ShowApplication', 'ShowApplications',
        'ShowEnterpriseApp', 'ShowEnterpriseApps',
        'ShowEnterpriseApplication', 'ShowEnterpriseApplications'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Graph'
        if ( -not $ServicePrincipalObject -or $ServicePrincipalObject.Count -eq 0 ) {
            $ScriptServicePrincipalObjects = @( $Global:IRT_ServicePrincipalObjects )
            if ( -not $ScriptServicePrincipalObjects -or
                $ScriptServicePrincipalObjects.Count -eq 0
            ) {
                throw "No service principal objects passed or found in global variables."
            }
        }
        else {
            $ScriptServicePrincipalObjects = $ServicePrincipalObject
        }

        $SelectProps = @(
            'accountEnabled'
            'alternativeNames'
            'appDescription'
            'appDisplayName'
            'appId'
            'appOwnerOrganizationId'
            'appRoles'
            'createdDateTime'
            'deletedDateTime'
            'description'
            'disabledByMicrosoftStatus'
            'displayName'
            'errorUrl'
            'homepage'
            'id'
            'info'
            'keyCredentials'
            'loginUrl'
            'logoutUrl'
            'notes'
            'notificationEmailAddresses'
            'oauth2PermissionScopes'
            'passwordCredentials'
            'preferredSingleSignOnMode'
            'preferredTokenSigningKeyThumbprint'
            'publisherName'
            'replyUrls'
            'samlSingleSignOnSettings'
            'servicePrincipalNames'
            'servicePrincipalType'
            'signInAudience'
            'tags'
            'tokenEncryptionKeyId'
            'verifiedPublisher'
        )
    }

    process {

        foreach ($ScriptServicePrincipalObject in $ScriptServicePrincipalObjects) {

            $SpName = if ($ScriptServicePrincipalObject.AppDisplayName) {
                $ScriptServicePrincipalObject.AppDisplayName
            }
            else {
                $ScriptServicePrincipalObject.DisplayName
            }

            try {
                $GetSPParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    Property           = $SelectProps
                    ErrorAction        = 'Stop'
                }
                $FullSP = Get-MgServicePrincipal @GetSPParams

                Write-IRT "Showing service principal properties for: ${SpName}"
                $FullSP | Show-GraphServicePrincipalTree | Out-Host
            }
            catch {
                $Msg = "Failed to get service principal object: $($_.Exception.Message)"
                Write-IRT $Msg -Level Error
            }

            # OAuth2 Permission Grants (delegated permissions)
            try {
                $GrantsParams = @{
                    Cached = $Cached
                    Return = 'tablebyclientid'
                }
                $GrantsByClientId = Request-GraphOauth2Grant @GrantsParams
                $OAuth2Grants = @( $GrantsByClientId[$ScriptServicePrincipalObject.Id] )
                $SPsById = Request-GraphServicePrincipal -Cached:$Cached -Return 'tablebyid'
                $UsersById = Request-GraphUser -Cached:$Cached -Return 'tablebyid'

                Write-IRT "OAuth2 Permission Grants (delegated) for: ${SpName}"
                if ($OAuth2Grants.Count -gt 0) {
                    $OAuth2Grants | ForEach-Object {
                        $User = if ($_.ConsentType -eq 'Principal') {
                            $UsersById[$_.PrincipalId]
                        } else {
                            $null
                        }
                        $ResourceSP = $SPsById[$_.ResourceId]
                        $ResourceVal = ($ResourceSP ? $ResourceSP.DisplayName : $null) ??
                        $_.ResourceId
                        [PSCustomObject]@{
                            Resource          = $ResourceVal
                            ConsentType       = $_.ConsentType
                            DisplayName       = $User ? $User.DisplayName : $null
                            UserPrincipalName = $User ? $User.UserPrincipalName : $null
                            Scope             = $_.Scope
                            ExpiryTime        = $_.ExpiryTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No OAuth2 permission grants found." -Level Warn
                }
            }
            catch {
                $Msg = "Failed to get OAuth2 permission grants: $($_.Exception.Message)"
                Write-IRT $Msg -Level Error
            }

            # App Role Assignments (application permissions)
            try {
                $GetAssignmentParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    All                = $true
                    ErrorAction        = 'Stop'
                }
                $AppRoleAssignments = Get-MgServicePrincipalAppRoleAssignment @GetAssignmentParams

                Write-IRT "App Role Assignments (application permissions) for: ${SpName}"
                if ($AppRoleAssignments.Count -gt 0) {
                    $RoleLookup = @{}
                    foreach ($Assignment in $AppRoleAssignments) {
                        if (-not $RoleLookup.ContainsKey($Assignment.ResourceId)) {
                            $GetRoleResourceParams = @{
                                ServicePrincipalId = $Assignment.ResourceId
                                Property           = 'appRoles'
                                ErrorAction        = 'SilentlyContinue'
                            }
                            $ResourceSP = Get-MgServicePrincipal @GetRoleResourceParams
                            $RoleLookup[$Assignment.ResourceId] = @{}
                            if ($ResourceSP) {
                                foreach ($Role in $ResourceSP.AppRoles) {
                                    $RoleIdKey = $Role.Id.ToString()
                                    $RoleLookup[$Assignment.ResourceId][$RoleIdKey] = $Role.Value
                                }
                            }
                        }
                    }

                    $AppRoleAssignments | ForEach-Object {
                        $RoleName = $RoleLookup[$_.ResourceId][$_.AppRoleId.ToString()]
                        $PermValue = if ($RoleName) { $RoleName } else { $_.AppRoleId.ToString() }
                        [PSCustomObject]@{
                            Resource        = $_.ResourceDisplayName
                            Permission      = $PermValue
                            CreatedDateTime = $_.CreatedDateTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No app role assignments found." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get app role assignments: $($_.Exception.Message)" -Level Error
            }

            # Directory Role Memberships (Entra admin roles assigned to this SP)
            try {
                $DirRoleParams = @{
                    Filter      = "principalId eq '$($ScriptServicePrincipalObject.Id)'"
                    All         = $true
                    ErrorAction = 'Stop'
                }
                $RoleAssignments = Get-MgRoleManagementDirectoryRoleAssignment @DirRoleParams
                $DrtParams = @{
                    Cached = $Cached
                    Return = 'tablebyid'
                }
                $RoleTemplatesById = Request-DirectoryRoleTemplate @DrtParams

                Write-IRT "Directory Role Memberships (Entra admin roles) for: ${SpName}"
                if ($RoleAssignments.Count -gt 0) {
                    $RoleAssignments | ForEach-Object {
                        $TplEntry = $RoleTemplatesById[$_.RoleDefinitionId]
                        $RoleName = ($TplEntry ? $TplEntry.DisplayName : $null) ??
                        $_.RoleDefinitionId
                        [PSCustomObject]@{
                            DisplayName      = $RoleName
                            DirectoryScopeId = $_.DirectoryScopeId
                        }
                    } | Format-Table -AutoSize | Out-Host
                } else {
                    Write-IRT "No directory role memberships found." -Level Warn
                }
            }
            catch {
                $Msg = "Failed to get directory role memberships: $($_.Exception.Message)"
                Write-IRT $Msg -Level Error
            }

            # App Role Assigned To (users/groups/SPs that have been given access to this app)
            try {
                $GetAssignedToParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    All                = $true
                    ErrorAction        = 'Stop'
                }
                $AssignedTo = Get-MgServicePrincipalAppRoleAssignedTo @GetAssignedToParams

                Write-IRT "App Role Assigned To (principals with access) for: ${SpName}"
                if ($AssignedTo.Count -gt 0) {
                    $AppRoleLookup = @{ '00000000-0000-0000-0000-000000000000' = 'Default Access' }
                    if ($FullSP) {
                        foreach ($Role in $FullSP.AppRoles) {
                            $AppRoleLookup[$Role.Id.ToString()] = $Role.DisplayName
                        }
                    }

                    $AssignedTo | ForEach-Object {
                        $RoleName = $AppRoleLookup[$_.AppRoleId.ToString()]
                        $AppRoleVal = if ($RoleName) { $RoleName } else { $_.AppRoleId.ToString() }
                        [PSCustomObject]@{
                            PrincipalDisplayName = $_.PrincipalDisplayName
                            PrincipalType        = $_.PrincipalType
                            AppRole              = $AppRoleVal
                            CreatedDateTime      = $_.CreatedDateTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No principals assigned to this app." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get app role assigned to: $($_.Exception.Message)" -Level Error
            }
        }
    }
}
#EndRegion '.\Public\ServicePrincipal\Show-IRTServicePrincipal.ps1' 316
#Region '.\Public\UnifiedAuditLog\Get-IRTUnifiedAuditLog.ps1' -1

function Get-IRTUnifiedAuditLog {
    <#
    .SYNOPSIS
    Runs multiple queries to pull all Unified Audit Log records related to a specific user.

    .DESCRIPTION
    Queries the Microsoft 365 Unified Audit Log via Exchange Online for activity related
    to one or more users, a service principal, or all users in the tenant. Runs several
    categorised queries in parallel (e.g. SharePoint, Exchange, Teams, Azure AD) and
    exports each category to a separate sheet in an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.
    Requires an active Exchange Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Mutually exclusive with -AllUsers and
    -ServicePrincipal. Falls back to global session objects if omitted.

    .PARAMETER AllUsers
    Query the UAL for all users in the tenant. Mutually exclusive with -UserObject and
    -ServicePrincipal.

    .PARAMETER ServicePrincipal
    One or more service principal objects to query. Mutually exclusive with -UserObject
    and -AllUsers.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER Operation
    Filter results to specific UAL operation names.

    .PARAMETER RiskyOperation
    Filter to a predefined list of high-risk operations.

    .PARAMETER SignInLog
    Filter to only UAL sign-in operations.

    .PARAMETER FreeText
    One or more free-text search strings passed to Search-UnifiedAuditLog.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER WaitOnMessageTrace
    Wait for any pending message trace jobs before querying. Intended for use when running
    playbook. (running functions in parallel) Default: $false.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data where available.

    .EXAMPLE
    Get-IRTUnifiedAuditLog
    Queries the UAL for the last 30 days for the user in the global session.

    .EXAMPLE
    Get-IRTUnifiedAuditLog -UserObject $User -Days 90
    Queries 90 days of UAL activity for a specific user.

    .EXAMPLE
    Get-IRTUnifiedAuditLog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'
    Finds all FileDeleted events for any user during April 2026.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.6.0
    1.6.0 - Added profile tags to allow generating specific sheets in Show-IRTUnifiedAuditLog.
    1.5.1 - Added function name to all output.
    1.5.0 - Added -AllUsers option, added test timers.
    1.4.0 - Updating to add metadata object, use shorter file names.
    1.3.0 - Updated to output objects.
    #>
    [Alias('GetUALog', 'GetUALogs', 'UALog', 'UALogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'UserObject')]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [Parameter(Position = 0, ParameterSetName = 'ServicePrincipal')]
        [Alias( 'ServicePrincipals' )]
        [psobject[]] $ServicePrincipal,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        [Alias('Operations')]
        [string[]] $Operation,
        [Alias('RiskyOperations')]
        [switch] $RiskyOperation,
        [Alias('SignInLogs')]
        [switch] $SignInLog,
        [string[]] $FreeText,

        [boolean] $Excel = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # query profiles - add new entries here to support additional modes
        $ProfileTable = [ordered]@{
            Default = [pscustomobject]@{
                FilePrefix   = 'UnifiedAuditLogs'
                SheetTitle   = 'Unified audit logs'
                DefaultDays  = 1
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = $null
            }
            RiskyOperations = [pscustomobject]@{
                FilePrefix   = 'UALRiskyOperations'
                SheetTitle   = 'UAL risky operations'
                DefaultDays  = 180
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = $null
            }
            SignInLogs = [pscustomobject]@{
                FilePrefix   = 'UALSignInLogs'
                SheetTitle   = 'UAL sign-in logs'
                DefaultDays  = 180
                Operations   = [string[]]@('UserLoggedIn', 'UserLoggedOff', 'UserLoginFailed')
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = 'SignInLogs'
            }
        }
        $ActiveProfile = switch ($true) {
            $RiskyOperation { $ProfileTable['RiskyOperations']; break }
            $SignInLog { $ProfileTable['SignInLogs']; break }
            default { $ProfileTable['Default'] }
        }

        # get/create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $LoopObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $LoopObjects = Get-GlobalUserObject

                    # if none found, exit
                    if ( -not $LoopObjects -or $LoopObjects.Count -eq 0 ) {
                        $Msg = "No user objects passed or found in global variables."
                        Write-IRT $Msg -Level Error
                        return
                    }
                    if (($LoopObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used, ' +
                            'no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'AllUsers' {
                $null = $AllUsers  # switch controls parameter set; value not needed
                # build user object with null principal name
                $LoopObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = 'AllUsers'
                    }
                )
            }
            'ServicePrincipal' {
                $LoopObjects = $ServicePrincipal
            }
        }

        # get client domain name for file output
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-AcceptedDomain $Elapsed"
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1

        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $ActiveProfile.DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc

        # set file name date to query end date
        $FileNameDateString = $EndDateUtc.ToLocalTime().ToString('yy-MM-dd_HH-mm')

        $OperationsSet = [System.Collections.Generic.Hashset[string]]::new()
        # add user specified operations
        foreach ($o in $Operation) { [void]$OperationsSet.Add($o) }
        # populate profile operations
        if ($RiskyOperation) {
            # import alloperations sheet
            $OperationsSheetPath = $Global:IRT_Config.AllOperationsSheetPath
            $ExcelParams = @{
                Path          = $OperationsSheetPath
                WorksheetName = 'Operations'
            }
            $OperationsSheetData = Import-Excel @ExcelParams

            # get high risk operations and store in active profile
            $HighRisk = $OperationsSheetData | Where-Object { $_.Risk -eq 'High' }
            $ActiveProfile.Operations = $HighRisk.Operation
        }
        # add profile operations to set
        foreach ($o in $ActiveProfile.Operations) { [void]$OperationsSet.Add($o) }
    }

    process {

        #region USER LOOP

        foreach ($LoopObject in $LoopObjects) {

            $AllLogs = [System.Collections.Generic.List[psobject]]::new()

            # users
            switch ( $ParameterSet ) {
                'UserObject' {
                    $UserId = $LoopObject.Id
                    $UserIdNoDashes = $UserId -replace '-', ''
                    $UserEmail = $LoopObject.UserPrincipalName
                    $ObjectName = $UserEmail -split '@' | Select-Object -First 1
                }
                'AllUsers' {
                    $ObjectName = $DomainName
                    # don't add a user filter
                }
                'ServicePrincipal' {
                    $ServicePrincipalId = $LoopObject.Id
                    $ServicePrincipalIdNoDash = $LoopObject.Id -replace '-', ''
                    $AppId = $LoopObject.AppId
                    $AppIdNoDash = $LoopObject.AppId -replace '-', ''
                    $ObjectName = $LoopObject.DisplayName -replace '[^a-zA-Z0-9]', ''
                }
            }
            $FileNamePrefix = $ActiveProfile.FilePrefix
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}" +
            "_${ObjectName}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleSuffix = " for ${ObjectName}. Covers ${Days} days, " +
            "${TitleStartDate} to ${TitleEndDate}."

            # build query params
            $BaseParams = @{
                ResultSize     = 5000
                SessionCommand = 'ReturnLargeSet'
                Formatted      = $true
                StartDate      = $StartDateUtc
                EndDate        = $EndDateUtc
            }

            # add operations, if specified
            if (($OperationsSet | Measure-Object).Count -gt 0) {
                $BaseParams['Operations'] = $OperationsSet
            }

            #region QUERY TABLE
            switch ( $ParameterSet ) {
                'UserObject' {
                    $QueryTable = [ordered]@{
                        '1' = @{
                            Params = @{
                                UserIds = $UserEmail, $UserId, $UserIdNoDashes
                            }
                            ConsoleOutput = "Running UserIds query for ${UserEmail}, " +
                            "${UserId}, ${UserIdNoDashes}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $UserEmail
                            }
                            ConsoleOutput = "Running Freetext query for ${UserEmail}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $UserId
                            }
                            ConsoleOutput = "Running Freetext query for ${UserId}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $UserIdNoDashes
                            }
                            ConsoleOutput = "Running Freetext query for ${UserIdNoDashes}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 5
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running FreeText '${FreeTextString}' query."
                            }
                            $Key++
                        }
                    }
                }
                'AllUsers' {
                    if ($FreeText) {
                        $QueryTable = [ordered]@{}
                        $Key = 1
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running FreeText '${FreeTextString}' " +
                                "query for all users."
                            }
                            $Key++
                        }
                    }
                    else {
                        $QueryTable = [ordered]@{
                            '1' = @{
                                Params = @{}
                                ConsoleOutput   = "Running query for all users."
                            }
                        }
                    }
                }
                'ServicePrincipal' {
                    $QueryTable = [ordered]@{
                        '1' = @{
                            Params = @{
                                UserIds = @(
                                    $ServicePrincipalId
                                    $ServicePrincipalIdNoDash
                                    $AppId
                                    $AppIdNoDash
                                )
                            }
                            ConsoleOutput = "Running UserIds query for " +
                            "${ServicePrincipalId}, ${ServicePrincipalIdNoDash}, " +
                            "${AppId}, ${AppIdNoDash}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $ServicePrincipalId
                            }
                            ConsoleOutput = "Running Freetext query for ${ServicePrincipalId}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $ServicePrincipalIdNoDash
                            }
                            ConsoleOutput = "Running Freetext query for ${ServicePrincipalIdNoDash}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $AppId
                            }
                            ConsoleOutput = "Running Freetext query for ${AppId}"
                        }
                        '5' = @{
                            Params = @{
                                FreeText = $AppIdNoDash
                            }
                            ConsoleOutput = "Running Freetext query for ${AppIdNoDash}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 6
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running Freetext query for '${FreeTextString}'"
                            }
                            $Key++
                        }
                    }
                }
            }


            #region RUN QUERIES
            foreach ( $QueryDict in $QueryTable.GetEnumerator() ) {

                # build final params
                $FirstPageParams = @{}
                # add params from table
                $BaseParams.GetEnumerator() | ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }
                $QueryDict.Value.Params.GetEnumerator() |
                    ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }

                $ConsoleOutput = $QueryDict.Value.ConsoleOutput

                # run query
                Write-IRT $ConsoleOutput
                $QueryKey = $QueryDict.Key
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Search-UnifiedAuditLog query $QueryKey $Elapsed"
                $Page = Search-UnifiedAuditLog @FirstPageParams
                $LogCount = ($Page | Measure-Object).Count

                if ($LogCount -gt 0) {

                    Write-IRT "Retrieved ${LogCount} logs."

                    # add to list
                    foreach ($i in $Page) { $AllLogs.Add($i) }

                    # extract sessionid for paging
                    $SessionId = $Page[0].SessionId
                    $PageCount = 2
                    $NextPageParams = $FirstPageParams
                    $NextPageParams['SessionId'] = $SessionId
                }
                else {
                    Write-IRT "Retrieved 0 logs." -Level Warn
                }

                # retrieve pages
                while ($LogCount -eq 5000) {

                    Write-IRT "Requesting page ${PageCount}."
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Search-UnifiedAuditLog page $PageCount $Elapsed"
                    $Page = Search-UnifiedAuditLog @NextPageParams
                    $LogCount = @($Page).Count

                    if ( $LogCount -gt 0 ) {

                        Write-IRT "Retrieved ${LogCount} logs."

                        # add to list
                        foreach ($i in $Page) { $AllLogs.Add($i) }

                        # extract sessionid for paging
                        $SessionId = $Page[0].SessionId
                    }
                    else {
                        Write-IRT "Retrieved 0 logs." -Level Warn
                    }

                    $PageCount++
                }
            }

            # exit if no logs returned
            if (($AllLogs | Measure-Object).Count -eq 0) {
                Write-IRT "0 total logs retrieved." -Level Warn
                return
            }

            #region UNIQUE, SORT
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Dedupliacation, sorting $Elapsed"
            # remove duplicates
            $UniqueLogIds = [System.Collections.Generic.HashSet[string]]::new()
            $Logs = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Log in $AllLogs) {
                if ($UniqueLogIds.Add([string]$Log.Identity)) {
                    $null = $Logs.Add($Log)
                }
            }
            # build comparison script
            $PropertyName = 'CreationDate'
            $Descending = $true
            $Comparison = [System.Comparison[PSObject]] {
                param($X, $Y)
                $Result = $X.$PropertyName.CompareTo($Y.$PropertyName)
                if ( $Descending ) {
                    return -1 * $Result
                }
                return $Result
            }
            $Logs.Sort($Comparison)

            #region OUTPUT

            # count actual logs before adding metadata
            $TotalLogCount = ($Logs | Measure-Object).Count
            if ($TotalLogCount -gt 0) {
                Write-IRT "Total retrieved ${TotalLogCount} logs."
            }
            else {
                Write-IRT "Total retrieved 0 logs." -Level Warn
                return
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata = $true
                    FileNamePrefix = $FileNamePrefix
                    FileName = $FileNameBase
                    SheetTitle = $ActiveProfile.SheetTitle
                    Title = "$($ActiveProfile.SheetTitle)${TitleSuffix}"
                    TitleSuffix = $TitleSuffix
                    ProfileTag = $ActiveProfile.ProfileTag
                }
            )

            # export to xml
            if ($Xml) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Starting XML export $Elapsed"
                Write-IRT "Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }

            # export excel spreadsheet
            if ($Excel) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Starting Excel export $Elapsed"
                $Params = @{
                    Log = $Logs
                    WaitOnMessageTrace = $WaitOnMessageTrace
                    Cached = $Cached
                }
                & $ActiveProfile.ShowFunction @Params
            }
        }
    }
}
#EndRegion '.\Public\UnifiedAuditLog\Get-IRTUnifiedAuditLog.ps1' 561
#Region '.\Public\UnifiedAuditLog\Open-IRTAllOperationsSheet.ps1' -1

function Open-IRTAllOperationsSheet {
    <#
    .SYNOPSIS
    Opens the unified audit log all-operations reference spreadsheet.

    .DESCRIPTION
    Opens the UALAllOperations.xlsx workbook for viewing or editing.
    Uses the path configured in AllOperationsSheetPath (via Set-IRTConfig) when set,
    otherwise opens the default file bundled with the module under the Data\ folder.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('Open-AllOperationsSheet', 'IRTAllOperationsSheet')]
    [CmdletBinding()]
    param ()

    process {
        $SheetPath = $Global:IRT_Config.AllOperationsSheetPath

        if (-not (Test-Path $SheetPath)) {
            throw "All-operations spreadsheet not found: ${SheetPath}"
        }

        Invoke-Item $SheetPath
    }
}
#EndRegion '.\Public\UnifiedAuditLog\Open-IRTAllOperationsSheet.ps1' 28
#Region '.\Public\UnifiedAuditLog\Show-IRTUnifiedAuditLog.ps1' -1

function Show-IRTUnifiedAuditLog {
    <#
	.SYNOPSIS
	Parse and show unified audit logs.

	.NOTES
	Version: 1.0.1
    1.0.1 - Added option pass raw log objects, not just import from file.
	#>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [int] $MaxWaitMinutes = 15,
        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Import-CliXml $Elapsed"
                $RawLog = Import-CliXml -Path $ResolvedXmlPath
                [System.Collections.Generic.List[PSObject]] $Log = $RawLog
            }
            catch {
                $_
                Write-IRT "Error importing from ${XmlPath}." -Level Error
                return
            }
        }

        #region METADATA
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # sheet registry - maps operation types to their dedicated sheet builders
        $SheetRegistry = [ordered]@{
            'AllOperations' = @{
                Operations    = @()   # empty = matches all logs
                BuildFunction = 'Build-AllOperationSheet'
                SheetName     = $Metadata.FileNamePrefix
                SheetTitle    = $Metadata.SheetTitle
            }
            'SignInLogs' = @{
                Operations    = @('UserLoggedIn', 'UserLoginFailed', 'UserLoggedOff')
                BuildFunction = 'Build-UserLoginOperationsSheet'
                SheetName     = 'SignInLogs'
                SheetTitle    = 'UAL sign-in logs'
            }
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + ".xlsx"

        # import alloperations sheet
        $OperationsSheetData = $Global:IRT_UalOperationsData
    }

    process {

        #region FIRST LOOP

        foreach ($LogEntry in $Log) {
            # convert audit data to powershell objects
            $LogEntry.AuditData = $LogEntry.AuditData | ConvertFrom-Json -Depth 10
        }

        #region WAIT ON MESSAGE TRACE
        # resolve message trace table once before the row loop
        $MessageTraceTable = $null
        if ($WaitOnMessageTrace) {
            $WaitInterval = 15
            $WaitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # wait for both user and AllUsers message traces to complete via WaitFlags
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Waiting on message trace $Elapsed"
            if ($Global:IRT_WaitFlags) {
                while (-not ($Global:IRT_WaitFlags.MessageTraceUserDone -and
                        $Global:IRT_WaitFlags.MessageTraceAllUsersDone)) {
                    if ($WaitStopwatch.Elapsed.TotalMinutes -ge $MaxWaitMinutes) {
                        $Msg = "Timed out after ${MaxWaitMinutes} minutes waiting on " +
                        "message trace. Continuing without subjects."
                        Write-IRT $Msg -Level Error
                        break
                    }
                    $WaitElapsed = $WaitStopwatch.Elapsed.ToString('mm\:ss')
                    $UserDone = $Global:IRT_WaitFlags.MessageTraceUserDone
                    $AllDone = $Global:IRT_WaitFlags.MessageTraceAllUsersDone
                    Write-IRT "Waiting on message trace..." -Level Warn
                    $WaitMsg = "${FunctionName}: MessageTrace wait ${WaitElapsed} elapsed. " +
                    "UserDone=${UserDone}, AllUsersDone=${AllDone}"
                    Write-Verbose $WaitMsg
                    Start-Sleep -Seconds $WaitInterval
                }
            }
        }

        # load message trace table from global
        if ($Global:IRT_MessageTraceTable -is [hashtable] -and
            $Global:IRT_MessageTraceTable.Count -gt 0) {
            $MessageTraceTable = $Global:IRT_MessageTraceTable
        }

        #region AUTO-DETECT SHEETS
        # build set of operations present in the logs
        $LogEntryOperations = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($LogEntry in $Log) {
            if ($LogEntry.AuditData.Operation) {
                [void]$LogEntryOperations.Add($LogEntry.AuditData.Operation)
            }
        }

        $MatchedSheets = [System.Collections.Generic.List[hashtable]]::new()

        if ($Metadata.ProfileTag -and $SheetRegistry.Contains($Metadata.ProfileTag)) {
            # profile-driven: only the tagged sheet
            $MatchedSheets.Add($SheetRegistry[$Metadata.ProfileTag])
        }
        else {
            # default: always include AllOperations, then add any specialized
            # sheets whose operations are present in the logs
            $MatchedSheets.Add($SheetRegistry['AllOperations'])
            foreach ($Key in $SheetRegistry.Keys) {
                if ($Key -eq 'AllOperations') { continue }
                $SheetEntry = $SheetRegistry[$Key]
                foreach ($Op in $SheetEntry.Operations) {
                    if ($LogEntryOperations.Contains($Op)) {
                        $MatchedSheets.Add($SheetEntry)
                        break
                    }
                }
            }
        }

        #region build workbook
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphServicePrincipal $Elapsed"
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
        $Workbook = Open-ExcelPackage -Path $ExcelOutputPath -Create

        foreach ($SheetEntry in $MatchedSheets) {
            # filter logs - empty Operations array means all logs
            if ($SheetEntry.Operations.Count -gt 0) {
                $FilteredLogs = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($LogEntry in $Log) {
                    if ($LogEntry.AuditData.Operation -in $SheetEntry.Operations) {
                        $FilteredLogs.Add($LogEntry)
                    }
                }
            }
            else {
                $FilteredLogs = $Log
            }

            if (($FilteredLogs | Measure-Object).Count -gt 0) {
                $BuildTitle = $SheetEntry.SheetTitle + $Metadata.TitleSuffix
                $SheetParams = @{
                    Logs          = $FilteredLogs
                    ExcelPackage  = $Workbook
                    WorksheetName = $SheetEntry.SheetName
                    Title         = $BuildTitle
                    TableStyle    = $TableStyle
                    Font          = $Font
                    Cached        = $Cached
                }
                # AllOperations needs extra parameters
                if ($SheetEntry.BuildFunction -eq 'Build-AllOperationSheet') {
                    if ($MessageTraceTable) {
                        $SheetParams['MessageTraceTable'] = $MessageTraceTable
                    }
                    if ($OperationsSheetData) {
                        $SheetParams['OperationsSheetData'] = $OperationsSheetData
                    }
                }
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                $BuildFn = $SheetEntry.BuildFunction
                Write-Verbose "${FunctionName}: $BuildFn $Elapsed"
                $Workbook = & $SheetEntry.BuildFunction @SheetParams
            }
        }

        # enrich IP addresses with ip_info data
        if ($IpInfo) {
            foreach ($ws in $Workbook.Workbook.Worksheets) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                $WsName = $ws.Name
                Write-Verbose "${FunctionName}: Add-IpInfoToSheet ($WsName) $Elapsed"
                Add-IpInfoToSheet -Worksheet $ws -ColumnName 'IpAddress'
            }
        }

        #region output
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-IRT "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
#EndRegion '.\Public\UnifiedAuditLog\Show-IRTUnifiedAuditLog.ps1' 229
#Region '.\Public\User\Disable-IRTUser.ps1' -1

function Disable-IRTUser {
    <#
	.SYNOPSIS
	Disable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('DisableUser', 'DisableUsers', 'Lock-GraphUsers',
        'LockUser', 'LockUsers', 'Lock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-UserEnabled @Params
}
#EndRegion '.\Public\User\Disable-IRTUser.ps1' 27
#Region '.\Public\User\Enable-IRTUser.ps1' -1

function Enable-IRTUser {
    <#
	.SYNOPSIS
	Enable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('EnableUser', 'EnableUsers', 'Unlock-GraphUsers',
        'UnlockUser', 'UnlockUsers', 'Unlock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-UserEnabled @Params
}
#EndRegion '.\Public\User\Enable-IRTUser.ps1' 27
#Region '.\Public\User\Find-IRTUser.ps1' -1

function Find-IRTUser {
    <#
    .SYNOPSIS
    Finds graph user by displayname, email address, or user id guid. Creates $UserObjects variable.

    .EXAMPLE
    Find-IRTUser flast
    Find-IRTUser -Search flast,flast,flast
    Find-IRTUser flast@domain.com
    Find-IRTUser -Search bf7573a5844f (partial user id number)

    .NOTES
    Version: 1.2.0
    1.2.0 - Added -AllMatches to collect all matching users and deduplicate results.
    1.1.4 - Fixed bug with $UserObjects not being a collection.
            Moved getting full object to Show-User function.
    1.1.3 - Removed checks for modules and permissions. Checking at module level instead.
    1.1.2 - Added enabled as a displayed field.
    1.1.1 - Bug fix. Script was passing collections rather than user objects.
    1.1.0 - Major rewrite. Renamed to Find-User.
    #>
    [Alias(
        'Find-IRTUsers', 'FindIRTUser', 'FindIRTUsers',
        'Find-User', 'Find-Users', 'FindUser', 'FindUsers'
    )]
    [OutputType([psobject[]])]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Cached,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'UserPrincipalName'
            'OnPremisesSamAccountName'
            'Id'
        )

        # fetch fresh data by default; use cache only when -Cached is specified
        $GraphUsers = Request-GraphUser -Cached:$Cached
    }

    process {

        foreach ( $SearchString in $Search ) {

            # find matching users
            $MatchingUsers = $GraphUsers | Where-Object {
                $_.DisplayName -match $SearchString -or
                $_.UserPrincipalName -match $SearchString -or
                $_.Id -match $SearchString -or
                $_.ProxyAddresses -match $SearchString -or
                $_.OnPremisesSamAccountName -match $SearchString
            }

            if (($MatchingUsers | Measure-Object).Count -eq 1) {

                if ( -not $Script ) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                $User = $MatchingUsers | Select-Object -First 1
                if ($SeenIds.Add($User.Id)) {
                    $ScriptUserObjects.Add($User)
                }
            }
            elseif (($MatchingUsers | Measure-Object).Count -gt 1) {

                if ( -not $Script ) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($User in $MatchingUsers) {
                        if ($SeenIds.Add($User.Id)) {
                            $ScriptUserObjects.Add($User)
                        }
                    }
                } elseif (-not $Script) {
                    Write-IRT 'Multiple users found. Refine search or use -AllMatches.' -Level Error
                }
            }
            else {
                if ( -not $Script ) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return [psobject[]]$ScriptUserObjects
        }

        if ( $ScriptUserObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}UserObjects"
                Value = @($ScriptUserObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}UserObjects"

            if ( $ScriptUserObjects.Count -gt 1 ) {
                $ScriptUserObjects | Format-Table $DisplayProperties
            }
        }
    }
}
#EndRegion '.\Public\User\Find-IRTUser.ps1' 128
#Region '.\Public\User\Reset-IRTUserPassword.ps1' -1

function Reset-IRTUserPassword {
    <#
    .SYNOPSIS
    Resets an Entra ID user's password.

    .DESCRIPTION
    Resets the password for one or more Entra ID users via the Microsoft Graph API. Exactly
    one of the three password mode switches must be specified:

      -RandomCharacters     Generates a random 30-character password and sets it immediately.
                            The new password is printed to the console via [Console]::WriteLine
                            so it is NOT captured in PowerShell transcripts.

      -Custom               Prompts the operator to enter a password interactively via
                            Read-Host. The password is set immediately with no forced
                            change on next sign-in.

      -ForceChangePasswordNextSignIn
                            Does not set a new password. Instead, sets
                            ForceChangePasswordNextSignInWithMfa = $true on the account,
                            which forces the user to choose a new password (with MFA
                            verification) on their next login.

      -ClearForceChangePasswordNextSignIn
                            Clears the force-change flag. Sets both
                            ForceChangePasswordNextSignIn and
                            ForceChangePasswordNextSignInWithMfa to $false without
                            changing the current password.

    If no -UserObject is supplied, the function falls back to the global session objects
    stored in $Global:IRT_UserObjects (populated by Get-GlobalUserObject). An error is thrown
    if neither source yields a user.

    After the reset, updated account properties are retrieved and displayed as a table.
    If the user is synced from on-premises Active Directory, a warning is shown reminding
    the operator to also reset the password in the local AD.

    Supports -WhatIf and -Confirm via SupportsShouldProcess.

    .PARAMETER UserObject
    One or more Entra ID user objects whose passwords will be reset. Falls back to
    $Global:IRT_UserObjects if omitted.

    .PARAMETER RandomCharacters
    Generates a random password of the specified length (default: 30 characters) and
    applies it to the account. The password is written directly to the console (bypassing
    transcript logging) so it can be recorded securely by the operator.

    .PARAMETER Length
    The length of the randomly generated password. Only valid with -RandomCharacters.
    Must be at least 4 characters. Defaults to 30.

    .PARAMETER Custom
    Prompts the operator to enter a custom password via Read-Host. The password is applied
    immediately with ForceChangePasswordNextSignIn set to $false.

    .PARAMETER ForceChangePasswordNextSignIn
    Sets ForceChangePasswordNextSignInWithMfa = $true on the account without changing the
    current password. The user will be required to set a new password (verified with MFA)
    on their next sign-in.

    .PARAMETER ClearForceChangePasswordNextSignIn
    Clears the forced-change-on-next-sign-in flag. Sets both ForceChangePasswordNextSignIn
    and ForceChangePasswordNextSignInWithMfa to $false without changing the current password.
    Use this to undo a previous -ForceChangePasswordNextSignIn call.

    .EXAMPLE
    Reset-IRTUserPassword -RandomCharacters
    Resets the password for the user stored in the global session using a random password.
    The new password is printed to the console.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -RandomCharacters
    Resets the password for a specific user object using a random password.

    .EXAMPLE
    Reset-IRTUserPassword -Custom
    Prompts the operator to enter a custom password, then applies it to the global session user.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -ForceChangePasswordNextSignIn
    Forces the user to set a new password (with MFA) on their next sign-in, without
    changing the current password.

    .EXAMPLE
    Reset-IRTUserPassword -RandomCharacters -Length 48
    Resets the password using a random 48-character password.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -RandomCharacters -WhatIf
    Shows what would happen without actually resetting the password.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -ClearForceChangePasswordNextSignIn
    Clears the forced-change flag on the user's account.

    .OUTPUTS
    None. Updated user properties are displayed as a formatted table in the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Added ClearForceChangePasswordNextSignIn parameter set to undo the force-change flag.
    1.1.0 - Added ForceChangePasswordNextSignIn parameter set. Removed default parameter set;
            operator must now explicitly choose a password mode. Renamed to Reset-IRTUserPassword.
    1.0.1 - Updated to output password in safe way. Fixed bug preventing password reset.
            Updated variable names.
    #>
    [Alias('ResetPassword', 'ResetPasswords')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [Alias('Random')]
        [switch] $RandomCharacters,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [ValidateRange(4, [int]::MaxValue)]
        [int] $Length = 30,

        # [Parameter(ParameterSetName = 'PassPhrase')] # FIXME this would be cool, right?
        # [Alias('Phrase')]
        # [switch] $PassPhrase,

        [Parameter(ParameterSetName = 'Custom')]
        [switch] $Custom,

        [Parameter(ParameterSetName = 'ForceChangePasswordNextSignIn')]
        [switch] $ForceChangePasswordNextSignIn,

        [Parameter(ParameterSetName = 'ClearForceChangePasswordNextSignIn')]
        [Alias('UndoForceChangePasswordNextSignIn')]
        [switch] $ClearForceChangePasswordNextSignIn
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $LoopObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $LoopObjects -or $LoopObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $LoopObjects = $UserObject
        }

        # variables
        $GetProperties = @(
            'AccountEnabled'
            'DisplayName'
            'Id'
            'LastPasswordChangeDateTime'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'LastPasswordChangeDateTime'
            'AccountEnabled'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
        )
    }

    process {

        foreach ($LoopObject in $LoopObjects) {

            switch ($true) {
                $Custom {
                    $Password = Read-Host -Prompt "Enter new password"
                    $PasswordProfile = @{
                        Password = $Password
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                    break
                }
                $ForceChangePasswordNextSignIn {
                    $PasswordProfile = @{
                        ForceChangePasswordNextSignInWithMfa = $true
                    }
                    break
                }
                $ClearForceChangePasswordNextSignIn {
                    $PasswordProfile = @{
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                    break
                }
                $RandomCharacters {
                    # RandomCharacters
                    $UserEmail = $LoopObject.UserPrincipalName
                    $Password = Get-RandomPassword $Length
                    Write-IRT "${UserEmail} new password:"
                    # Console WriteLine prevents password from being recorded in transcripts
                    [Console]::WriteLine($Password)
                    $PasswordProfile = @{
                        Password = $Password
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                }
            }

            # create password profile and reset password
            if ($PSCmdlet.ShouldProcess($LoopObject.UserPrincipalName, 'Reset password')) {
                Update-MgUser -UserId $LoopObject.Id -PasswordProfile $PasswordProfile
            }

            # get new user object
            Write-IRT "Getting updated user information."
            $FullUserObject = Get-MgUser -UserId $LoopObject.Id -Property $GetProperties
            try {
                $FullUserObject.LastPasswordChangeDateTime =
                $FullUserObject.LastPasswordChangeDateTime.ToLocalTime()
            }
            catch {}

            # display new object
            $FullUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ( $FullUserObject.OnPremisesSyncEnabled ) {
                $Msg = 'User is synced from on-premises. Reset password in local AD too!'
                Write-IRT $Msg -Level Error
            }
        }
    }
}
#EndRegion '.\Public\User\Reset-IRTUserPassword.ps1' 242
#Region '.\Public\User\Revoke-IRTUserSession.ps1' -1

function Revoke-IRTUserSession {
    <#
	.SYNOPSI
	Revoke sessions for selected user. (NOTE: There is currently no way to revoke MFA
	sessions through graph APIs. It must be done in the Entra/Azure web portal.)

	.NOTES
	Version: 1.0.0
	#>
    [Alias('RevokeSessions', 'Revoke-IRTUserSessions')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserPrincipalName = $ScriptUserObject.UserPrincipalName

            Write-IRT "Revoking user sessions for: ${UserPrincipalName}"
            $Result = ( Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id ).Value

            if ( $Result -eq $true ) {
                Write-IRT "Sessions revoked."
            }
            else {
                Write-IRT "Revoking sessions failed." -Level Error
            }
        }
    }
}
#EndRegion '.\Public\User\Revoke-IRTUserSession.ps1' 54
#Region '.\Public\User\Set-IRTUserUsageLocation.ps1' -1

function Set-IRTUserUsageLocation {
    <#
	.SYNOPSIS
	Sets user's usage location.

	.NOTES
	Version: 1.0.2
    1.0.2 - .Contains() method is case sensitive. Adjusted so .ToUpper() happens before
            running .Contains() so lower case input of valid country codes will be accepted.
	#>
    [Alias('SetLocation', 'SetUsage')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject,

        [string] $CountryCode
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # variables
        $CountryCodeHelpUrl = "https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes"
        $ValidCountryCodes = [system.collections.generic.hashset[string]]::new( [string[]](
                'AD', 'AE', 'AF', 'AG', 'AI', 'AL', 'AM', 'AO', 'AQ', 'AR', 'AS', 'AT', 'AU', 'AW',
                'AX', 'AZ', 'BA', 'BB', 'BD', 'BE', 'BF', 'BG', 'BH', 'BI', 'BJ', 'BL', 'BM', 'BN',
                'BO', 'BQ', 'BR', 'BS', 'BT', 'BV', 'BW', 'BY', 'BZ', 'CA', 'CC', 'CD', 'CF', 'CG',
                'CH', 'CI', 'CK', 'CL', 'CM', 'CN', 'CO', 'CR', 'CU', 'CV', 'CW', 'CX', 'CY', 'CZ',
                'DE', 'DJ', 'DK', 'DM', 'DO', 'DZ', 'EC', 'EE', 'EG', 'EH', 'ER', 'ES', 'ET', 'FI',
                'FJ', 'FK', 'FM', 'FO', 'FR', 'GA', 'GB', 'GD', 'GE', 'GF', 'GG', 'GH', 'GI', 'GL',
                'GM', 'GN', 'GP', 'GQ', 'GR', 'GS', 'GT', 'GU', 'GW', 'GY', 'HK', 'HM', 'HN', 'HR',
                'HT', 'HU', 'ID', 'IE', 'IL', 'IM', 'IN', 'IO', 'IQ', 'IR', 'IS', 'IT', 'JE', 'JM',
                'JO', 'JP', 'KE', 'KG', 'KH', 'KI', 'KM', 'KN', 'KP', 'KR', 'KW', 'KY', 'KZ', 'LA',
                'LB', 'LC', 'LI', 'LK', 'LR', 'LS', 'LT', 'LU', 'LV', 'LY', 'MA', 'MC', 'MD', 'ME',
                'MF', 'MG', 'MH', 'MK', 'ML', 'MM', 'MN', 'MO', 'MP', 'MQ', 'MR', 'MS', 'MT', 'MU',
                'MV', 'MW', 'MX', 'MY', 'MZ', 'NA', 'NC', 'NE', 'NF', 'NG', 'NI', 'NL', 'NO', 'NP',
                'NR', 'NU', 'NZ', 'OM', 'PA', 'PE', 'PF', 'PG', 'PH', 'PK', 'PL', 'PM', 'PN', 'PR',
                'PS', 'PT', 'PW', 'PY', 'QA', 'RE', 'RO', 'RS', 'RU', 'RW', 'SA', 'SB', 'SC', 'SD',
                'SE', 'SG', 'SH', 'SI', 'SJ', 'SK', 'SL', 'SM', 'SN', 'SO', 'SR', 'SS', 'ST', 'SV',
                'SX', 'SY', 'SZ', 'TC', 'TD', 'TF', 'TG', 'TH', 'TJ', 'TK', 'TL', 'TM', 'TN', 'TO',
                'TR', 'TT', 'TV', 'TW', 'TZ', 'UA', 'UG', 'UM', 'US', 'UY', 'UZ', 'VA', 'VC', 'VE',
                'VG', 'VI', 'VN', 'VU', 'WF', 'WS', 'YE', 'YT', 'ZA', 'ZM', 'ZW') )
        $UserGetProperties = @(
            'UsageLocation'
            'DisplayName'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $UserDisplayProperties = @(
            'UsageLocation'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
            'Id'
        )

        # show country codes if not provided
        if (-not $CountryCode) {
            # open browser to wikipedia
            Start-Process $CountryCodeHelpUrl
            Write-IRT "Opening browser..." -Level Warn
            $CountryCode = Read-Host "Enter ISO-3166 A-2 country code"
            if ($CountryCode) {
                # set code to capital letters
                $CountryCode = $CountryCode.ToUpper()
            }
            while ( -not $ValidCountryCodes.Contains( $CountryCode ) ) {
                Write-IRT "Not a valid country code. Try again." -Level Error
                $CountryCode = Read-Host "Enter ISO-3166 A-2 country code"
            }
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # set code to capital letters
            $CountryCode = $CountryCode.ToUpper()

            # set new location
            $Upn = $ScriptUserObject.UserPrincipalName
            if ($PSCmdlet.ShouldProcess($Upn, "Set usage location to $CountryCode")) {
                Write-IRT "Setting new usage location."
                Update-MgUser -UserId $ScriptUserObject.Id -Usagelocation $CountryCode
            }

            # get new user object
            Write-IRT "Getting new user properties."
            $FullUserObject = Get-MgUser -UserId $ScriptUserObject.Id -Property $UserGetProperties

            # display new object
            $FullUserObject | Format-Table $UserDisplayProperties
        }
    }
}
#EndRegion '.\Public\User\Set-IRTUserUsageLocation.ps1' 115
#Region '.\Public\User\Show-IRTUser.ps1' -1

function Show-IRTUser {
    <#
    .SYNOPSIS
    Displays user properties.

    .DESCRIPTION
    Retrieves the full Graph user object (all available properties) and displays it as a
    formatted tree in the console. Also updates $Global:IRT_UserObjects with the enriched
    object so downstream playbook steps receive complete data.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more Microsoft Graph user objects to display. Falls back to global session
    objects if omitted.

    .EXAMPLE
    Show-IRTUser
    Displays info for the user stored in the global session.

    .EXAMPLE
    Show-IRTUser -UserObject $User
    Displays info for a specific user object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Switched to Format-Tree, Show-GraphUserTree
    #>
    [Alias(
        'Show-IRTUsers',
        'Show-User', 'Show-Users',
        'ShowIRTUser', 'ShowIRTUsers',
        'ShowUser', 'ShowUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global user object
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }
    }

    process {

        # overwrite global $UserObject so we can add the full user objects with all properties
        $Global:IRT_UserObjects = [System.Collections.Generic.List[psobject]]::new()

        foreach ($ScriptUserObject in $ScriptUserObjects) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # get user object with all possible properties
            Write-IRT "Getting full user object."
            $ScriptUserObject = Get-FullUserObject -UserObject $ScriptUserObject

            # copy full user object to global variables
            $Global:IRT_UserObjects.Add($ScriptUserObject)

            Write-IRT "Showing user properties for: ${UserEmail}"
            $ScriptUserObject | Show-GraphUserTree | Out-Host

            Write-IRT "Showing groups for: ${UserEmail}"
            $UserGroups = Get-MgUserMemberOfAsGroup -UserId $ScriptUserObject.Id
            if ( $UserGroups ) {
                $UserGroups |
                    Sort-Object DisplayName |
                    Format-Table DisplayName, GroupTypes, Mail, Description |
                    Out-Host
            }
            else {
                Write-Host "None" | Out-Host
            }
        }
    }
}
#EndRegion '.\Public\User\Show-IRTUser.ps1' 97
#Region '.\Public\User\Show-IRTUserMfa.ps1' -1

function Show-IRTUserMfa {
    <#
    .SYNOPSIS
    Shows a graph user's MFA methods.

    .DESCRIPTION
    Retrieves all registered authentication methods for one or more Entra ID users and
    displays them in a formatted table. Each method row includes type, summary details,
    and a pre-built deletion command for quick remediation.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more Entra ID user objects to query. Falls back to global session objects if
    omitted. Accepts pipeline input.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .EXAMPLE
    Show-IRTUserMfa
    Displays MFA methods for the user in the global session.

    .EXAMPLE
    Show-IRTUserMfa -UserObject $User
    Displays MFA methods for a specific user.

    .OUTPUTS
    None. Results are displayed in the console and optionally exported to Excel.

    .NOTES
    Credit to:
    https://thesysadminchannel.com/get-mfa-methods-using-msgraph-api-and-powershell-sdk/
    #>
    [Alias('ShowMFA', 'UserMFA')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0,
            ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $OutputTable = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Properties = [System.Collections.Generic.Hashset[string]]::new()
        $PropertySortOrder = @(
            'Raw'
            'MethodType'
            'Summary'
            'Id'
            'DeleteCommand'
        )
        $EventDateFormat = 'MM/dd/yy hh:mm:sstt'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'MFAMethods'


        # if user objects not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # get client domain name for file output
        $DomainName = Get-DefaultDomain

        # get date/time string for filename
        $DateString = Get-Date -Format $FileNameDateFormat
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserId = $ScriptUserObject.Id

            # get username
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # build file name
            $XmlOutputPath = "MFAMethods_${DomainName}_${UserName}_${DateString}.xml"
            $ExcelOutputPath = "MFAMethods_${DomainName}_${UserName}_${DateString}.xlsx"

            # build worksheet title
            $DateString = ( Get-Date ).ToString( "M/d/yy h:mmtt" ).ToLower()
            $WorksheetTitle = "MFA methods for ${UserEmail} on ${DateString}."

            Write-IRT "Getting MFA methods for: ${UserEmail}"
            $Methods = Get-MgUserAuthenticationMethod -UserId $ScriptUserObject.Id -ErrorAction Stop

            foreach ( $Method in $Methods ) {

                # variables
                $MethodId = $Method.Id
                $CustomObject = [PSCustomObject]@{
                    Id = $Method.Id
                }

                # Raw
                $Raw = $Method | ConvertTo-Json -Depth 10
                $AddParams = @{
                    MemberType = 'NoteProperty'
                    Name       = 'Raw'
                    Value      = $Raw
                }
                $CustomObject | Add-Member @AddParams

                $SummaryParts = [System.Collections.Generic.List[string]]::new()

                foreach ( $Key in $Method.AdditionalProperties.Keys ) {

                    # set user friendly type name
                    if ( $Key -eq "@odata.type" ) {

                        # start params tables
                        $NameParams = @{
                            MemberType = 'NoteProperty'
                            Name       = 'MethodType'
                        }
                        $DeleteParams = @{
                            MemberType = 'NoteProperty'
                            Name       = 'DeleteCommand'
                        }

                        # add human friendly method name to table, then add table to custom object
                        switch -Wildcard ( $Method.AdditionalProperties["@odata.type"] ) {
                            # email
                            '#microsoft.graph.emailAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Email'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationEmailMethod' +
                                " -UserId ${UserId} -EmailAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # fido
                            '#microsoft.graph.fido2AuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Fido2'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationFido2Method' +
                                " -UserId ${UserId} -Fido2AuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # microsoft authenticator
                            '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'MicrosoftAuthenticator'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod' +
                                " -UserId ${UserId}" +
                                ' -MicrosoftAuthenticatorAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # password
                            '#microsoft.graph.passwordAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Password'
                                $CustomObject | Add-Member @NameParams
                            }
                            # passwordless
                            '*passwordlessMicrosoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Passwordless'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgBetaUserAuthentication' +
                                'PasswordlessMicrosoftAuthenticatorMethod' +
                                " -UserId ${UserId}" +
                                ' -PasswordlessMicrosoftAuthenticatorAuthentication' +
                                "MethodId  ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # phone
                            '#microsoft.graph.phoneAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Phone'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationPhoneMethod' +
                                " -UserId ${UserId} -PhoneAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # software oath
                            '#microsoft.graph.softwareOathAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'SoftwareOath'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationSoftwareOathMethod' +
                                " -UserId ${UserId}" +
                                ' -SoftwareOathAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # temporary access pass
                            '#microsoft.graph.temporaryAccessPassAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'TemporaryAccessPass'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationTemporaryAccessPassMethod' +
                                " -UserId ${UserId}" +
                                ' -TemporaryAccessPassAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # windows hello
                            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'WindowsHelloForBusiness'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationWindowsHelloForBusinessMethod' +
                                " -UserId ${UserId}" +
                                ' -WindowsHelloForBusinessAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            default {

                                # add human friendly method name
                                $NameParams['Value'] = $Method.AdditionalProperties["@odata.type"]
                                $CustomObject | Add-Member @NameParams
                            }
                        }
                    }

                    # convert created date string to datetime object and add to summary
                    elseif ( $Key -eq 'createdDateTime' ) {

                        # cast string to datetime object
                        $DateTime = [datetime]( $Method.AdditionalProperties[$Key] )

                        ### build date string
                        $BuildString = $DateTime.ToLocalTIme().ToString(
                            $EventDateFormat).ToLower()
                        # create acronym from timezone full name
                        if ( $DateTime.ToLocalTIme().IsDaylightSavingTime()) {
                            $TimeZoneName = $TimeZoneInfo.DaylightName
                        }
                        else {
                            $TimeZoneName = $TimeZoneInfo.StandardName
                        }
                        $TimeZoneAcronym = -join ($TimeZoneName -split ' ' |
                                ForEach-Object { $_[0] })
                        # add time zone acronym to string
                        $EventDateString = $BuildString + " " + $TimeZoneAcronym
                        # if first character of date is 0, replace with space
                        if ( $EventDateString[0] -eq '0' ) {
                            $EventDateString = " " + $EventDateString.Substring(1)
                        }
                        # if first character of time is 0, replace with space
                        if ( $EventDateString[9] -eq '0' ) {
                            $EventDateString = $EventDateString.Substring(0, 9) +
                            ' ' + $EventDateString.Substring(10)
                        }

                        # add to summary list
                        $SummaryParts.Add( "CreatedDateTime: ${EventDateString}" )
                    }

                    # for other properties, add to summary list
                    else {

                        # capitalize propertyname
                        $CapPropertyName = $Key.Substring(0, 1).ToUpper() + $Key.Substring(1)

                        # format phone numbers for Excel compatibility
                        $Value = $Method.AdditionalProperties[$Key]
                        if ( $CapPropertyName -eq 'PhoneNumber' ) {
                            $Value = Format-PhoneNumber $Value
                        }

                        # add to summary list
                        if ( $null -ne $Value -and $Value -ne '' ) {
                            $SummaryParts.Add( "${CapPropertyName}: ${Value}" )
                        }
                    }
                }

                # add summary column
                if ( $SummaryParts.Count -gt 0 ) {
                    $SummaryString = $SummaryParts -join "`n"
                    $NpParams = @{
                        MemberType = 'NoteProperty'
                        Name       = 'Summary'
                        Value      = $SummaryString
                    }
                    $CustomObject | Add-Member @NpParams
                }

                # add loop object to table
                $OutputTable.Add( $CustomObject )
            }

            # show raw data if verbose
            if ($VerbosePreference -eq 'Continue') {
                Write-Verbose "Raw data:"
                $Methods.AdditionalProperties
            }

            # collect all property names
            foreach ( $Object in $OutputTable ) {
                $Properties.UnionWith( [string[]]@($Object.PsObject.Properties.Name) )
            }

            # sort properties in custom order
            $SortedProperties = $Properties | Sort-Object -Property @{
                Expression = {
                    $Index = $PropertySortOrder.IndexOf( $_ )
                    # if not in the list, make last
                    if ( $Index -eq -1 ) {
                        [int]::MaxValue
                    }
                    else {
                        $Index
                    }
                }
                Ascending  = $true
            }

            if ($Xml) {
                # export raw data as xml
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $Methods | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            #region EXCEL
            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorkSheetName
                Title         = $WorksheetTitle
                TableStyle    = $TableStyle
                AutoSize      = $true
                FreezeTopRow  = $true
                Passthru      = $true
            }
            try {
                $Workbook = $OutputTable |
                    Select-Object $SortedProperties | Export-Excel @ExcelParams
            }
            catch {
                Write-IRT "Unable to open new Excel document." -Level Error
                if ( Get-YesNo "Try closing open files. Respond y when done." ) {
                    try {
                        $Workbook = $OutputTable | Export-Excel @ExcelParams
                    }
                    catch {
                        Write-IRT "Unable to open new Excel document. Exiting." -Level Error
                    }
                }
            }
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

            # get table ranges
            $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $WorkSheet.Dimension.Start.Row
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 )
            #     .Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            $SummaryColumn = ($Worksheet.Tables[0].Columns |
                    Where-Object { $_.Name -eq 'Summary' }).Id |
                    Convert-DecimalToExcelColumn

            #region COLUMN WIDTH

            # column widths
            $ColumnWidths = @{
                'Raw'           = 8
                'MethodType'    = 20
                'Summary'       = 70
                'Id'            = 42
                'DeleteCommand' = 200
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # enable text wrapping on Summary column
            $WrapParams = @{
                Worksheet = $Worksheet
                Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @WrapParams

            # set font and size
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            Set-ExcelRange @SetParams

            # add left side border
            $BorderParams = @{
                Worksheet = $Worksheet
                Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            #region OUTPUT

            # save and close
            Write-IRT "Exporting to: ${ExcelOutputPath}"
            if ($Open) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
#EndRegion '.\Public\User\Show-IRTUserMfa.ps1' 484
#Region '.\Public\Utility\Compress-IRTInvestigationFolder.ps1' -1

function Compress-IRTInvestigationFolder {
    <#
	.SYNOPSIS
	Compresses all folders ending with "_investigation" into folder called investigations.

	.NOTES
	Version: 1.0.0
	#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Days', Justification = 'Used inside scriptblock'
    )]
    [CmdletBinding()]
    param (
        [int] $Days = 3
    )

    begin {
        # get the current directory path
        $CurrentDirectory = Get-Location

        # define the destination path as a subfolder named "incidents" under the current directory
        $DestinationPath = Join-Path -Path $CurrentDirectory.Path -ChildPath '\investigations\'

        if ( -not ( Test-Path -Path $DestinationPath ) ) {
            $null = New-Item -ItemType Directory -Path $DestinationPath
        }
    }

    process {

        # find all subdirectories in the current directory whose names end with "investigation"
        $IncidentParams = @{
            Path      = $CurrentDirectory.Path
            Directory = $true
        }
        $Investigations = Get-ChildItem @IncidentParams | Where-Object {
            $_.Name -match 'investigation$'
        }

        foreach ( $Investigation in $Investigations ) {

            # retrieve all files under this folder (including subfolders)
            $FilesParams = @{
                Path    = $Investigation.FullName
                File    = $true
                Recurse = $true
            }
            $Files = Get-ChildItem @FilesParams

            # find any file modified within the last 48 hours
            $RecentFilesParams = @{
                FilterScript = {
                    $_.LastWriteTime -ge (Get-Date).AddDays($Days)
                }
            }
            $RecentFiles = $Files | Where-Object @RecentFilesParams

            # only compress if there are no recent files
            if ( -not $RecentFiles ) {

                # build the .zip file path
                $ArchiveName = $Investigation.Name + '.zip'
                $ArchivePath = Join-Path -Path $DestinationPath -ChildPath $ArchiveName

                # compress the folder into the destination path
                $CompressParams = @{
                    Path             = $Investigation.FullName
                    DestinationPath  = $ArchivePath
                    CompressionLevel = 'Optimal'
                    Force            = $true
                }
                Compress-Archive @CompressParams

                # delete folder
                if ( Test-Path $ArchivePath ) {
                    Remove-Item -Recurse -Force -LiteralPath $Investigation.FullName
                }
            }
        }
    }
}
#EndRegion '.\Public\Utility\Compress-IRTInvestigationFolder.ps1' 82
#Region '.\Public\Utility\Find-IRTDirectoryObject.ps1' -1

function Find-IRTDirectoryObject {
    [Alias('FindObject', 'FindObjects')]
    param(
        [Parameter( Position = 0 )]
        [string] $Content
    )

    begin {
        $GuidPattern = "\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b"

        # get content from clipboard
        if (-not $Content) {
            Write-IRT "No content provided. Pulling from clipboard."
            $Content = Get-Clipboard
            if ( @( $Content ).Count -eq 0 ) {
                throw "No content provided, or found in clipboard. Exiting."
            }
            $DisplayLines = $Content -split "`r`n" | Select-Object -First 3
            $TruncatedLines = $DisplayLines | ForEach-Object {
                if ( $_.Length -gt 80 ) {
                    $_.Substring(0, 77) + "..."
                }
                else {
                    $_
                }
            }
            Write-IRT $TruncatedLines
        }
    }

    process {

        $Guids = $Content |
            Select-String -Pattern $GuidPattern -AllMatches |
            ForEach-Object { $_.Matches.Value }

        # remove duplicates
        $Guids = $Guids | Sort-Object -Unique

        Write-IRT "Found GUIDS:"
        $Guids

        foreach ( $Guid in $Guids ) {

            # variables
            $DirectoryObject = $null
            $ObjectType = $null

            Write-IRT "Running Get-MgDirectoryObject for ${Guid}"

            try {

                $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Guid -ErrorAction Stop

                $ObjectType = $DirectoryObject.AdditionalProperties.'@odata.type' -replace '#', ''

                Write-IRT "ObjectType: ${ObjectType}"
            }
            catch {
                $Pattern = 'does not exist or one of its queried' +
                ' reference-property objects are not present'
                if ( $_ -match $Pattern ) {
                    Write-IRT "Unable to find object."
                }
                else {
                    $_
                }
            }

            switch ( $ObjectType ) {
                'microsoft.graph.user' {
                    $Object = if ( $Global:IRT_UsersById -and
                        $Global:IRT_UsersById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_UsersById[$Guid]
                    } else {
                        Get-MgUser -UserId $Guid
                    }
                    $Object | Format-Table
                }
                'microsoft.graph.group' {
                    $Object = if ( $Global:IRT_GroupsById -and
                        $Global:IRT_GroupsById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_GroupsById[$Guid]
                    } else {
                        Get-MgGroup -GroupId $Guid
                    }
                    $Object | Format-Table
                }
                'microsoft.graph.servicePrincipal' {
                    $Object = if ( $Global:IRT_ServicePrincipalsById -and
                        $Global:IRT_ServicePrincipalsById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_ServicePrincipalsById[$Guid]
                    } else {
                        Get-MgServicePrincipal -ServicePrincipalId $Guid
                    }
                    $Object | Format-Table
                }
            }
        }
    }
}
#EndRegion '.\Public\Utility\Find-IRTDirectoryObject.ps1' 105
#Region '.\Public\Utility\Get-IRTLicenseReport.ps1' -1

function Get-IRTLicenseReport {
    <#
    .SYNOPSIS
    Shows table of tenant licenses.

    .DESCRIPTION
    Retrieves all subscribed SKUs from Microsoft Graph, resolves each SKU's friendly
    product name via Get-LicenseFullName, and displays a formatted table showing
    capability status, applies-to scope, license name, total enabled units, consumed
    units, and available units. Use -Objects to return raw enriched objects instead.

    .PARAMETER Objects
    Return raw license objects (with the LicenseFullName property added) instead of
    displaying the formatted table. Useful for piping to further processing.

    .PARAMETER Runspace
    Switch to Format-Table -AutoSize output instead of Write-PSObject color formatting.
    Set automatically when called from a runspace (e.g., the incident response playbook).

    .EXAMPLE
    Get-IRTLicenseReport
    Displays a color-formatted license table in the console.

    .EXAMPLE
    $Licenses = Get-IRTLicenseReport -Objects
    Returns raw license objects for further processing.

    .OUTPUTS
    None (console table) by default.
    Microsoft.Graph.PowerShell.Models.MicrosoftGraphSubscribedSku[] when -Objects is used.

    .NOTES
    Version: 1.1.3
    1.1.3 - Added optional output formatting for runspaces.
    #>
    [Alias('LicenseReport')]
    [CmdletBinding()]
    param (
        [switch] $Objects,
        [switch] $Runspace
    )

    begin {
        $Context = Get-MgContext
        if ( -not $Context ) {
            throw "Not connected to Graph. Exiting"
        }

        # get license objects
        $Licenses = Get-MgSubscribedSku |
            # Where-Object { $_.CapabilityStatus -eq 'Enabled' } |
            Get-LicenseFullName
    }

    process {

        Write-IRT "Retrieving tenant licenses..."

        if ( $Objects ) {
            return $Licenses
        }
        # if user doesn't specify output, display table in terminal
        else {

            if ( -not $Licenses ) {
                Write-IRT "No Licenses found. Exiting." -Level Error
                return
            }

            # generate report for viewing in terminal
            $OutputTable = $Licenses | ForEach-Object {

                $LicenseName = if ( $_.LicenseFullName ) {
                    $_.LicenseFullName
                }
                else {
                    $_.SkuPartNumber
                }

                [pscustomobject]@{
                    CapabilityStatus = $_.CapabilityStatus
                    AppliesTo        = $_.AppliesTo
                    LicenseName      = $LicenseName
                    Enabled          = $_.PrepaidUnits.Enabled
                    Consumed         = $_.ConsumedUnits
                    Available        = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
                }
            }

            # sort
            $SortOrder = @(
                'CapabilityStatus'
                'AppliesTo'
                'LicenseName'
            )
            $OutputTable = $OutputTable | Sort-Object $SortOrder

            if ( $RunSpace ) {
                # output formatting if being run in a runspace
                return $OutputTable | Format-Table -AutoSize
            }
            else {

                # output formatting if being run directly in terminal
                $WriteParams = @{
                    HeadersForeColor = 'Green'
                    MatchMethod      = 'Match', 'Match'
                    Column           = 'LicenseName', 'LicenseName'
                    Value            = 'E3', 'E5'
                    ValueForeColor   = 'Magenta', 'Magenta'
                }
                Write-PSObject $OutputTable @WriteParams
            }
        }
    }
}
#EndRegion '.\Public\Utility\Get-IRTLicenseReport.ps1' 117
#Region '.\Public\Utility\Import-IRT.ps1' -1

function Import-IRT {
    <#
    .SYNOPSIS
        Preloads the M365IncidentResponseTools module into the current session.

    .DESCRIPTION
        A lightweight stub whose sole purpose is to trigger PowerShell's automatic
        module loading. Calling this function forces the full module to be imported --
        dot-sourcing all domain scripts and initializing shared state -- so that
        subsequent commands respond instantly instead of incurring the first-call
        import penalty.

    .EXAMPLE
        Import-IRT

        Loads M365IncidentResponseTools into the current session. Run this once at
        the start of a session to warm up the module before using any IRT commands.

    .OUTPUTS
        None

    .NOTES
        The function body is intentionally empty. The import side-effect is produced
        entirely by PowerShell's automatic module loading when any exported function
        from the module is invoked.
    #>
    [Alias('ImportIRT', 'LoadIRT', 'IRT')]
    [CmdletBinding()]
    [OutputType([void])]
    param()
}
#EndRegion '.\Public\Utility\Import-IRT.ps1' 32
#Region '.\Public\Utility\Import-IRTConfig.ps1' -1

function Import-IRTConfig {
    <#
    .SYNOPSIS
    Loads the current IRT configuration.

    .DESCRIPTION
    Reads the user configuration from $env:APPDATA\<ModuleName>\config.json.
    If the file does not exist, copies the template from the module root and loads it.
    The parsed config is cached in $Global:IRT_Config.

    .PARAMETER Force
    Re-read the config file even if $Global:IRT_Config is already populated.
    #>
    [Alias('ImportConfig', 'IRTConfig')]
    [CmdletBinding()]
    param(
        [switch] $Force
    )

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir = Join-Path -Path $env:APPDATA -ChildPath $ModuleName
    $ConfigPath = Join-Path -Path $ConfigDir -ChildPath 'Config.json'
    $TemplatePath = Join-Path -Path $ModuleRoot -ChildPath 'Data\ConfigTemplate.json'

    if (-not (Test-Path $ConfigPath)) {
        if (-not (Test-Path $ConfigDir)) {
            $null = New-Item -ItemType Directory -Path $ConfigDir -Force
        }
        Copy-Item -Path $TemplatePath -Destination $ConfigPath
        Write-IRT "Created default config at: $ConfigPath"
    }

    if ($Force -or -not $Global:IRT_Config) {
        $Global:IRT_Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }

    # Backfill any new keys from the template that the user's config doesn't have yet
    $Template = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json
    $Updated = $false
    foreach ($Property in $Template.PSObject.Properties) {
        if (-not ($Global:IRT_Config.PSObject.Properties.Name -contains $Property.Name)) {
            $AddParams = @{
                NotePropertyName  = $Property.Name
                NotePropertyValue = $Property.Value
            }
            $Global:IRT_Config | Add-Member @AddParams
            $Updated = $true
        }
    }
    if ($Updated) {
        $Global:IRT_Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding utf8
    }

    # Resolve null path values to their defaults (in-memory only; defaults are not written back)
    if (-not $Global:IRT_Config.TenantsSheetPath) {
        $TenantDir = Join-Path -Path $env:APPDATA -ChildPath 'M365IncidentResponseTools'
        $TenantPath = Join-Path -Path $TenantDir -ChildPath 'tenants.xlsx'
        $Global:IRT_Config.TenantsSheetPath = $TenantPath
    }
}
#EndRegion '.\Public\Utility\Import-IRTConfig.ps1' 62
#Region '.\Public\Utility\New-IRTInvestigationFolder.ps1' -1

function New-IRTInvestigationFolder {
    <#
    .SYNOPSIS
    Makes a new directory based on client and user info.

    .DESCRIPTION
    Creates a timestamped investigation output folder in the current working directory.
    The folder name is built from the tenant's default domain, an optional ticket number,
    and the display names of the users under investigation.

    If the Graph context is not available the function prompts for a client name
    interactively. Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more user objects whose names are included in the folder name. Falls back to
    global session objects if omitted.

    .PARAMETER Ticket
    Optional ticket or case number to include in the folder name.

    .EXAMPLE
    New-IRTInvestigationFolder
    Creates a folder like: investigation_contoso_jsmith_26-05-03_14-30

    .EXAMPLE
    New-IRTInvestigationFolder -Ticket 'INC-1234' -UserObject $User
    Creates a folder that includes the ticket number and user name.

    .OUTPUTS
    System.IO.DirectoryInfo

    .NOTES
    Version: 1.0.2
    #>
    [Alias('NewDir', 'NewFolder')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $Ticket
    )

    begin {

        # script variables
        $CurrentPath = Get-Location
        $FileNameStrings = [System.Collections.Generic.List[string]]::new()

        # get client domain
        try {
            $DomainName = Get-DefaultDomain
        }
        catch {}

        if ( -not $DomainName ) {
            $DomainName = Read-Host "Enter client name"
        }

        # get datetime string for filename
        $DateString = Get-Date -Format "yy-MM-dd_HH-mm"

        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

        }
        else {
            $ScriptUserObjects = $UserObject
        }
    }

    process {

        ### build string array
        # domain name
        if ( $DomainName ) {
            $FileNameStrings.Add( $DomainName )
        }

        # user name
        if ( @( $ScriptUserObjects ).Count -eq 1 ) {

            $UserEmail = $ScriptUserObjects.UserPrincipalName
            $UserName = $UserEmail -split '@' | Select-Object -First 1
            $FileNameStrings.Add( $UserName )
        }
        elseif (  @( $ScriptUserObjects ).Count -gt 1 ) {

            $FileNameStrings.Add( 'MultipleUsers' )
        }
        else {
            $UserName = Read-Host "Enter username:"
            $FileNameStrings.Add( $UserName )
        }

        # ticket number
        if (-not [string]::IsNullOrWhiteSpace($Ticket)) {
            $FileNameStrings.Add($Ticket)
        }

        # date
        $FileNameStrings.Add( $DateString )

        # investigation
        $FileNameStrings.Add( 'Investigation' )

        # build folder name
        $FolderName = $FileNameStrings -join '_'

        # create folder
        $FolderPath = Join-Path -Path $CurrentPath -ChildPath $FolderName
        if ($PSCmdlet.ShouldProcess($FolderPath, 'Create directory')) {
            $null = New-Item -ItemType Container -Path $FolderPath -Confirm:$false

            # move to folder
            Set-Location -Path $FolderPath
        }
    }
}
#EndRegion '.\Public\Utility\New-IRTInvestigationFolder.ps1' 124
#Region '.\Public\Utility\Open-IRTConfig.ps1' -1

function Open-IRTConfig {
    <#
    .SYNOPSIS
    Opens the IRT config.json file for editing.
    #>
    [Alias('OpenConfig')]
    [CmdletBinding()]
    param()

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $JoinParams = @{
        Path                = $env:APPDATA
        ChildPath           = $ModuleName
        AdditionalChildPath = 'config.json'
    }
    $ConfigPath = Join-Path @JoinParams

    if (-not (Test-Path $ConfigPath)) {
        Import-IRTConfig
    }

    Invoke-Item $ConfigPath
}
#EndRegion '.\Public\Utility\Open-IRTConfig.ps1' 24
#Region '.\Public\Utility\Set-IRTConfig.ps1' -1

function Set-IRTConfig {
    <#
    .SYNOPSIS
    Interactively updates IRT configuration settings.

    .DESCRIPTION
    Presents a menu of configuration settings. When the user selects a setting,
    shows a description and available options, then saves the new value.

    .PARAMETER Reset
    Reset config to the template defaults without showing the menu.
    #>
    [Alias('SetIRTConfig', 'Set-IRTConfigs', 'SetIRTConfigs')]
    [Alias('Set-Config', 'SetConfig', 'Set-Configs', 'SetConfigs')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $Reset
    )

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir = Join-Path -Path $env:APPDATA -ChildPath $ModuleName
    $ConfigPath = Join-Path -Path $ConfigDir -ChildPath 'config.json'
    $TplJoin = @{
        Path                = $ModuleRoot
        ChildPath           = 'Data'
        AdditionalChildPath = 'ConfigTemplate.json'
    }
    $TemplatePath = Join-Path @TplJoin

    if ($Reset) {
        if ($PSCmdlet.ShouldProcess($ConfigPath, 'Reset to template defaults')) {
            if (-not (Test-Path $ConfigDir)) {
                $null = New-Item -ItemType Directory -Path $ConfigDir -Force
            }
            Copy-Item -Path $TemplatePath -Destination $ConfigPath -Force
            $Global:IRT_Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            Write-IRT "Config reset to defaults."
            return
        }
        return
    }

    Import-IRTConfig
    $Config = $Global:IRT_Config

    # define settings metadata
    $Settings = [ordered]@{
        PasswordBrowser = @{
            Summary     = 'Browser for opening password URLs in Tenants CSV'
            Description = 'Which browser to use when opening password URLs from the Tenants CSV. ' +
            'Set to "default" to use the system default browser.'
            Options     = @('default', 'msedge', 'chrome', 'firefox', 'brave')
        }
        Browser = @{
            Summary     = 'Browser for opening other URLs'
            Description = 'Which browser to use when opening OWA links and ' +
            'other web pages. (where possible) ' +
            'Set to "default" to use the system default browser.'
            Options     = @('default', 'msedge', 'chrome', 'firefox', 'brave')
        }
        ExcelTableStyle = @{
            Summary     = 'Excel table style'
            Description = 'The table style applied to Excel worksheets exported by IRT. ' +
            'Uses ImportExcel style names (e.g. Dark1-Dark11, ' +
            'Medium1-Medium28, Light1-Light21).'
            Options     = @(
                'Dark1', 'Dark2', 'Dark3', 'Dark4', 'Dark5', 'Dark6',
                'Dark7', 'Dark8', 'Dark9', 'Dark10', 'Dark11',
                'Medium1', 'Medium2', 'Medium3', 'Medium4', 'Medium5', 'Medium6', 'Medium7',
                'Light1', 'Light2', 'Light3', 'Light4', 'Light5', 'Light6', 'Light7'
            )
        }
        ExcelFont = @{
            Summary     = 'Excel font name'
            Description = 'The font used across all Excel output. ' +
            'Monospace fonts like Consolas work best for log data. ' +
            'Enter any font name installed on your system.'
            Options     = $null  # free text
        }
        ExportXml = @{
            Summary     = 'Export raw XML with log pulls'
            Description = 'When enabled, log commands ' +
            '(sign-in logs, UAL, message trace) will save ' +
            'the raw XML response alongside the parsed Excel output.'
            Options     = @('true', 'false')
        }
        AllOperationsSheetPath = @{
            Summary     = 'All Operations sheet path'
            Description = 'Path to the UALAllOperations.xlsx file ' +
            'used for operation lookups. ' +
            'Leave blank (null) to use the default file bundled with the module. ' +
            'Set to an absolute path to use a custom file outside the module.'
            Options     = $null  # free text / file path
        }
        TenantsSheetPath = @{
            Summary     = 'Tenants worksheet path'
            Description = 'Path to the tenants.xlsx file used by Connect-IRTTenant. ' +
            'Leave blank (null) to use the default location: ' +
            '$env:APPDATA\M365IncidentResponseTools\tenants.xlsx. ' +
            'Set to an absolute path to use a custom file.'
            Options     = $null  # free text / file path
        }
        MaxRunspaces = @{
            Summary     = 'Maximum runspaces for parallel operations'
            Description = 'Maximum number of runspaces used for parallel processing.'
            Options     = $null  # free text / integer
        }
        MaxExchangeConnections = @{
            Summary     = 'Maximum concurrent Exchange connections'
            Description = 'Maximum number of concurrent Exchange Online connections. ' +
            '(Recommend 10 or lower: https://techcommunity.microsoft.com/blog/exchange/' +
            'more-efficient-bulk-operations-with-powershell-parallelism/4409693)'
            Options     = $null  # free text / integer
        }
        PromptColor = @{
            Summary     = 'Prompt color'
            Description = 'Foreground color used for the IRT prompt labels ' +
            '(e.g. "[IRT]", "Graph:", "Exchange:").'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        InfoColor = @{
            Summary     = 'Informational message color'
            Description = 'Foreground color used for informational messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        WarnColor = @{
            Summary     = 'Warning message color'
            Description = 'Foreground color used for warning messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        ErrorColor = @{
            Summary     = 'Error message color'
            Description = 'Foreground color used for error messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        EnableTokenCache = @{
            Summary         = 'Persistent MSAL token cache'
            Description     = 'When enabled, refresh tokens are written to an ' +
            'encrypted file on disk, so Connect-IRT skips the browser prompt ' +
            'across PowerShell sessions (up to ~90 days, until the refresh token ' +
            'expires or is revoked). On first use, the required ' +
            'Microsoft.Identity.Client.Extensions.Msal DLL is downloaded from ' +
            'nuget.org. Run Clear-IRTTokenCache to wipe the cache.'
            SecurityWarning = 'SECURITY WARNING: The cache file is DPAPI-encrypted and ' +
            'bound to your Windows user account, but any process running as that ' +
            'user can decrypt it. Do not enable this on shared or multi-user ' +
            'machines. Always run Clear-IRTTokenCache when you finish an investigation.'
            Options         = @('true', 'false')
        }
        MsalCachePath = @{
            Summary     = 'MSAL token cache file path'
            Description = 'Absolute path for the DPAPI-encrypted MSAL token cache file. ' +
            'Leave blank (null) to use the default path set in ' +
            'M365IncidentResponseTools.psm1. ' +
            'Override to an isolated path for testing or multi-instance scenarios. ' +
            'Takes effect on the next Connect-IRT call.'
            Options     = $null  # free text / file path
        }
        IPConditionalFormattingTemplatePath = @{
            Summary     = 'IP address CF template path'
            Description = 'Absolute path to an Excel file whose first sheet A columncontains the ' +
            'conditional-formatting rules to apply to IP address columns. ' +
            'Leave blank (null) to use the default template bundled with the module ' +
            '(Data/IpAddressConditionalFormattingTemplate.xlsx). ' +
            'Replace with a custom file to change color-coding without editing code.'
            Options     = $null  # free text / file path
        }
    }

    # main menu loop
    while ($true) {
        $MenuOptions = [ordered]@{}
        $KeyMap = [ordered]@{}
        $i = 1
        foreach ($Key in $Settings.Keys) {
            $CurrentVal = $Config.$Key
            $MenuOptions["$i"] = @{
                String = "$($Settings[$Key].Summary.PadRight(22)) $('='.PadLeft(2)) $CurrentVal"
                Color  = 'White'
            }
            $KeyMap["$i"] = $Key
            $i++
        }
        $MenuOptions["$i"] = @{ String = 'Reset to defaults'; Color = 'Yellow' }
        $ResetIndex = "$i"
        $i++
        $MenuOptions["$i"] = @{ String = 'Done'; Color = 'Green' }
        $DoneIndex = "$i"

        $Choice = Build-Menu -Options $MenuOptions -Title 'IRT Configuration' -List

        if ($Choice -eq $MenuOptions[$DoneIndex].String) {
            break
        }

        if ($Choice -eq $MenuOptions[$ResetIndex].String) {
            Set-IRTConfig -Reset
            $Config = $Global:IRT_Config
            continue
        }

        # Find which setting was selected
        $SelectedKey = $null
        foreach ($mi in $KeyMap.Keys) {
            if ($Choice -eq $MenuOptions[$mi].String) {
                $SelectedKey = $KeyMap[$mi]
                break
            }
        }
        if (-not $SelectedKey) { continue }

        $Setting = $Settings[$SelectedKey]
        $CurrentVal = $Config.$SelectedKey

        Write-IRT ''
        Write-IRT $Setting.Description
        if ($Setting.SecurityWarning) {
            Write-IRT ''
            Write-IRT $Setting.SecurityWarning -Level Error
        }
        Write-IRT "Current value: $CurrentVal"
        Write-IRT ''

        if ($Setting.Options) {
            # Build a selection menu from predefined options
            $NewValue = Build-Menu -Options $Setting.Options -Title 'Select a value:' -List
        }
        else {
            # Free text input; for path settings blank clears back to null (restores default)
            if ($SelectedKey -in 'AllOperationsSheetPath', 'TenantsSheetPath') {
                $NewValue = Read-Host "Enter new value (blank to clear and use module default)"
            }
            else {
                $NewValue = Read-Host "Enter new value (blank to keep current)"
                if ([string]::IsNullOrWhiteSpace($NewValue)) {
                    Write-IRT "Keeping current value: $CurrentVal"
                    continue
                }
            }
        }

        # Convert blank/null path settings back to null
        if ($SelectedKey -in 'AllOperationsSheetPath', 'TenantsSheetPath') {
            if ([string]::IsNullOrWhiteSpace($NewValue)) { $NewValue = $null }
        }

        # Convert string to bool for boolean settings
        if ($SelectedKey -in 'ExportXml', 'EnableTokenCache') {
            $NewValue = $NewValue -eq 'true'
        }

        # Convert string to int for integer settings
        if ($SelectedKey -in 'MaxRunspaces', 'MaxExchangeConnections') {
            $NewValue = [int]$NewValue
        }

        $Config.$SelectedKey = $NewValue

        if ($PSCmdlet.ShouldProcess($ConfigPath, "Set $SelectedKey = $NewValue")) {
            $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding utf8
            $Global:IRT_Config = $Config
            Write-IRT "$SelectedKey updated to: $NewValue"
        }
    }
}
#EndRegion '.\Public\Utility\Set-IRTConfig.ps1' 283
#Region '.\Public\Utility\Start-IRTPlaybook.ps1' -1

function Start-IRTPlaybook {
    <#
    .SYNOPSIS
    Runs multiple functions to assist in investigating a user's activity.

    .DESCRIPTION
    The incident response playbook is the primary investigation entry point.
    It accepts one or more Entra ID user objects and launches ~15 investigation steps in
    parallel, then saves output files to the investigation folder.

    Steps include: license report, user info, app assignments, mailbox details, admin roles,
    risky applications, MFA state, message trace, inbox rules, Entra audit log, sign-in logs,
    non-interactive sign-in logs, and Unified Audit Log (UAL).

    If -UserObject is omitted the function falls back to $Global:IRT_UserObjects populated
    by Find-User.

    .PARAMETER UserObject
    One or more Entra ID user objects to investigate. Accepts the objects returned by
    Find-GraphUser or Get-GlobalUserObject. Falls back to global session objects if omitted.

    .PARAMETER Ticket
    Ticket or case number string. Used to name the investigation folder when -NoFolder is
    not specified.

    .PARAMETER NoFolder
    Skip creating an investigation output folder. Results are still displayed in the console
    but not written to disk.

    .PARAMETER MaxRunspaces
    Maximum number of parallel runspaces. Default: 15. Reduce if the host machine has
    limited memory or Graph throttling is a concern.

    .EXAMPLE
    Find-GraphUser 'jsmith@contoso.com'
    Start-IRTPlaybook
    Look up a user, then run the full playbook using the global user object.

    .EXAMPLE
    Start-IRTPlaybook -UserObject $User -Ticket 'INC-1234'
    Run the playbook for an already-resolved user object and name the output folder INC-1234.

    .EXAMPLE
    Start-IRTPlaybook -UserObject $User -NoFolder -MaxRunspaces 5
    Run without writing files, using a limited runspace pool.

    .OUTPUTS
    None. All output is written to the investigation folder or displayed in the console.

    .NOTES
    Version: 2.2.0
    2.2.0 - Added license report, added error handling to close runspaces when script exits.
    2.1.0 - Added ability to run parallel exchange runspaces using exchange access token.
    2.0.0 - Added ability to run mulitple operations in parallel using runspaces.
    #>
    [Alias('Playbook')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $Ticket,
        [switch] $NoFolder,
        [switch] $NoNewTab,
        [int] $MaxRunspaces = 15
    )

    begin {

        #region BEGIN


        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                $ErrMsg = 'No -UserObject argument used, no $Global:IRT_UserObjects present.'
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = $ErrMsg
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        # verify connected to graph
        if (-not (Get-MgContext)) {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Graph. Run Connect-MgGraph."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
    }

    process {

        $Target = $ScriptUserObjects[0].UserPrincipalName
        if (-not $PSCmdlet.ShouldProcess($Target, 'Start incident response playbook')) {
            return
        }

        if (-not $NoFolder) {

            # make directory
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: New-IRTInvestigationFolder $Elapsed"
            $DirParams = @{
                UserObject = $ScriptUserObjects
            }
            if ( $Ticket ) {
                $DirParams['Ticket'] = $Ticket
            }
            else {
                $DirParams['Confirm'] = $true
            }
            New-IRTInvestigationFolder @DirParams
        }

        if (-not $NoNewTab) {
            Open-IRTTab
        }

        $WorkingPath = Get-Location

        # reset wait flags for this run (IRT_IpInfo and IRT_MessageTraceTable are
        # initialized as synchronized hashtables by the module and persist across runs)
        $Global:IRT_WaitFlags = [hashtable]::Synchronized(@{
                MessageTraceUserDone     = $false
                MessageTraceAllUsersDone = $false
            })

        # pre-populate caches in main thread
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-DirectoryRole $Elapsed"
        Request-DirectoryRole -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-DirectoryRoleTemplate $Elapsed"
        Request-DirectoryRoleTemplate -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphGroup $Elapsed"
        Request-GraphGroup -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphOauth2Grant $Elapsed"
        Request-GraphOauth2Grant -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphUser $Elapsed"
        Request-GraphUser -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphServicePrincipal $Elapsed"
        Request-GraphServicePrincipal -Return 'none'

        # pack references for injection into child runspace globals
        $SharedRefs = @{
            IRT_IpInfo                     = $Global:IRT_IpInfo
            IRT_MessageTraceTable          = $Global:IRT_MessageTraceTable
            IRT_WaitFlags                  = $Global:IRT_WaitFlags
            IRT_DirectoryRoles             = $Global:IRT_DirectoryRoles
            IRT_DirectoryRolesById         = $Global:IRT_DirectoryRolesById
            IRT_DirectoryRoleTemplates     = $Global:IRT_DirectoryRoleTemplates
            IRT_DirectoryRoleTemplatesById = $Global:IRT_DirectoryRoleTemplatesById
            IRT_Groups                     = $Global:IRT_Groups
            IRT_GroupsById                 = $Global:IRT_GroupsById
            IRT_Oauth2Grants               = $Global:IRT_Oauth2Grants
            IRT_Oauth2GrantsByClientId     = $Global:IRT_Oauth2GrantsByClientId
            IRT_Users                      = $Global:IRT_Users
            IRT_UsersById                  = $Global:IRT_UsersById
            IRT_ServicePrincipals          = $Global:IRT_ServicePrincipals
            IRT_ServicePrincipalsByAppId   = $Global:IRT_ServicePrincipalsByAppId
            IRT_ServicePrincipalsById      = $Global:IRT_ServicePrincipalsById
            IRT_EntraErrorTable            = $Global:IRT_EntraErrorTable
            IRT_UalOperationsData          = $Global:IRT_UalOperationsData
            IRT_UalUserTypeTable           = $Global:IRT_UalUserTypeTable
            IRT_TenantInfoTable            = $Global:IRT_TenantInfoTable
            IRT_Session                    = $Global:IRT_Session
            IRT_UserObjects                = $ScriptUserObjects
        }

        # build Exchange connection params once for all runspaces
        $ExoConnectParams = @{
            AccessToken       = $Global:IRT_Session.Exchange.Token
            UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
            ShowBanner        = $false
        }
        if ($Global:IRT_Session.Environment -in @('GCC High', 'DoD', 'USGov')) {
            $ExoConnectParams['ExchangeEnvironmentName'] = 'O365USGovGCCHigh'
        }

        #region playbook steps

        $Steps = @(

            @{  Name   = 'Get-IRTLicenseReport' # FIXME not included in module?
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Get-IRTLicenseReport
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-IRTUser'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Show-IRTUser
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTUserServicePrincipal'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Get-IRTUserServicePrincipal -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-IRTMailbox'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Show-IRTMailbox -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTAdminRole'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    $AdminParams = @{
                        Excel     = $true
                        Highlight = $Global:IRT_UserObjects.UserPrincipalName
                        Cached    = $true
                    }
                    Get-IRTAdminRole @AdminParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Find-IRTRiskyServicePrincipal'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Find-IRTRiskyServicePrincipal -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-IRTUserMfa'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Show-IRTUserMfa
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTMessageTrace'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        UserObject = $Global:IRT_UserObjects
                        Days = 90
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-IRTInboxRule'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    Get-IRTInboxRule
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-IRTEntraAuditLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Get-IRTEntraAuditLog -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTEntraSignInLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Get-IRTEntraSignInLog
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTUnifiedAuditLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        WaitOnMessageTrace = $true
                        Cached = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'UALRiskyOperations'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        RiskyOperations = $true
                        Days = 180
                        Cached = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'UALSignInLogs'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        SignInLogs = $true
                        Cached = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-IRTNonInteractiveSignIn'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Get-IRTNonInteractiveSignIn
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTMessageTrace -AllUsers'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) {
                        Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k]
                    }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        AllUsers = $true
                        Days = 10
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }
        )

        #region open runspaces

        try {

            $Global:IRT_Playbook_JobList = @()
            $Global:IRT_Playbook_RunspacePool = $null

            ### build a runspace pool
            $IssType = [System.Management.Automation.Runspaces.InitialSessionState]
            $InitialSessionState = $IssType::CreateDefault()
            $InitialSessionState.ImportPSModule(
                'ExchangeOnlineManagement',
                'M365IncidentResponseTools',
                'Microsoft.Graph.Authentication',
                'Microsoft.Graph.Applications',
                'Microsoft.Graph.Beta.Reports',
                'Microsoft.Graph.Users'
            )
            $Global:IRT_Playbook_RunspacePool = [RunspaceFactory]::CreateRunspacePool(
                1, $MaxRunspaces, $InitialSessionState, $Host
            )
            $Global:IRT_Playbook_RunspacePool.Open()

            ### queue tasks
            $Global:IRT_Playbook_JobList = foreach ($Step in $Steps) {

                $PowerShell = [PowerShell]::Create()
                $PowerShell.RunspacePool = $Global:IRT_Playbook_RunspacePool

                $null = $PowerShell.AddScript($Step.Script)
                foreach ($Arg in $Step.Args) {
                    $null = $PowerShell.AddArgument($Arg)
                }

                # loop output
                [pscustomobject]@{
                    Name       = $Step.Name
                    PowerShell = $PowerShell
                    Handle     = $PowerShell.BeginInvoke()
                    Completed  = $false
                }
            }

            #region wait on runspaces
            while ($Global:IRT_Playbook_JobList.Completed -contains $false) {
                foreach ($Job in $Global:IRT_Playbook_JobList) {
                    if ( -not $Job.Completed -and $Job.Handle.IsCompleted ) {
                        try {
                            $Job.PowerShell.EndInvoke( $Job.Handle )

                            # output errors, if any
                            foreach ($RunspaceError in $Job.PowerShell.Streams.Error) {
                                Write-IRT "$($Job.Name) error:" -Level Error
                                Write-Error -ErrorRecord $RunspaceError
                            }
                        }
                        catch {
                            Write-IRT "$($Job.Name): exception during EndInvoke" -Level Error
                            Write-Error -ErrorRecord $_
                        }
                        finally {
                            $Job.PowerShell.Dispose()
                            $Job.Completed = $true
                        }
                    }
                }

                $TotalJobs = $Global:IRT_Playbook_JobList.Count
                $CompletedJobs = $Global:IRT_Playbook_JobList | Where-Object { $_.Completed }
                $CompletedCount = $CompletedJobs.Count
                $RemainingNames = $Global:IRT_Playbook_JobList |
                    Where-Object { -not $_.Completed } |
                    Select-Object -ExpandProperty Name
                $PercentComplete = [int](($CompletedCount / $TotalJobs) * 100)
                $WpParams = @{
                    Activity        = 'Playbook Running'
                    Status          = "Waiting on: $($RemainingNames -join ', ')"
                    PercentComplete = $PercentComplete
                }
                Write-Progress @WpParams
                Start-Sleep -Seconds 10
            }
            Write-Progress -Activity 'Playbook Running' -Completed
        }
        #region cleanup
        finally {
            # stop all runspaces
            foreach ($Job in $Global:IRT_Playbook_JobList) {
                try { $Job.PowerShell.Stop() } catch {}
                try { $Job.PowerShell.Dispose() } catch {}
            }
            $Global:IRT_Playbook_JobList = @()

            # close pool
            if ($Global:IRT_Playbook_RunspacePool) {
                try { $Global:IRT_Playbook_RunspacePool.Close() }  catch {}
                try { $Global:IRT_Playbook_RunspacePool.Dispose() } catch {}
            }
            $Global:IRT_Playbook_RunspacePool = $null
        }

        $Stopwatch.Stop()
        $TotalElapsed = $Stopwatch.Elapsed.ToString()
        Write-Verbose "${FunctionName}: Playbook complete. Total elapsed: $TotalElapsed"
    }
}
#EndRegion '.\Public\Utility\Start-IRTPlaybook.ps1' 651
#Region '.\Suffix.ps1' -1

# ModuleBuilder Notes: Code in this file will be appended to the built .psm1 file.

# output info stream to host
$InformationPreference = 'Continue'

# when removing module from session, restore original prompt function if it was modified
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($Global:IRT_OriginalPrompt) {
        ${function:global:prompt} = $Global:IRT_OriginalPrompt
    }
}

# Initialize shared global caches as synchronized hashtables.
# Using Synchronized everywhere costs nothing measurable and is safe for runspace sharing.
# Existing data is preserved on module re-import (-Force).
foreach ($VarName in 'IRT_IpInfo', 'IRT_MessageTraceTable') {
    $Current = Get-Variable -Name $VarName -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if (-not ($Current -is [hashtable] -and $Current.IsSynchronized)) {
        $Existing = if ($Current -is [hashtable]) { $Current } else { @{} }
        Set-Variable -Name $VarName -Scope Global -Value ([hashtable]::Synchronized($Existing))
    }
}

# Cloud endpoint definitions used by OIDC probing and all Connect-IRT* functions.
# Ordered so OIDC probing tries Commercial first, then USGov, then China.
$Global:IRT_CloudEnvironments = [ordered]@{
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
        # maybe this instead? md docs inconsistent:
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

# Load user config on module import
Import-IRTConfig

# Set the default MSAL cache path if the config does not override it.
if (-not $Global:IRT_Config.MsalCachePath) {
    $JpParams = @{
        Path                = $env:LOCALAPPDATA
        ChildPath           = 'M365IncidentResponseTools'
        AdditionalChildPath = 'IRT-Cache.bin'
    }
    $Global:IRT_Config.MsalCachePath = Join-Path @JpParams
}

# Set the default IP address CF template path when the config does not override it.
if (-not $Global:IRT_Config.IPConditionalFormattingTemplatePath) {
    $IpcftJoin = @{
        Path                = $PSScriptRoot
        ChildPath           = 'Data'
        AdditionalChildPath = 'IpAddressConditionalFormattingTemplate.xlsx'
    }
    $Global:IRT_Config.IPConditionalFormattingTemplatePath = Join-Path @IpcftJoin
}

# Check ip_info availability once at module load and cache in config.
$Global:IRT_Config.IpInfoAvailable = (Test-PythonPackage -Name 'ip_info').Present

# Load static reference data (error codes, UAL operation metadata, UAL user types).
Import-ReferenceData

# Set terminal title on module load.
Set-TerminalTitle '[IRT]'

# verbose: output module load time
if ($Global:IRT_LoadStopwatch) {
    $Global:IRT_LoadStopwatch.Stop()
    $Elapsed = $Global:IRT_LoadStopwatch.Elapsed.TotalSeconds
    Write-Verbose "Module loaded in $($Elapsed.ToString('N2'))s."
    Remove-Variable -Name 'IRT_LoadStopwatch' -Scope Global
}
#EndRegion '.\Suffix.ps1' 106

