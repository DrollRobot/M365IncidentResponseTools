function Connect-IRTGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph with default incident response scopes.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER GCCHigh
    Connect to a GCC High tenant environment.

    .PARAMETER DeviceCode
    Use device code authentication flow.

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Browser
    Browser to use for device code login. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .NOTES
    Version: 3.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'DeviceCode', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [Alias('AdditionalScopes')]
        [string[]] $AdditionalScope,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force
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

        $GraphBaseUrl = 'https://graph.microsoft.com'
        $Authority    = "https://login.microsoftonline.com/$TenantId"
        if ($GCCHigh) {
            $GraphBaseUrl = 'https://graph.microsoft.us'
            $Authority    = "https://login.microsoftonline.us/$TenantId"
        }
    }

    process {

        # ---------- Setup: MSAL app, token-acquisition helper ----------

        $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
        if (-not $GraphModule) {
            throw 'Microsoft.Graph.Authentication must be imported before connecting to Graph.'
        }
        $MsalDll = Join-Path $GraphModule.ModuleBase 'Dependencies' 'Core' 'Microsoft.Identity.Client.dll'
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
            Add-Type -Path $MsalDll
        }

        $GraphClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Microsoft Graph CLI Tools
        $MsalScopes    = [string[]]($Scopes | ForEach-Object { "$GraphBaseUrl/$_" })

        # Reuse the cached MSAL app instance to preserve its token cache (refresh token).
        $App = if ($Global:IRT_Session -and
                   $Global:IRT_Session.Graph -and
                   $Global:IRT_Session.Graph.PublicClientApplication -and
                   $Global:IRT_Session.TenantId -eq $TenantId
        ) {
            $Global:IRT_Session.Graph.PublicClientApplication
        } else {
            [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($GraphClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
        }

        # Inline helper - closes over $App, $MsalScopes, $DeviceCode, $Browser, $Private.
        # Tries silent refresh first, then interactive or device code.
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
                        return $App.AcquireTokenSilent($MsalScopes, ($Cached | Select-Object -First 1)).
                            ExecuteAsync().GetAwaiter().GetResult()
                    } catch {
                        Write-Verbose "Silent Graph token refresh failed: $_"
                    }
                }
            }

            if ($DeviceCode) {
                $Extra = if ($RequireConsent) { @{ prompt = 'consent' } } else { $null }
                $params = @{
                    App                  = $App
                    Scope                = $MsalScopes
                    ExtraQueryParameter  = $Extra
                    Browser              = $Browser
                    Private              = $Private
                }
                return Invoke-IRTDeviceCodeAuth @params
            }

            try {
                $Builder = $App.AcquireTokenInteractive($MsalScopes)
                if ($RequireConsent) {
                    $Builder = $Builder.WithPrompt([Microsoft.Identity.Client.Prompt]::Consent)
                }
                if ($Account) {
                    $Builder = $Builder.WithAccount($Account)
                }
                return $Builder.ExecuteAsync().GetAwaiter().GetResult()
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
                $Token   = $Global:IRT_Session.Graph.Token
                $Account = $Global:IRT_Session.Graph.Account
                Write-Verbose 'Using cached Graph token.'
            } else {
                Write-Verbose "Cached token missing scopes: $($TokenScopeMissing -join ', ')"
            }
        }

        if ($NeedNewToken) {
            if ($Global:IRT_Session -and $Global:IRT_Session.Graph -and $Global:IRT_Session.Graph.Token) {
                Write-IRT "Refreshing expired Graph token for tenant $TenantId." -Level Warn
            }
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Graph access token.'
            }
            $Token   = $TokenResult.AccessToken
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
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }
            $Secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
            $Params = @{ AccessToken = $Secure; NoWelcome = $true }
            if ($GCCHigh) { $Params['Environment'] = 'USGov' }
            Connect-MgGraph @Params
        }

        # ---------- Phase 3: admin consent ----------
        # Verify tenant-wide consent. The token may have all scopes via per-user
        # consent while admin consent is missing, so this is independent of
        # MgContext.Scopes. Drive the dedicated /adminconsent endpoint if anything
        # is missing - that flow has no checkbox to miss, so consent persists
        # tenant-wide reliably.

        try {
            $MissingAdminScopes = Test-IRTGraphAdminConsent -RequestedScope $Scopes
        } catch {
            Write-Warning ("Admin consent check failed - skipping consent verification. " +
                "Re-run Connect-IRT to retry. Error: $_")
            $MissingAdminScopes = @()
        }

        if ($MissingAdminScopes) {
            Write-IRT "Admin consent missing tenant-wide for $($MissingAdminScopes.Count) scope(s):" -Level Warn
            Write-IRT "  $($MissingAdminScopes -join ', ')" -Level Warn

            $ConsentParams = @{
                TenantId    = $TenantId
                ClientId    = $GraphClientId
                Scope       = $MissingAdminScopes  # only request what's actually missing
                ResourceUri = $GraphBaseUrl
                Browser     = $Browser
            }
            if ($GCCHigh) { $ConsentParams['GCCHigh'] = $true }
            if ($Private) { $ConsentParams['Private'] = $true }

            $null = Invoke-IRTAdminConsent @ConsentParams

            # Verify the grant landed. Brief retry window for replication.
            $StillMissing = $Scopes
            for ($Attempt = 1; $Attempt -le 5 -and $StillMissing; $Attempt++) {
                Start-Sleep -Seconds 2
                try {
                    $StillMissing = Test-IRTGraphAdminConsent -RequestedScope $Scopes
                } catch {
                    $StillMissing = $Scopes
                }
            }

            if ($StillMissing) {
                Write-Warning "Tenant-wide grant not yet visible for: $($StillMissing -join ', ')"
                Write-Warning 'Replication may still be in flight; re-run Connect-IRT shortly to confirm.'
            } else {
                Write-IRT 'Admin consent granted tenant-wide.'
            }
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Graph for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            Account                 = $Account
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
    }
}



