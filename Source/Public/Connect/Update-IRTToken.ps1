function Update-IRTToken {
    <#
    .SYNOPSIS
    Checks whether the token for one or more M365 services is expiring soon and refreshes
    if needed. Writes a friendly error if a required service is not connected.

    .DESCRIPTION
    Intended to be called at the start of any domain function that requires a live
    Graph, Exchange, or IPPS connection (and inside long-running loops). For each
    requested service it reads the bound-token expiry stored in $Global:IRT_Session
    and:

      - Writes an error message and returns if the service is not connected.
      - Re-binds ONLY that service (via its private connector) when the token bound
        into the SDK context expires within 5 minutes. Exchange/IPPS re-binds are
        scoped by ConnectionId, so refreshing one service never tears down another.
      - Does nothing when the bound token is healthy.

    Inside playbook runspace workers ($Global:IRT_IsRunspaceWorker) behavior differs:
    Graph is a no-op (the parent keeps the process-wide Graph binding fresh), and
    Exchange delegates to Connect-IRTRunspaceExchange, which maintains a
    runspace-local connection minted silently from the shared MSAL cache.

    The 5-minute window aligns with MSAL's internal silent-refresh threshold so
    that AcquireTokenSilent uses the refresh token and returns genuinely new tokens
    rather than the same near-expired cached access token.

    .PARAMETER Service
    One or more service names to check. Accepts 'Graph', 'Exchange', and 'IPPS'.
    Defaults to all three.

    .PARAMETER SkipIfNeverConnected
    When set, silently skips any service that has no active session rather than
    writing an error. Intended for callers that run regardless of whether the user
    has called Connect-IRT.

    .PARAMETER PassThru
    When set, returns a hashtable keyed by each requested service name with a boolean
    value indicating whether the bound token is currently valid (not expired). The
    status reflects the state after any refresh that was performed.

    .EXAMPLE
    Update-IRTToken -Service 'Graph'
    Checks and re-binds the Graph token if it is expiring within 5 minutes.
    Writes an error if the Graph session does not exist.

    .EXAMPLE
    Update-IRTToken -Service 'Graph', 'Exchange'
    Checks both Graph and Exchange tokens and refreshes whichever is expiring soon.

    .EXAMPLE
    Update-IRTToken
    Checks all three services (Graph, Exchange, IPPS).

    .OUTPUTS
    System.Collections.Hashtable
    When -PassThru is specified, returns a hashtable keyed by service name (Graph,
    Exchange, IPPS) with boolean values indicating whether each token is currently valid.
    Returns nothing otherwise.

    .NOTES
    Version: 2.0.0
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

    Import-IRTModule -Name 'PSFramework'

    Write-PSFMessage -Level 8 -Message (
        "Update-IRTToken: Services=[$($Service -join ', ')], " +
        "SkipIfNeverConnected=$SkipIfNeverConnected, " +
        "Worker=$([bool]$Global:IRT_IsRunspaceWorker)")

    if (-not $Global:IRT_Session) {
        Write-PSFMessage -Level 8 -Message 'Update-IRTToken: No session - not connected.'
        if (-not $SkipIfNeverConnected) {
            foreach ($svc in $Service) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
        }
        return
    }

    # ---------- Runspace worker path ----------
    # Workers never re-bind shared session state: Graph is process-wide and kept
    # fresh by the parent's wait loop; Exchange uses a runspace-local connection.
    if ($Global:IRT_IsRunspaceWorker) {
        foreach ($svc in $Service) {
            switch ($svc) {
                'Graph' {
                    Write-PSFMessage -Level 8 -Message (
                        'Update-IRTToken: worker - Graph binding is ' +
                        'maintained by the parent; no-op.')
                }
                'Exchange' {
                    $ExpiresAt = $Global:IRT_RunspaceExo.BoundTokenExpiry
                    $MinutesLeft = if ($ExpiresAt) {
                        [int](($ExpiresAt - [datetime]::UtcNow).TotalMinutes)
                    } else {
                        -1
                    }
                    Write-PSFMessage -Level 8 -Message (
                        "Update-IRTToken: worker Exchange - $MinutesLeft min remaining.")
                    if ($MinutesLeft -lt 5) {
                        try {
                            Connect-IRTRunspaceExchange -ErrorAction Stop
                        } catch {
                            Write-IRT "Token refresh failed: $_" -Level Error
                        }
                    }
                }
                'IPPS' {
                    Write-PSFMessage -Level 8 -Message (
                        'Update-IRTToken: worker - IPPS refresh is not ' +
                        'supported inside runspaces; skipping.')
                }
            }
        }

        if ($PassThru) {
            $status = @{}
            foreach ($svc in $Service) {
                $ExpiresAt = if ($svc -eq 'Exchange') {
                    $Global:IRT_RunspaceExo.BoundTokenExpiry
                } else {
                    $Global:IRT_Session.$svc.BoundTokenExpiry
                }
                $status[$svc] = [bool](
                    $ExpiresAt -and
                    ($ExpiresAt - [datetime]::UtcNow).TotalMinutes -gt 0
                )
            }
            return $status
        }
        return
    }

    # ---------- Parent path: per-service scoped refresh ----------
    foreach ($svc in $Service) {
        $svcObj = $Global:IRT_Session.$svc
        if (-not $svcObj -or -not $svcObj.BoundTokenExpiry) {
            Write-PSFMessage -Level 8 -Message "Update-IRTToken: $svc - no token present."
            if (-not $SkipIfNeverConnected) {
                Write-IRT "Not connected to $svc. Run Connect-IRT first." -Level Error
            }
            continue
        }
        $MinutesLeft = [int](($svcObj.BoundTokenExpiry - [datetime]::UtcNow).TotalMinutes)
        Write-PSFMessage -Level 8 -Message (
            "Update-IRTToken: $svc - expires $($svcObj.BoundTokenExpiry) UTC " +
            "($MinutesLeft min remaining)")
        if ($MinutesLeft -ge 5) {
            continue
        }

        Write-PSFMessage -Level 8 -Message (
            "Update-IRTToken: $svc token expiring soon - refreshing.")
        Write-IRT "$svc token expiring soon - refreshing..."

        $ConnectParams = @{
            TenantId    = $Global:IRT_Session.TenantId
            Cloud       = $Global:IRT_Session.Cloud
            Force       = $true
            ErrorAction = 'Stop'
        }
        if ($Global:IRT_Session.ClientId) {
            $ConnectParams['ClientId'] = $Global:IRT_Session.ClientId
        }

        try {
            $Fresh = switch ($svc) {
                'Graph' {
                    # Re-request any extra scopes granted in this session.
                    $ScopeDelta = @($svcObj.Scopes |
                            Where-Object { $_ -notin (Get-IRTGraphDefaultScope) })
                    if ($ScopeDelta) { $ConnectParams['AdditionalScope'] = $ScopeDelta }
                    Connect-IRTGraph @ConnectParams
                }
                'Exchange' {
                    Connect-IRTExchange @ConnectParams
                }
                'IPPS' {
                    $ConnectParams['SearchOnly'] = [bool]$svcObj.SearchOnly
                    Connect-IRTIPPS @ConnectParams
                }
            }
            # Only replace the slot when the connector returned metadata - never
            # wipe a service slot because of an empty return.
            if ($Fresh) {
                $Global:IRT_Session.$svc = $Fresh | Select-Object -Last 1
            }
            Write-PSFMessage -Level 8 -Message (
                "Update-IRTToken: $svc refresh completed successfully.")
        }
        catch {
            Write-IRT "Token refresh failed: $_" -Level Error
        }
    }

    if ($PassThru) {
        $status = @{}
        foreach ($svc in $Service) {
            $svcObj = $Global:IRT_Session.$svc
            $status[$svc] = [bool](
                $svcObj -and $svcObj.BoundTokenExpiry -and
                ($svcObj.BoundTokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0
            )
        }
        return $status
    }
}
