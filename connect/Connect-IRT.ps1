function Connect-IRT {
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

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER Browser
    Browser to use for device code login and URL opening. Valid values: msedge, chrome, firefox,
    brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .EXAMPLE
    Connect-IRT -TenantId $tid
    Connects to Graph and Exchange Online.

    .EXAMPLE
    Connect-IRT -TenantId $tid -Graph -DeviceCode
    Connects to Graph only using device code auth.

    .EXAMPLE
    Connect-IRT -TenantId $tid -Exchange -GCCHigh
    Connects to Exchange in a GCC High environment.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ConnectIRT')]
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [string] $TenantId,
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [Alias('AdditionalScopes')]
        [string[]] $AdditionalScope,

        [switch] $Graph,
        [switch] $Exchange,
        [switch] $IPPS,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force
    )

    process {

        # if no service switches specified, connect to all
        $ConnectAll      = -not ($Graph -or $Exchange -or $IPPS)
        $ConnectGraph    = $ConnectAll -or $Graph
        $ConnectExchange = $ConnectAll -or $Exchange
        $ConnectIPPS     = $ConnectAll -or $IPPS

        # --- Initialize session global before attempting connections ---
        if ($Global:IRT_Session -and $Global:IRT_Session.TenantId -ne $TenantId) {
            $OldTenant = $Global:IRT_Session.TenantId
            Write-Warning "TenantId mismatch (current: $OldTenant). Disconnecting existing session."
            Disconnect-IRT
        }

        if (-not $Global:IRT_Session) {
            $Global:IRT_Session = [pscustomobject]@{
                TenantId = $TenantId
                GCCHigh  = [bool]$GCCHigh
                Graph    = $null
                Exchange = $null
                IPPS     = $null
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
            if ($AdditionalScope) {
                $GraphParams['AdditionalScope'] = $AdditionalScope
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

        # --- IPPS ---
        if ($ConnectIPPS) {
            $IPPSParams = @{ TenantId = $TenantId }
            if ($GCCHigh)    { $IPPSParams['GCCHigh']    = $true }
            if ($DeviceCode) { $IPPSParams['DeviceCode'] = $true }
            if ($Force)      { $IPPSParams['Force']      = $true }
            $IPPSParams['Browser'] = $Browser
            if ($Private)    { $IPPSParams['Private']    = $true }

            $IPPSConnection = Connect-IRTIPPS @IPPSParams
            if ($IPPSConnection) { $Global:IRT_Session.IPPS = $IPPSConnection }
        }

        # display status if at least one connection succeeded
        if ($Global:IRT_Session.Graph -or
            $Global:IRT_Session.Exchange -or
            $Global:IRT_Session.IPPS
        ) {
            Test-IRTConnection
        }
    }
}

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

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $true }

        # Base64url decode the payload segment (second part of the JWT)
        $payload = $parts[1]
        $padded  = $payload.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '='  }
        }

        $bytes  = [System.Convert]::FromBase64String($padded)
        $json   = [System.Text.Encoding]::UTF8.GetString($bytes)
        $claims = $json | ConvertFrom-Json

        if (-not $claims.exp) { return $true }

        $expiry    = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
        $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)

        return $expiry -le $threshold
    }
    catch {
        # If the token cannot be decoded, treat it as expired to force re-acquisition
        return $true
    }
}
