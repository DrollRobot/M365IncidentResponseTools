function Get-IRTAccessToken {
    <#
    .SYNOPSIS
    Acquires an access token for Graph, Exchange Online, or IPPS from the MSAL cache.

    .DESCRIPTION
    The single token authority for the module. Mints tokens on demand from the
    session's MSAL public client apps: cached access tokens are returned in
    microseconds, expired ones are silently renewed via the refresh token, and
    only when no cached account works does it fall back to interactive browser
    sign-in (unless -Silent).

    Cached accounts are tried in smart order (Select-IRTMsalAccount): the
    account that last worked for this client ID, then accounts homed in the
    target tenant, then any other account in the same cloud. Every candidate is
    tried before prompting, so a cache full of other customers' accounts never
    causes a spurious sign-in prompt.

    Tokens are never stored by this function - callers use the result
    immediately (e.g. to bind an SDK connection or call a REST API). Inside
    playbook runspace workers ($Global:IRT_IsRunspaceWorker) the function is
    always silent, so a worker can never pop a hidden browser prompt.

    .PARAMETER Service
    Which service to acquire a token for: Graph, Exchange, or IPPS.

    .PARAMETER SearchOnly
    IPPS only. Use the search-only audience (dataservice.o365filtering.com)
    instead of the full Exchange audience. Defaults to $true, matching
    Connect-IRTIPPS.

    .PARAMETER AdditionalScope
    Graph only. Additional delegated scopes to request beyond the default
    incident-response set.

    .PARAMETER Silent
    Never prompt. If no cached account yields a token silently, throw instead
    of opening a browser.

    .PARAMETER ForceRefresh
    Bypass the cached access token and force MSAL to redeem the refresh token.
    Used after audience-validation failures.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the session override if set,
    otherwise the service's first-party app (Graph CLI Tools for Graph, the EXO
    app for Exchange and IPPS).

    .EXAMPLE
    ```powershell
    Get-IRTAccessToken -Service Exchange -Silent
    ```
    Returns a fresh Exchange token from the cache without ever prompting.

    .EXAMPLE
    ```powershell
    (Get-IRTAccessToken -Service Graph).AccessToken
    ```
    Returns just the bearer token string for a manual Graph REST call.

    .OUTPUTS
    Microsoft.Identity.Client.AuthenticationResult. Callers typically use
    .AccessToken, .ExpiresOn, and .Account.Username.

    .NOTES
    Version: 1.0.0
    Requires ExchangeOnlineManagement >= 3.2.0 module-wide for token-based
    connections (the enforced floor is 3.6.0).
    #>
    [OutputType('Microsoft.Identity.Client.AuthenticationResult')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Graph', 'Exchange', 'IPPS')]
        [string] $Service,

        [bool] $SearchOnly = $true,

        [Alias('AdditionalScopes')]
        [string[]] $AdditionalScope,

        [switch] $Silent,
        [switch] $ForceRefresh,

        [string] $ClientId
    )

    begin {
        #region BEGIN

        # import modules
        Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'PSFramework'

        if (-not $Global:IRT_Session -or
            -not $Global:IRT_Session.TenantId -or
            -not $Global:IRT_Session.CloudConfig) {
            throw 'No active IRT session. Run Connect-IRT first.'
        }

        # Runspace workers must never pop a (hidden) browser prompt.
        if ($Global:IRT_IsRunspaceWorker) {
            $Silent = $true
        }

        $TenantId = $Global:IRT_Session.TenantId
        $CloudConfig = $Global:IRT_Session.CloudConfig

        # Resolve client ID: parameter > session override > service default.
        $ServiceDefaultClientId = switch ($Service) {
            'Graph' { '14d82eec-204b-4c2f-b7e8-296a70dab67e' }  # Microsoft Graph CLI Tools
            default { 'fb78d390-0c51-40cd-8e17-fdbfab77341b' }  # EXO/IPPS first-party app
        }
        $ResolvedClientId = if ($ClientId) {
            $ClientId
        } elseif ($Global:IRT_Session.ClientId) {
            $Global:IRT_Session.ClientId
        } else {
            $ServiceDefaultClientId
        }

        # Resolve MSAL scope strings for the service.
        $MsalScopes = switch ($Service) {
            'Graph' {
                $PlainScopes = $Global:IRT_Session.Graph?.Scopes ?? (Get-IRTGraphDefaultScope)
                if ($AdditionalScope) {
                    $PlainScopes = @($PlainScopes) + $AdditionalScope | Select-Object -Unique
                }
                [string[]]($PlainScopes | ForEach-Object { "$($CloudConfig.Graph)/$_" })
            }
            'Exchange' {
                [string[]]@($CloudConfig.Exchange)
            }
            'IPPS' {
                [string[]]@($SearchOnly ? $CloudConfig.IPPSSearchOnly : $CloudConfig.Exchange)
            }
        }
        # The switch statement enumerates its output into object[], which does not
        # bind to MSAL's IEnumerable[string] scope parameters - re-type explicitly.
        $MsalScopes = [string[]]$MsalScopes

        # Bare login host (no scheme) used to match cached MSAL accounts to this cloud.
        $ExpectedLoginHost = $CloudConfig.LoginHost.Replace('https://', '')

        Write-PSFMessage -Level 8 -Message (
            "Get-IRTAccessToken: Service=$Service, TenantId=$TenantId, " +
            "ClientId=$ResolvedClientId, Scopes=$($MsalScopes.Count), " +
            "Silent=$Silent, ForceRefresh=$ForceRefresh")
    }

    process {
        #region PROCESS

        $App = Get-IRTPublicClient -ClientId $ResolvedClientId

        # ---------- Silent acquisition: try every candidate account ----------

        $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
        $SelectParams = @{
            Account           = $Cached
            TenantId          = $TenantId
            ExpectedLoginHost = $ExpectedLoginHost
            StickyAccountId   = $Global:IRT_Session.StickyAccount?[$ResolvedClientId]
        }
        $Candidates = Select-IRTMsalAccount @SelectParams

        foreach ($Candidate in $Candidates) {
            try {
                Write-PSFMessage -Level 8 -Message (
                    "Attempting silent $Service token acquisition for: " +
                    "$($Candidate.Username) (env: $($Candidate.Environment))")
                $Builder = $App.AcquireTokenSilent($MsalScopes, $Candidate)
                if ($ForceRefresh) {
                    $Builder = $Builder.WithForceRefresh($true)
                }
                $Result = $Builder.ExecuteAsync().GetAwaiter().GetResult()

                # Reject a token issued for a DIFFERENT tenant. MSAL can hand back
                # a token in the account's home tenant even though this app's
                # authority targets $TenantId - e.g. a cached account that has no
                # presence in the target tenant. Nothing downstream checks the
                # realm (only the audience/cloud is validated), so such a token
                # would be bound and mislabeled as the target tenant. Treat it as
                # a failed candidate and move on, leaving the sticky pointer
                # untouched so it self-heals to the first correct-tenant account.
                # AuthenticationResult.TenantId is the issued realm; mirror the
                # audience-check contract and only act on a positively-wrong value
                # (an absent one is not punished).
                if ($Result.TenantId -and $Result.TenantId -ne $TenantId) {
                    Write-PSFMessage -Level 8 -Message (
                        "Discarding $Service token for $($Candidate.Username): " +
                        "issued for tenant $($Result.TenantId), expected $TenantId.")
                    continue
                }

                Write-PSFMessage -Level 8 -Message (
                    "Silent $Service token acquisition succeeded for " +
                    "$($Result.Account.Username). Expiry: $($Result.ExpiresOn)")
                if ($null -ne $Global:IRT_Session.StickyAccount) {
                    $Global:IRT_Session.StickyAccount[$ResolvedClientId] =
                    $Result.Account.HomeAccountId.Identifier
                }
                return $Result
            } catch {
                Write-PSFMessage -Level 8 -Message (
                    "Silent $Service token acquisition failed for " +
                    "$($Candidate.Username): $_")
            }
        }

        # ---------- Interactive fallback ----------

        if ($Silent) {
            throw ("Silent $Service token acquisition failed for tenant $TenantId " +
                "($($Candidates.Count) cached account(s) tried) and interactive auth " +
                'is not allowed (-Silent). Run Connect-IRT to sign in interactively.')
        }

        $Msg = 'A browser window has been opened for interactive sign-in. ' +
        'Please complete authentication to continue.'
        Write-IRT $Msg -Level Warn
        try {
            $Cts = [System.Threading.CancellationTokenSource]::new()
            $Task = $App.AcquireTokenInteractive($MsalScopes).ExecuteAsync($Cts.Token)
            try {
                while (-not $Task.IsCompleted) { Start-Sleep -Milliseconds 250 }
            } finally {
                $Cts.Cancel()
                $Cts.Dispose()
            }
            $Result = $Task.GetAwaiter().GetResult()
        } catch {
            throw "Interactive token acquisition failed: $_"
        }

        # Same tenant guard as the silent path: a wrong-tenant interactive token
        # must not be bound and labeled as the target tenant. Interactive auth
        # against a tenant-scoped authority shouldn't yield this, so fail loud
        # rather than mislabel. Validated outside the try so the message isn't
        # wrapped as an acquisition failure.
        if ($Result.TenantId -and $Result.TenantId -ne $TenantId) {
            throw ("Interactive sign-in token for tenant '$($Result.TenantId)' " +
                "does not match the requested tenant '$TenantId'. " +
                'Sign in with an account that belongs to the target tenant.')
        }

        Write-PSFMessage -Level 8 -Message (
            "Interactive $Service token acquisition succeeded. " +
            "Account: $($Result.Account.Username), " +
            "Expiry: $($Result.ExpiresOn)")
        if ($null -ne $Global:IRT_Session.StickyAccount) {
            $Global:IRT_Session.StickyAccount[$ResolvedClientId] =
            $Result.Account.HomeAccountId.Identifier
        }
        return $Result
    }
}
