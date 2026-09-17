function Connect-IRTRunspaceExchange {
    <#
    .SYNOPSIS
    Establishes (or refreshes) a runspace-local Exchange Online connection.

    .DESCRIPTION
    Intended for playbook runspace workers. Mints a fresh Exchange token
    silently from the shared MSAL cache (the parent session's
    PublicClientApplication is injected via $Global:IRT_Session and is
    thread-safe) and binds it with Connect-ExchangeOnline. The resulting
    ConnectionId and token expiry are tracked in the runspace-local
    $Global:IRT_RunspaceExo, so repeated calls are cheap no-ops until the
    bound token nears expiry.

    This function never prompts: token acquisition is always silent. If the
    refresh token has been revoked mid-playbook, it throws with instructions
    to re-run Connect-IRT rather than popping a hidden browser window inside
    a worker.

    Safe to call in the parent session too, but the parent normally uses
    Connect-IRT / Update-IRTToken instead.

    .EXAMPLE
    ```powershell
    Connect-IRTRunspaceExchange
    ```
    Inside a playbook step: ensures this runspace has a live Exchange
    connection with a fresh token.

    .OUTPUTS
    None.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param ()

    # import modules
    $Imports = @(
        'ExchangeOnlineManagement'
        'Microsoft.Graph.Authentication'
        'PSFramework'
    )
    Import-IRTModule -Name $Imports

    if (-not $Global:IRT_Session -or -not $Global:IRT_Session.CloudConfig) {
        throw 'No active IRT session. Run Connect-IRT in the parent session first.'
    }
    $TenantId = $Global:IRT_Session.TenantId

    # IPPS connections show up in Get-ConnectionInformation alongside EXO.
    $IppsUriPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'

    # Fast path: this runspace already has a live connection with a fresh token.
    $Existing = $Global:IRT_RunspaceExo
    if ($Existing.ConnectionId -and $Existing.BoundTokenExpiry) {
        $MinutesLeft = [int](($Existing.BoundTokenExpiry - [datetime]::UtcNow).TotalMinutes)
        $GciParams = @{
            ConnectionId = $Existing.ConnectionId
            ErrorAction  = 'SilentlyContinue'
        }
        $Conn = Get-ConnectionInformation @GciParams
        if ($Conn.State -eq 'Connected' -and
            $Conn.TenantID -eq $TenantId -and
            $MinutesLeft -ge 5) {
            Write-PSFMessage -Level 8 -Message (
                'Connect-IRTRunspaceExchange: existing runspace connection healthy ' +
                "($MinutesLeft min remaining); no-op.")
            return
        }
        Write-PSFMessage -Level 8 -Message (
            'Connect-IRTRunspaceExchange: runspace connection stale or dead ' +
            "(state: $($Conn.State), $MinutesLeft min remaining); reconnecting.")
    }

    # Mint silently from the shared MSAL cache - never prompts inside a worker.
    $TokenResult = Get-IRTAccessToken -Service Exchange -Silent
    if (-not $TokenResult.AccessToken) {
        throw ('Failed to silently acquire an Exchange token for this runspace. ' +
            'Re-run Connect-IRT in the parent session, then restart the playbook.')
    }

    $PreIds = @(Get-ConnectionInformation -ErrorAction SilentlyContinue).ConnectionId

    $Params = @{
        AccessToken       = $TokenResult.AccessToken
        UserPrincipalName = $TokenResult.Account.Username
        ShowBanner        = $false
    }
    $Params['ExchangeEnvironmentName'] = $Global:IRT_Session.CloudConfig.ExchangeEnv
    Write-PSFMessage -Level 8 -Message (
        'Connect-IRTRunspaceExchange: calling Connect-ExchangeOnline ' +
        "(account: $($TokenResult.Account.Username)).")
    Connect-ExchangeOnline @Params

    $NewConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object {
            $_.State -eq 'Connected' -and
            $_.ConnectionUri -notmatch $IppsUriPattern -and
            $_.ConnectionId -notin $PreIds
        } | Select-Object -First 1

    # Scoped cleanup of the connection this runspace replaced.
    $OldId = $Existing.ConnectionId
    if ($OldId -and $OldId -ne $NewConnection.ConnectionId -and $OldId -in $PreIds) {
        Write-PSFMessage -Level 8 -Message (
            "Connect-IRTRunspaceExchange: disconnecting replaced connection: $OldId")
        $DcParams = @{
            ConnectionId = $OldId
            Confirm      = $false
            ErrorAction  = 'SilentlyContinue'
        }
        Disconnect-ExchangeOnline @DcParams
    }

    # Runspace-local tracking (plain global; intentionally NOT shared between runspaces).
    $Global:IRT_RunspaceExo = @{
        ConnectionId     = $NewConnection.ConnectionId
        BoundTokenExpiry = $TokenResult.ExpiresOn.UtcDateTime
    }
    Write-PSFMessage -Level 8 -Message (
        'Connect-IRTRunspaceExchange: connected. ' +
        "ConnectionId: $($NewConnection.ConnectionId), " +
        "BoundTokenExpiry: $($TokenResult.ExpiresOn.UtcDateTime)")
}
