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

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
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
            if ($Silent)                        { $RefreshParams['Silent']   = $true }
            if ($Global:IRT_Session.ClientId) {
                $RefreshParams['ClientId'] = $Global:IRT_Session.ClientId
            }
            if ($Global:IRT_Session.Graph)      { $RefreshParams['Graph']    = $true }
            if ($Global:IRT_Session.Exchange) { $RefreshParams['Exchange'] = $true }
            if ($Global:IRT_Session.IPPS)     { $RefreshParams['IPPS']     = $true }
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
        $ConnectAll      = -not ($Graph -or $Exchange -or $IPPS)
        $ConnectGraph    = $ConnectAll -or $Graph
        $ConnectExchange = $ConnectAll -or $Exchange
        $ConnectIPPS     = $ConnectAll -or $IPPS

        # --- Resolve cloud ---
        # Use the OIDC lookup when -Cloud is not specified.
        $DetectedEnvironment = $Cloud
        if (-not $Cloud) {
            $Oidc = Invoke-TenantOIDCLookup -TenantId $TenantId
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
            if ($Force)            { $GraphParams['Force']              = $true }
            $GraphParams['Browser'] = $Browser
            if ($Private) { $GraphParams['Private'] = $true }
            if ($AdditionalScope) {
                $GraphParams['AdditionalScope'] = $AdditionalScope
            }
            if ($Silent)   { $GraphParams['Silent']   = $true }
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
            if ($Force)      { $ExchangeParams['Force']      = $true }
            $ExchangeParams['Browser'] = $Browser
            if ($Private) { $ExchangeParams['Private'] = $true }
            if ($Silent)   { $ExchangeParams['Silent']   = $true }
            if ($ClientId) { $ExchangeParams['ClientId'] = $ClientId }

            $ExchangeConnection = Connect-IRTExchange @ExchangeParams
            if ($ExchangeConnection) { $Global:IRT_Session.Exchange = $ExchangeConnection }
        }

        # --- IPPS ---
        if ($ConnectIPPS) {
            $IPPSParams = @{ TenantId = $TenantId }
            $IPPSParams['Cloud'] = $DetectedEnvironment
            if ($Force)      { $IPPSParams['Force']      = $true }
            $IPPSParams['Browser'] = $Browser
            if ($Private)    { $IPPSParams['Private']    = $true }
            if ($Silent)     { $IPPSParams['Silent']     = $true }
            if ($ClientId)   { $IPPSParams['ClientId']   = $ClientId }

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

function Get-IRTTokenExpiry {
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
        $padded  = $payload.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '='  }
        }

        $bytes  = [System.Convert]::FromBase64String($padded)
        $json   = [System.Text.Encoding]::UTF8.GetString($bytes)
        $claims = $json | ConvertFrom-Json

        if (-not $claims.exp) { return $null }

        return [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
    }
    catch {
        return $null
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

    $expiry = Get-IRTTokenExpiry -Token $Token
    if ($null -eq $expiry) { return $true }

    $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)
    return $expiry -le $threshold
}
