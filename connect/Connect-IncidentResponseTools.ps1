function Connect-IncidentResponseTools {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph and Exchange Online for incident response.

    .DESCRIPTION
    Orchestrates connections to Graph and Exchange Online.
    When no service switches are specified, both services are connected. Use -Graph
    or -Exchange to connect to specific services only.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER GCCHigh
    Connect to a GCC High tenant environment.

    .PARAMETER DeviceCode
    Use device code authentication flow instead of interactive browser auth.

    .PARAMETER AdditionalScopes
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER Browser
    Browser to use for device code login and URL opening. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .EXAMPLE
    Connect-IncidentResponseTools -TenantId $tid
    Connects to Graph and Exchange Online.

    .EXAMPLE
    Connect-IncidentResponseTools -TenantId $tid -Graph -DeviceCode
    Connects to Graph only using device code auth.

    .EXAMPLE
    Connect-IncidentResponseTools -TenantId $tid -Exchange -GCCHigh
    Connects to Exchange in a GCC High environment.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [string] $TenantId,
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [string[]] $AdditionalScopes,

        [switch] $Graph,
        [switch] $Exchange,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force
    )

    process {

        # if no service switches specified, connect to both
        $ConnectAll = -not ($Graph -or $Exchange)
        $ConnectGraph    = $ConnectAll -or $Graph
        $ConnectExchange = $ConnectAll -or $Exchange

        # --- Initialize session global before attempting connections ---
        if ($Global:IRT_Session -and $Global:IRT_Session.TenantId -ne $TenantId) {
            Write-Warning "TenantId mismatch (current: $($Global:IRT_Session.TenantId)). Disconnecting existing session."
            Disconnect-IncidentResponseTools
        }

        if (-not $Global:IRT_Session) {
            $Global:IRT_Session = [pscustomobject]@{
                TenantId = $TenantId
                Graph    = $null
                Exchange = $null
            }
        }

        # --- Graph ---
        if ($ConnectGraph) {

            $GraphParams = @{
                TenantId = $TenantId
            }
            if ($GCCHigh)          { $GraphParams['GCCHigh']            = $true }
            if ($DeviceCode)       { $GraphParams['DeviceCode']         = $true }
            if ($Force)            { $GraphParams['Force']              = $true }
            $GraphParams['Browser'] = $Browser
            if ($Private) { $GraphParams['Private'] = $true }
            if ($AdditionalScopes) {
                $GraphParams['AdditionalScopes'] = $AdditionalScopes
            }

            $GraphConnection = Connect-IRTGraph @GraphParams
            if ($GraphConnection) { $Global:IRT_Session.Graph = $GraphConnection }
        }

        # --- Exchange Online ---
        if ($ConnectExchange) {

            $ExchangeParams = @{
                TenantId          = $TenantId
            }
            if ($GCCHigh)    { $ExchangeParams['GCCHigh']    = $true }
            if ($DeviceCode) { $ExchangeParams['DeviceCode'] = $true }
            if ($Force)      { $ExchangeParams['Force']      = $true }
            $ExchangeParams['Browser'] = $Browser
            if ($Private) { $ExchangeParams['Private'] = $true }

            $ExchangeConnection = Connect-IRTExchange @ExchangeParams
            if ($ExchangeConnection) { $Global:IRT_Session.Exchange = $ExchangeConnection }
        }

        # display status if at least one connection succeeded
        if ($Global:IRT_Session.Graph -or $Global:IRT_Session.Exchange) {
            Get-IRTConnectionStatus
        }
    }
}