#region Test-IRTGraphAdminConsent
function Test-IRTGraphAdminConsent {
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
    $ClientSp = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/servicePrincipals(appId='$ClientAppId')" -ErrorAction Stop
    $ResourceSp = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/servicePrincipals(appId='$ResourceAppId')" -ErrorAction Stop

    # Pull all AllPrincipals grants for this client/resource pair.
    # In practice there's usually one, but multiple are possible if
    # admins consented in batches.
    $Filter = "clientId eq '$($ClientSp.id)' and " +
              "resourceId eq '$($ResourceSp.id)' and " +
              "consentType eq 'AllPrincipals'"
    $Encoded = [uri]::EscapeDataString($Filter)
    $Grants  = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/oauth2PermissionGrants?`$filter=$Encoded" -ErrorAction Stop

    # scope is a space-delimited string per grant; flatten across grants
    $Granted = @($Grants.value | ForEach-Object { $_.scope -split '\s+' } |
                 Where-Object { $_ } | Select-Object -Unique)

    # Return the missing ones (case-insensitive compare)
    $RequestedScope | Where-Object { $Granted -notcontains $_ }
}


#region Invoke-IRTAdminConsent
function Invoke-IRTAdminConsent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $TenantId,
        [Parameter(Mandatory)] [string]   $ClientId,
        [Parameter(Mandatory)] [Alias('Scopes')] [string[]] $Scope,
        [string] $ResourceUri = 'https://graph.microsoft.com',
        [switch] $GCCHigh,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = 'default',
        [switch] $Private,

        [int] $TimeoutSeconds = 300
    )

    begin {
        $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Listener.Start()
        $Port        = ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
        $RedirectUri = "http://localhost:$Port/"
    }

    process {
        try {
            $LoginHost = if ($GCCHigh) { 'login.microsoftonline.us' } else { 'login.microsoftonline.com' }
            $State     = [guid]::NewGuid().ToString('N')

            # Fully-qualify each scope with the resource URI, then space-delimit.
            # This is what makes /v2.0/adminconsent work for dynamic-consent apps
            # like Microsoft Graph Command Line Tools, where /.default would only
            # consent to statically configured permissions (User.Read in this case).
            $ScopeQuery = ($Scope | ForEach-Object { "$ResourceUri/$_" }) -join ' '

            $ConsentUrl = "https://$LoginHost/$TenantId/v2.0/adminconsent" +
                        "?client_id=$ClientId" +
                        "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
                        "&state=$State" +
                        "&scope=$([uri]::EscapeDataString($ScopeQuery))"

            Write-IRT 'Opening admin consent page in browser...' -Level Warn
            Write-IRT "  Granting tenant-wide consent for $($Scope.Count) scope(s)." -Level Warn
            Write-IRT '  Sign in as a Global Administrator and click Accept.' -Level Warn
            Open-Browser -Browser $Browser -Url $ConsentUrl -Private:$Private

            $AcceptTask = $Listener.AcceptTcpClientAsync()
            if (-not $AcceptTask.Wait($TimeoutSeconds * 1000)) {
                throw "Timed out after $TimeoutSeconds seconds waiting for admin consent response."
            }
            $Client = $AcceptTask.Result

            try {
                $Stream      = $Client.GetStream()
                $Reader      = [System.IO.StreamReader]::new($Stream)
                $RequestLine = $Reader.ReadLine()

                $Body = '<html><body style="font-family:sans-serif;text-align:center;padding-top:4em">' +
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
            $Path  = $Matches[1]
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
                throw "Admin consent denied or failed: $($Params['error']) - $($Params['error_description'])"
            }
            if ($Params['admin_consent'] -eq 'True') {
                return $true
            }
            throw "Unexpected admin consent response: $Query"
        }
        finally {
            $Listener.Stop()
        }
    }
}