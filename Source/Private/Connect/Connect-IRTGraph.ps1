function Connect-IRTGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph with default incident response scopes.

    .DESCRIPTION
    Acquires a Graph token via Get-IRTAccessToken (silent from the MSAL cache
    when possible, interactive browser fallback otherwise), validates the token
    audience against the target cloud, binds it into the Graph SDK context via
    Connect-MgGraph -AccessToken, and verifies tenant-wide admin consent for the
    requested scopes.

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

    .PARAMETER Force
    Reconnect even when an apparently-healthy Graph context already exists.

    .PARAMETER Silent
    Never prompt. Token acquisition throws instead of opening a browser when no
    cached account works.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the Microsoft Graph CLI Tools
    first-party app (14d82eec-204b-4c2f-b7e8-296a70dab67e).

    .EXAMPLE
    Connect-IRTGraph -TenantId $Tid -Cloud Commercial

    .OUTPUTS
    [pscustomobject] - Graph session metadata: Account, Scopes,
    BoundTokenExpiry (expiry of the token bound into the SDK), TenantId.

    .NOTES
    Version: 4.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Connect-MgGraph requires a SecureString; the token is already in memory.')]
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

        [string] $ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Microsoft Graph CLI Tools
    )

    begin {
        #region BEGIN

        # import modules
        Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'PSFramework'

        # Plain scope names (no resource prefix) - used for MgContext scope checks
        # and the admin-consent flow. Get-IRTAccessToken builds the MSAL scope URLs.
        $Scopes = if ($AdditionalScope) {
            @(Get-IRTGraphDefaultScope) + $AdditionalScope | Select-Object -Unique
        } else {
            Get-IRTGraphDefaultScope
        }

        $CloudConfig = $Global:IRT_Session.CloudConfig
        $GraphBaseUrl = $CloudConfig.Graph

        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTGraph: TenantId=$TenantId, Cloud=$Cloud, " +
            "Scopes=$($Scopes.Count), Force=$Force, Silent=$Silent")
    }

    process {

        # ---------- Phase 1: token ----------
        # Get-IRTAccessToken is the single token authority: it mints from the MSAL
        # cache (trying every cached account for this cloud before prompting) and
        # falls back to interactive browser auth unless -Silent.

        $TokenParams = @{
            Service  = 'Graph'
            Silent   = $Silent
            ClientId = $ClientId
        }
        if ($AdditionalScope) { $TokenParams['AdditionalScope'] = $AdditionalScope }
        $TokenResult = Get-IRTAccessToken @TokenParams
        if (-not $TokenResult.AccessToken) {
            throw 'Failed to acquire Graph access token.'
        }
        $Token = $TokenResult.AccessToken
        $Account = $TokenResult.Account.Username
        Write-PSFMessage -Level 8 -Message "Token acquired for account: $Account"

        # ---------- Phase 1b: cloud validation ----------
        # Confirm the token's audience (aud) is the Graph endpoint for the cloud we're
        # connecting to. aud is the resource the token was minted for - e.g.
        # https://graph.microsoft.us for USGov vs https://graph.microsoft.com for
        # Commercial - so it's the authoritative cloud signal. (The iss claim is NOT:
        # v1.0 Graph access tokens use https://sts.windows.net/{tenant}/ in every cloud.)
        #
        # A wrong-cloud token passes expiry/scope checks but fails at the Graph API with
        # InvalidCloudInstance / 401. Get-IRTAccessToken already selects cached accounts
        # by environment, so silent acquisition can't hand back a wrong-cloud token; this
        # is a final assertion. On mismatch, force-refresh once for the correct cloud.
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

            $TokenResult = Get-IRTAccessToken @TokenParams -ForceRefresh
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Graph access token after cloud mismatch.'
            }
            $Token = $TokenResult.AccessToken
            $Account = $TokenResult.Account.Username

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
        # Connect if no context, wrong tenant, wrong cloud, missing scopes, or MSAL
        # handed us a newer token than the one currently bound (the existing MgContext
        # is still holding the old one).

        $Ctx = Get-MgContext -ErrorAction SilentlyContinue
        Write-PSFMessage -Level 8 -Message (
            'Preconnect MgContext - ' +
            "TenantId: $($Ctx.TenantId), " +
            "Environment: $($Ctx.Environment) " +
            "(expected: $($CloudConfig.GraphEnv)), " +
            "Account: $($Ctx.Account)")

        $BoundTokenExpiry = $Global:IRT_Session.Graph?.BoundTokenExpiry ?? [datetime]::MinValue
        $NeedConnect = $Force -or
        (-not $Ctx) -or # not connected
        ($Ctx.TenantId -ne $TenantId) -or # wrong tenant
        ($Ctx.Environment -ne $CloudConfig.GraphEnv) -or # wrong cloud
        [bool]($Scopes | Where-Object { $Ctx.Scopes -notcontains $_ }) -or # missing scopes
        ($TokenResult.ExpiresOn.UtcDateTime -gt $BoundTokenExpiry) # newer token in hand

        Write-PSFMessage -Level 8 -Message "NeedConnect: $NeedConnect (pre-verify)"

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

        # Track whether a token is actually (re)bound this call. When nothing is
        # rebound, the SDK keeps the previously-bound token, so the reported
        # account/expiry must reflect the prior session record - not the token
        # just acquired, which may name a different account and would mislabel the
        # session.
        $DidBind = $false

        if ($NeedConnect) {
            $Ctx = Get-MgContext -ErrorAction SilentlyContinue
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
            $DidBind = $true
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

            # Entra replication for oauth2PermissionGrants can take 60-120+ seconds.
            # No point polling here - just inform the operator and continue.
            Write-IRT ('Admin consent browser flow completed. ' +
                'Tenant-wide grant may take up to 2 minutes to replicate.') -Level Warn

            # Re-acquire with a forced refresh and re-bind: the token bound above was
            # issued BEFORE the grant, so its scope claim lacks the new scopes and the
            # session would otherwise limp on it for the rest of its ~1h lifetime
            # (MSAL keeps returning the cached pre-consent token). Replication lag can
            # still delay the new scopes a couple of minutes, but that beats an hour.
            try {
                $TokenResult = Get-IRTAccessToken @TokenParams -ForceRefresh
                $Token = $TokenResult.AccessToken
                $Account = $TokenResult.Account.Username
                $Secure = ConvertTo-SecureString -String $Token -AsPlainText -Force
                $RebindParams = @{
                    AccessToken = $Secure
                    NoWelcome   = $true
                    Environment = $CloudConfig.GraphEnv
                }
                $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
                $null = Connect-MgGraph @RebindParams
                $DidBind = $true
                Write-PSFMessage -Level 8 -Message (
                    'Post-consent Graph token re-acquired and re-bound.')
            } catch {
                Write-IRT ("Post-consent token refresh failed: $_ - the current " +
                    'session keeps the pre-consent token until it expires.') -Level Warn
            }
        }

        if (-not $NeedConnect) {
            Write-IRT "Already connected to Graph for tenant $TenantId." -Level Warn
        }

        # Nothing was rebound: report what is actually bound (the prior session
        # record), since Get-MgContext exposes no account in -AccessToken mode and
        # the freshly-acquired token was never bound.
        if (-not $DidBind) {
            $Account = $Global:IRT_Session.Graph?.Account ?? $Account
            $BoundTokenExpiry = $Global:IRT_Session.Graph?.BoundTokenExpiry ??
            $TokenResult.ExpiresOn.UtcDateTime
        } else {
            $BoundTokenExpiry = $TokenResult.ExpiresOn.UtcDateTime
        }

        $Result = [pscustomobject]@{
            Account          = $Account
            Scopes           = [string[]]$Scopes
            BoundTokenExpiry = $BoundTokenExpiry
            TenantId         = $TenantId
        }
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTGraph complete. Account: $Account, " +
            "BoundTokenExpiry: $($Result.BoundTokenExpiry)")
        return $Result
    }
}
