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
                Cloud    = $Global:IRT_Session.Cloud
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
        $DetectedCloud = $Cloud
        if (-not $Cloud) {
            $Oidc = Get-IRTTenantOidc -TenantId $TenantId
            if ($Oidc) {
                $DetectedCloud = $Oidc.Cloud
            } else {
                # Don't guess - a wrong cloud produces cross-cloud tokens that fail at the
                # API. Make the user specify rather than silently defaulting to Commercial.
                throw ('OIDC discovery could not determine the cloud for this tenant. ' +
                    'Re-run Connect-IRT with an explicit -Cloud ' +
                    '(Commercial, USGov, USGovDoD, or China).')
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
                ClientId    = $ClientId
                Cloud       = $DetectedCloud
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
            $GraphParams['Cloud'] = $DetectedCloud
            if ($Force) { $GraphParams['Force'] = $true }
            $GraphParams['Browser'] = $Browser
            if ($Private) { $GraphParams['Private'] = $true }
            if ($AdditionalScope) {
                $GraphParams['AdditionalScope'] = $AdditionalScope
            }
            if ($Silent) { $GraphParams['Silent'] = $true }
            if ($ClientId) { $GraphParams['ClientId'] = $ClientId }

            $GraphConnection = Connect-IRTGraph @GraphParams
            if ($GraphConnection) {
                $Global:IRT_Session.Graph = $GraphConnection
            } else {
                Write-IRT 'Failed to connect to Microsoft Graph.' -Level Error
            }
        }

        # --- Exchange Online ---
        if ($ConnectExchange) {

            $ExchangeParams = @{
                TenantId          = $TenantId
            }
            $ExchangeParams['Cloud'] = $DetectedCloud
            if ($Force) { $ExchangeParams['Force'] = $true }
            if ($Silent) { $ExchangeParams['Silent'] = $true }
            if ($ClientId) { $ExchangeParams['ClientId'] = $ClientId }

            $ExchangeConnection = Connect-IRTExchange @ExchangeParams
            if ($ExchangeConnection) {
                $Global:IRT_Session.Exchange = $ExchangeConnection
            } else {
                Write-IRT 'Failed to connect to Exchange Online.' -Level Error
            }
        }

        # --- IPPS ---
        if ($ConnectIPPS) {
            $IPPSParams = @{ TenantId = $TenantId }
            $IPPSParams['Cloud'] = $DetectedCloud
            if ($Force) { $IPPSParams['Force'] = $true }
            if ($Silent) { $IPPSParams['Silent'] = $true }
            if ($ClientId) { $IPPSParams['ClientId'] = $ClientId }

            $IPPSConnection = Connect-IRTIPPS @IPPSParams
            if ($IPPSConnection) {
                $Global:IRT_Session.IPPS = $IPPSConnection
            } else {
                Write-IRT 'Failed to connect to IPPS.' -Level Error
            }
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
