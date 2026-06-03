function Update-IRTToken {
    <#
    .SYNOPSIS
    Checks whether the token for one or more M365 services is expiring soon and refreshes
    if needed. Writes a friendly error if a required service is not connected.

    .DESCRIPTION
    Intended to be called at the start of any domain function that requires a live
    Graph, Exchange, or IPPS connection. For each requested service it reads the
    token expiry stored in $Global:IRT_Session and:

      - Writes an error message and returns if the service is not connected.
      - Calls Connect-IRT -Refresh when the token expires within 5 minutes.
      - Does nothing when the token is healthy.

    The 5-minute window aligns with MSAL's internal silent-refresh threshold so
    that AcquireTokenSilent uses the refresh token and returns genuinely new tokens
    rather than the same near-expired cached access token.

    .PARAMETER Service
    One or more service names to check. Accepts 'Graph', 'Exchange', and 'IPPS'.
    Defaults to all three.

    .PARAMETER SkipIfNeverConnected
    When set, silently skips any service that has no active session rather than
    writing an error. Intended for use in the prompt function, which runs regardless
    of whether the user has called Connect-IRT.

    .PARAMETER PassThru
    When set, returns a hashtable keyed by each requested service name with a boolean
    value indicating whether the token is currently valid (not expired). The status
    reflects the state after any refresh that was performed.

    .EXAMPLE
    Update-IRTToken -Service 'Graph'
    Checks and refreshes the Graph token if it is expiring within 5 minutes.
    Writes an error if the Graph session does not exist.

    .EXAMPLE
    Update-IRTToken -Service 'Graph', 'Exchange'
    Checks both Graph and Exchange tokens and refreshes if either is expiring soon.

    .EXAMPLE
    Update-IRTToken
    Checks all three services (Graph, Exchange, IPPS).

    .OUTPUTS
    System.Collections.Hashtable
    When -PassThru is specified, returns a hashtable keyed by service name (Graph,
    Exchange, IPPS) with boolean values indicating whether each token is currently valid.
    Returns nothing otherwise.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Automatic token-refresh guard; ShouldProcess is not applicable here.')]
    param (
        [ValidateSet('Graph', 'Exchange', 'IPPS')]
        [string[]] $Service = @('Graph', 'Exchange', 'IPPS'),

        [switch] $SkipIfNeverConnected,

        [switch] $PassThru
    )

    Write-PSFMessage -Level 8 -Message (
        "Update-IRTToken: Services=[$($Service -join ', ')], " +
        "SkipIfNeverConnected=$SkipIfNeverConnected")

    if (-not $Global:IRT_Session) {
        Write-PSFMessage -Level 8 -Message 'Update-IRTToken: No session — not connected.'
        if (-not $SkipIfNeverConnected) {
            foreach ($svc in $Service) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
        }
        return
    }

    $needsRefresh = $false
    foreach ($svc in $Service) {
        $svcObj = $Global:IRT_Session.$svc
        if (-not $svcObj -or -not $svcObj.Token -or -not $svcObj.TokenExpiry) {
            Write-PSFMessage -Level 8 -Message "Update-IRTToken: $svc — no token present."
            if (-not $SkipIfNeverConnected) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
            continue
        }
        $MinutesLeft = [int](($svcObj.TokenExpiry - [datetime]::UtcNow).TotalMinutes)
        Write-PSFMessage -Level 8 -Message (
            "Update-IRTToken: $svc — expires $($svcObj.TokenExpiry) UTC " +
            "($MinutesLeft min remaining)")
        if ($MinutesLeft -lt 5) {
            $needsRefresh = $true
        }
    }

    if ($needsRefresh) {
        Write-PSFMessage -Level 8 -Message 'Update-IRTToken: Token expiring soon — triggering refresh.'
        Write-IRT 'Token expiring soon - refreshing...'
        try {
            $null = Connect-IRT -Refresh -ErrorAction Stop
            Write-PSFMessage -Level 8 -Message 'Update-IRTToken: Refresh completed successfully.'
        }
        catch {
            Write-IRT "Token refresh failed: $_" -Level Error
        }
    }
    else {
        Write-PSFMessage -Level 8 -Message 'Update-IRTToken: All tokens healthy — no refresh needed.'
    }

    if ($PassThru) {
        $status = @{}
        foreach ($svc in $Service) {
            $svcObj = $Global:IRT_Session.$svc
            $status[$svc] = [bool](
                $svcObj -and $svcObj.TokenExpiry -and
                ($svcObj.TokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0
            )
        }
        return $status
    }
}
