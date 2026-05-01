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
    [CmdletBinding()]
    param (
        [switch] $Quiet
    )

    process {

        $GraphCtx  = Get-MgContext -ErrorAction SilentlyContinue
        $AllExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                         Where-Object { $_.State -eq 'Connected' }
        $ExoConn   = $AllExoConns |
            Where-Object { $_.ConnectionUri -notmatch 'compliance\.protection\.(outlook\.com|office365\.us)' } |
            Select-Object -First 1
        $IppsConn  = $AllExoConns |
            Where-Object { $_.ConnectionUri -match 'compliance\.protection\.(outlook\.com|office365\.us)' } |
            Select-Object -First 1

        $GraphConnected = $GraphCtx -and $GraphCtx.Account
        $ExoConnected   = $null -ne $ExoConn
        $IppsConnected  = $null -ne $IppsConn

        if ($Quiet) {
            if (-not $GraphConnected -or -not $ExoConnected) {
                return $false
            }
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId   = $ExoConn.TenantID
            return ($GraphTenantId -and $ExoTenantId -and
                    $GraphTenantId -eq $ExoTenantId)
        }

        # --- Verbose display ---
        $graphDomain = if ($GraphConnected) {
            ($GraphCtx.Account -split '@')[-1]
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
                Account   = if ($GraphConnected) { $GraphCtx.Account } else { '-' }
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
            $ExoTenantId   = $ExoConn.TenantID
            if ($GraphTenantId -and $ExoTenantId -and $GraphTenantId -ne $ExoTenantId) {
                Write-Warning 'Graph and Exchange are connected to different tenants.'
            }
        }
    }
}
