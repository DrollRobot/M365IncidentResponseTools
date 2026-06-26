function Connect-IRTExchange {
    <#
    .SYNOPSIS
    Connects to Exchange Online.

    .DESCRIPTION
    Acquires an Exchange token via Get-IRTAccessToken (silent from the MSAL
    cache when possible, interactive browser fallback otherwise), validates the
    token audience against the target cloud, and binds it to a REST connection
    via Connect-ExchangeOnline -AccessToken. Reconnects are scoped: the new
    connection is established first, then the previous one is disconnected by
    ConnectionId, so the IPPS connection (and any runspace-local connections)
    are never torn down as a side effect.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, USGovDoD, China.
    Mandatory - Connect-IRT resolves this via OIDC discovery and passes it in.

    .PARAMETER Force
    Reconnect even when an apparently-healthy connection already exists.

    .PARAMETER Silent
    Never prompt. Token acquisition throws instead of opening a browser when no
    cached account works.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the EXO first-party app
    (fb78d390-0c51-40cd-8e17-fdbfab77341b).

    .EXAMPLE
    Connect-IRTExchange -TenantId $Tid -Cloud Commercial

    .OUTPUTS
    [pscustomobject] - Exchange session metadata: UserPrincipalName,
    BoundTokenExpiry (expiry of the token bound into the SDK connection),
    ConnectionId, TenantId.

    .NOTES
    Version: 4.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [Parameter(Mandatory)]
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO first-party app
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
        $ExchangeScope = $CloudConfig.Exchange
        # Expected token audience host (the Exchange resource for this cloud, e.g.
        # outlook.office365.us). Used to confirm a token is for the right cloud.
        $ExpectedExchangeHost = ([uri]($ExchangeScope -replace '/\.default$', '')).Host

        # IPPS connections show up in Get-ConnectionInformation alongside EXO.
        # Distinguish by ConnectionUri matching the compliance endpoint - which differs
        # per cloud (outlook.com commercial, office365.us for USGov/DoD), so match both.
        $IppsUriPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'

        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTExchange: TenantId=$TenantId, Cloud=$Cloud, " +
            "Force=$Force, Silent=$Silent")
    }

    process {
        #region PROCESS

        # ---------- Phase 1: token ----------
        # Get-IRTAccessToken is the single token authority: it mints from the MSAL
        # cache (trying every cached account for this cloud before prompting) and
        # falls back to interactive browser auth unless -Silent.

        $TokenParams = @{
            Service  = 'Exchange'
            Silent   = $Silent
            ClientId = $ClientId
        }
        $TokenResult = Get-IRTAccessToken @TokenParams
        if (-not $TokenResult.AccessToken) {
            throw 'Failed to acquire Exchange access token.'
        }
        $Token = $TokenResult.AccessToken
        $Upn = $TokenResult.Account.Username
        Write-PSFMessage -Level 8 -Message "Exchange token acquired for account: $Upn"

        # ---------- Phase 1b: cloud validation ----------
        # Confirm the token's audience (aud) is the Exchange endpoint for this cloud (e.g.
        # outlook.office365.us for USGov). A wrong-cloud token passes expiry checks but is
        # rejected at use time. Env-filtered account selection already prevents the MSAL
        # cache from returning a wrong-cloud token; this is a final assertion.
        $TokenAud = (Get-TokenPayload -Token $Token).aud
        Write-PSFMessage -Level 8 -Message (
            "Exchange token audience: $TokenAud | " +
            "expected host: $ExpectedExchangeHost")

        if (-not $TokenAud) {
            Write-PSFMessage -Level 8 -Message (
                'Could not decode token audience; ' +
                'skipping cloud validation.')
        }
        elseif ($TokenAud -notlike 'http*') {
            Write-PSFMessage -Level 8 -Message (
                "Token audience is not a URL ('$TokenAud'); " +
                'skipping cloud validation.')
        }
        elseif (([uri]$TokenAud).Host -ne $ExpectedExchangeHost) {
            Write-IRT (
                "Exchange token audience '$TokenAud' " +
                'does not match the expected ' +
                "host '$ExpectedExchangeHost'. " +
                'Re-authenticating for the correct cloud.') -Level Warn
            $TokenResult = Get-IRTAccessToken @TokenParams -ForceRefresh
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Exchange access token after cloud mismatch.'
            }
            $Token = $TokenResult.AccessToken
            $Upn = $TokenResult.Account.Username
            $TokenAud = (Get-TokenPayload -Token $Token).aud
            if (([uri]$TokenAud).Host -ne $ExpectedExchangeHost) {
                throw (
                    "Acquired Exchange token audience '$TokenAud' " +
                    'still does not match ' +
                    "'$ExpectedExchangeHost'. " +
                    "Verify -Cloud '$Cloud' is correct " +
                    "for tenant $TenantId.")
            }
            Write-PSFMessage -Level 8 -Message (
                'Re-acquired Exchange token audience ' +
                'now matches expected cloud.')
        }

        # ---------- Phase 2: Connect-ExchangeOnline ----------
        # Connect if no existing EXO connection (IPPS connections are excluded by URI),
        # the bound token is stale, MSAL handed us a newer token than the bound one,
        # or -Force.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Connected' -and
                $_.TenantID -eq $TenantId -and
                $_.ConnectionUri -notmatch $IppsUriPattern
            }

        $BoundTokenExpiry = $Global:IRT_Session.Exchange?.BoundTokenExpiry ??
        [datetime]::MinValue
        $NeedConnect = $Force -or
        (-not $ExistingConnection) -or
        ($BoundTokenExpiry -lt [datetime]::UtcNow.AddMinutes(5)) -or
        ($TokenResult.ExpiresOn.UtcDateTime -gt $BoundTokenExpiry)

        Write-PSFMessage -Level 8 -Message "NeedConnect: $NeedConnect (pre-verify)"

        # Trust but verify: Get-ConnectionInformation reflects local session state, which
        # can report "Connected" while the session is actually dead. If we think we're
        # connected, confirm with a cheap live call before trusting it.
        if (-not $NeedConnect) {
            try {
                $null = Get-OrganizationConfig -ErrorAction Stop
                Write-PSFMessage -Level 8 -Message (
                    'Live Exchange verification succeeded; ' +
                    'existing connection is healthy.')
            } catch {
                Write-PSFMessage -Level 8 -Message (
                    'Exchange session looked connected but a ' +
                    "live call failed; forcing reconnect. Error: $_")
                $NeedConnect = $true
            }
        }

        if ($NeedConnect) {
            # Connect the new session first, then disconnect the old one by
            # ConnectionId - this avoids a no-connection window and never touches
            # the IPPS connection.
            $PreIds = @(Get-ConnectionInformation -ErrorAction SilentlyContinue).ConnectionId

            $Params = @{
                AccessToken       = $Token
                UserPrincipalName = $Upn
                ShowBanner        = $false
            }
            $Params['ExchangeEnvironmentName'] = $CloudConfig.ExchangeEnv
            Write-PSFMessage -Level 8 -Message (
                'Calling Connect-ExchangeOnline ' +
                "(ExchangeEnvironmentName: $($CloudConfig.ExchangeEnv)).")
            Connect-ExchangeOnline @Params
            Write-PSFMessage -Level 8 -Message "Connect-ExchangeOnline completed."

            $NewConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -notmatch $IppsUriPattern -and
                    $_.ConnectionId -notin $PreIds
                } | Select-Object -First 1
            $ConnectionId = $NewConnection.ConnectionId

            # Scoped cleanup of the connection we replaced.
            $OldId = $Global:IRT_Session.Exchange?.ConnectionId
            if (-not $OldId -and $ExistingConnection) {
                $OldId = ($ExistingConnection | Select-Object -First 1).ConnectionId
            }
            if ($OldId -and $OldId -ne $ConnectionId -and $OldId -in $PreIds) {
                Write-PSFMessage -Level 8 -Message (
                    "Disconnecting replaced Exchange connection: $OldId")
                $DcParams = @{
                    ConnectionId = $OldId
                    Confirm      = $false
                    ErrorAction  = 'SilentlyContinue'
                }
                Disconnect-ExchangeOnline @DcParams
            }
        } else {
            $Existing = $ExistingConnection | Select-Object -First 1
            $ConnectionId = $Existing.ConnectionId
            # No rebind: the live session still holds the previously-bound token.
            # Report the account it actually authenticated as (exposed by
            # Get-ConnectionInformation), not the freshly-acquired token's account.
            if ($Existing.UserPrincipalName) { $Upn = $Existing.UserPrincipalName }
            Write-IRT "Already connected to Exchange Online for tenant $TenantId." -Level Warn
        }

        # The new token is bound only on the reconnect path; otherwise report the
        # expiry of the token still bound (the prior session record).
        $ReportedExpiry = if ($NeedConnect) {
            $TokenResult.ExpiresOn.UtcDateTime
        } else {
            $Global:IRT_Session.Exchange?.BoundTokenExpiry ??
            $TokenResult.ExpiresOn.UtcDateTime
        }

        $Result = [pscustomobject]@{
            UserPrincipalName = $Upn
            BoundTokenExpiry  = $ReportedExpiry
            ConnectionId      = $ConnectionId
            TenantId          = $TenantId
        }
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTExchange complete. Account: " +
            "$Upn, BoundTokenExpiry: $($Result.BoundTokenExpiry)")
        return $Result
    }
}
