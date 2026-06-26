function Test-IRTConnection {
    <#
    .SYNOPSIS
    Shows which IRT services are connected and to which tenant.

    .DESCRIPTION
    Checks the current Graph and Exchange Online connections and displays
    the connected domain for each. Useful for confirming which tenant you
    are working against before running incident response commands.

    .PARAMETER Quiet
    Returns $true if both Graph and Exchange are connected to the same
    tenant (matched by TenantId), $false otherwise. Suppresses all output.

    .EXAMPLE
    Test-IRTConnection
    Displays connection status for Graph and Exchange.

    .EXAMPLE
    if (-not (Test-IRTConnection -Quiet)) { throw 'Not fully connected.' }
    Silently asserts that both services are connected to the same tenant.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param (
        [switch] $Quiet
    )

    begin {
        Import-IRTModule -Name 'ExchangeOnlineManagement', 'Microsoft.Graph.Authentication'
    }

    process {

        $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
        $GraphTokenValid = $false
        if ($GraphCtx) {
            try {
                $GraphParams = @{
                    Method      = 'GET'
                    # Relative URI so the request follows the current context's cloud
                    # endpoint (e.g. graph.microsoft.us for USGov). An absolute
                    # graph.microsoft.com URL sends the token to the commercial endpoint -
                    # which 401s on sovereign clouds AND latches the SDK base URL to
                    # commercial, breaking every subsequent Graph call in the session.
                    Uri         = 'v1.0/organization?$select=id&$top=1'
                    ErrorAction = 'Stop'
                }
                $null = Invoke-MgGraphRequest @GraphParams
                $GraphTokenValid = $true
            } catch {
                $GraphTokenValid = $false
            }
        }

        $IppsPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'
        $AllExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' }
        $ExoConn = $AllExoConns |
            Where-Object { $_.ConnectionUri -notmatch $IppsPattern } |
            Select-Object -First 1
        $IppsConn = $AllExoConns |
            Where-Object { $_.ConnectionUri -match $IppsPattern } |
            Select-Object -First 1

        # Account is null when Graph is bound via Connect-MgGraph -AccessToken, so
        # it cannot gate "connected" - doing so makes every token-bound Graph
        # session read as disconnected. The live call above already proved the
        # token works; require a context carrying a TenantId (populated in token
        # mode) plus that successful call.
        $GraphConnected = $GraphCtx -and $GraphCtx.TenantId -and $GraphTokenValid
        $ExoConnected = $null -ne $ExoConn
        $IppsConnected = $null -ne $IppsConn

        if ($Quiet) {
            if (-not $GraphConnected -or -not $ExoConnected) {
                return $false
            }
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId = $ExoConn.TenantID
            return ($GraphTenantId -and $ExoTenantId -and
                $GraphTenantId -eq $ExoTenantId)
        }

        # --- Verbose display ---
        # Get-MgContext.Account is null in -AccessToken mode, so the displayed
        # account/domain come from the session's recorded Graph account (the one
        # actually bound), not the SDK context.
        $graphAccount = if ($GraphConnected) {
            $Global:IRT_Session.Graph?.Account
        } else { $null }
        $graphDomain = if ($graphAccount) {
            ($graphAccount -split '@')[-1]
        } else { $null }

        $exoDomain = if ($ExoConnected) {
            ($ExoConn.UserPrincipalName -split '@')[-1]
        } else { $null }

        $ippsDomain = if ($IppsConnected) {
            ($IppsConn.UserPrincipalName -split '@')[-1]
        } else { $null }

        $rows = @(
            [pscustomobject]@{
                Service   = 'Graph'
                Connected = $GraphConnected
                Domain    = if ($graphDomain) { $graphDomain } else { '-' }
                Account   = if ($graphAccount) { $graphAccount } else { '-' }
            }
            [pscustomobject]@{
                Service   = 'Exchange'
                Connected = $ExoConnected
                Domain    = if ($exoDomain) { $exoDomain } else { '-' }
                Account   = if ($ExoConnected) { $ExoConn.UserPrincipalName } else { '-' }
            }
            [pscustomobject]@{
                Service   = 'IPPS'
                Connected = $IppsConnected
                Domain    = if ($ippsDomain) { $ippsDomain } else { '-' }
                Account   = if ($IppsConnected) { $IppsConn.UserPrincipalName } else { '-' }
            }
        )

        $rows | Format-Table -AutoSize

        # warn if both are connected but to different tenants
        if ($GraphConnected -and $ExoConnected) {
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId = $ExoConn.TenantID
            if ($GraphTenantId -and $ExoTenantId -and $GraphTenantId -ne $ExoTenantId) {
                Write-IRT 'Graph and Exchange are connected to different tenants.' -Level Warn
            }
        }
    }
}
