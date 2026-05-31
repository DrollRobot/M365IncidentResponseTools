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
