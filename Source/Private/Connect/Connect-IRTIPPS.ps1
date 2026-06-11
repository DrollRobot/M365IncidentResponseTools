function Connect-IRTIPPS {
    <#
    .SYNOPSIS
    Connects to Security & Compliance PowerShell (IPPS).

    .DESCRIPTION
    Acquires a portable access token via Get-IRTAccessToken using EXO's
    first-party client ID and the IPPS audience, then passes it to
    Connect-IPPSSession via -AccessToken. This bypasses IPPS's internal MSAL
    token-acquisition path, which fails with an assembly version mismatch when
    the Microsoft.Graph.Authentication MSAL has been pre-loaded.

    Because Exchange and IPPS share one client ID, they share one MSAL app and
    token cache - after any Exchange sign-in, the IPPS token is always minted
    silently (the refresh token is redeemed for the IPPS audience without a
    prompt). Reconnects are scoped by ConnectionId and never tear down the
    Exchange connection.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER Cloud
    Cloud to connect to. Valid values: Commercial, USGov, USGovDoD, China.
    Mandatory - Connect-IRT resolves this via OIDC discovery and passes it in.

    .PARAMETER SearchOnly
    Use the search-only audience (https://dataservice.o365filtering.com) and
    pass -EnableSearchOnlySession to Connect-IPPSSession. Required for newer
    eDiscovery and retention cmdlets (New-ComplianceSearchAction,
    Set-RetentionCompliancePolicy, etc.). Defaults to $true.

    .PARAMETER Force
    Reconnect even when an apparently-healthy connection already exists.

    .PARAMETER Silent
    Never prompt. Token acquisition throws instead of opening a browser when no
    cached account works.

    .PARAMETER ClientId
    Override the MSAL client ID. Defaults to the EXO/IPPS first-party app
    (fb78d390-0c51-40cd-8e17-fdbfab77341b).

    .EXAMPLE
    Connect-IRTIPPS -TenantId $Tid -Cloud Commercial

    .OUTPUTS
    [pscustomobject] - IPPS session metadata: UserPrincipalName,
    BoundTokenExpiry (expiry of the token bound into the SDK connection),
    ConnectionId, SearchOnly, TenantId.

    .NOTES
    Version: 3.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [Parameter(Mandatory)]
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,

        [bool]   $SearchOnly = $true,

        [switch] $Force,
        [switch] $Silent,

        [string] $ClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO/IPPS first-party app
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

        # IPPS connections show up in Get-ConnectionInformation alongside EXO.
        # Distinguish by ConnectionUri matching the compliance endpoint - which differs
        # per cloud (outlook.com commercial, office365.us for USGov/DoD), so match both.
        $IppsUriPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'

        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTIPPS: TenantId=$TenantId, Cloud=$Cloud, " +
            "SearchOnly=$SearchOnly, Force=$Force, Silent=$Silent")
    }

    process {

        # ---------- Phase 1: token ----------
        # Get-IRTAccessToken mints from the MSAL cache. Exchange and IPPS share a
        # client ID, so after any Exchange auth this is always a silent audience
        # swap - no prompt.
        #
        # Note: there is no Phase 1b cloud (aud) validation here as in Graph/Exchange.
        # The search-only audience (dataservice.o365filtering.com) is identical across
        # all clouds, so aud can't distinguish cloud. Cloud-correctness is enforced by
        # the environment-filtered account selection in Get-IRTAccessToken instead.

        $TokenParams = @{
            Service    = 'IPPS'
            SearchOnly = $SearchOnly
            Silent     = $Silent
            ClientId   = $ClientId
        }
        $TokenResult = Get-IRTAccessToken @TokenParams
        if (-not $TokenResult.AccessToken) {
            throw 'Failed to acquire IPPS access token.'
        }
        $Token = $TokenResult.AccessToken
        $Upn = $TokenResult.Account.Username
        Write-PSFMessage -Level 8 -Message "IPPS token acquired for account: $Upn"

        # ---------- Phase 2: Connect-IPPSSession ----------
        # Connect if no existing IPPS connection for this tenant, the SearchOnly mode
        # changed (a token issued for the search-only audience won't authenticate
        # against the full audience and vice versa), the bound token is stale, MSAL
        # handed us a newer token than the bound one, or -Force.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Connected' -and
                $_.TenantID -eq $TenantId -and
                $_.ConnectionUri -match $IppsUriPattern
            }

        $BoundTokenExpiry = $Global:IRT_Session.IPPS?.BoundTokenExpiry ??
        [datetime]::MinValue
        $NeedConnect = $Force -or
        (-not $ExistingConnection) -or
        ($Global:IRT_Session.IPPS?.SearchOnly -ne $SearchOnly) -or
        ($BoundTokenExpiry -lt [datetime]::UtcNow.AddMinutes(5)) -or
        ($TokenResult.ExpiresOn.UtcDateTime -gt $BoundTokenExpiry)

        Write-PSFMessage -Level 8 -Message "NeedConnect: $NeedConnect"

        if ($NeedConnect) {
            # Connect the new session first, then disconnect the old one by
            # ConnectionId - this avoids a no-connection window and never touches
            # the Exchange connection.
            $PreIds = @(Get-ConnectionInformation -ErrorAction SilentlyContinue).ConnectionId

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

            $NewConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -match $IppsUriPattern -and
                    $_.ConnectionId -notin $PreIds
                } | Select-Object -First 1
            $ConnectionId = $NewConnection.ConnectionId

            # Scoped cleanup of the connection we replaced.
            $OldId = $Global:IRT_Session.IPPS?.ConnectionId
            if (-not $OldId -and $ExistingConnection) {
                $OldId = ($ExistingConnection | Select-Object -First 1).ConnectionId
            }
            if ($OldId -and $OldId -ne $ConnectionId -and $OldId -in $PreIds) {
                Write-PSFMessage -Level 8 -Message (
                    "Disconnecting replaced IPPS connection: $OldId")
                $DcParams = @{
                    ConnectionId = $OldId
                    Confirm      = $false
                    ErrorAction  = 'SilentlyContinue'
                }
                Disconnect-ExchangeOnline @DcParams
            }
        } else {
            $ConnectionId = ($ExistingConnection | Select-Object -First 1).ConnectionId
            Write-IRT "Already connected to IPPS for tenant $TenantId." -Level Warn
        }

        $Result = [pscustomobject]@{
            UserPrincipalName = $Upn
            BoundTokenExpiry  = $TokenResult.ExpiresOn.UtcDateTime
            ConnectionId      = $ConnectionId
            SearchOnly        = [bool]$SearchOnly
            TenantId          = $TenantId
        }
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTIPPS complete. Account: $Upn, " +
            "BoundTokenExpiry: $($Result.BoundTokenExpiry)")
        return $Result
    }
}
