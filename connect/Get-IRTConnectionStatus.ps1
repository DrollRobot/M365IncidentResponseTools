function Get-IRTConnectionStatus {
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
    Get-IRTConnectionStatus
    Displays connection status for Graph and Exchange.

    .EXAMPLE
    if (-not (Get-IRTConnectionStatus -Quiet)) { throw 'Not fully connected.' }
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
        $ExoConns  = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                         Where-Object { $_.State -eq 'Connected' }
        $ExoConn   = $ExoConns | Select-Object -First 1

        $GraphConnected = $GraphCtx -and $GraphCtx.Account
        $ExoConnected   = $null -ne $ExoConn

        if ($Quiet) {
            if (-not $GraphConnected -or -not $ExoConnected) {
                return $false
            }
            # Compare by TenantId so multi-domain tenants still match correctly
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId   = $ExoConn.TenantID          # GUID string
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

        $rows = @(
            [pscustomobject]@{
                Service   = 'Graph'
                Connected = $GraphConnected
                Domain    = if ($graphDomain) { $graphDomain } else { '—' }
                Account   = if ($GraphConnected) { $GraphCtx.Account } else { '—' }
            }
            [pscustomobject]@{
                Service   = 'Exchange'
                Connected = $ExoConnected
                Domain    = if ($exoDomain) { $exoDomain } else { '—' }
                Account   = if ($ExoConnected) { $ExoConn.UserPrincipalName } else { '—' }
            }
        )

        $rows | Format-Table -AutoSize

        # Warn if both are connected but to different tenants
        if ($GraphConnected -and $ExoConnected) {
            $GraphTenantId = $GraphCtx.TenantId
            $ExoTenantId   = $ExoConn.TenantID
            if ($GraphTenantId -and $ExoTenantId -and $GraphTenantId -ne $ExoTenantId) {
                Write-Warning 'Graph and Exchange are connected to different tenants.'
            }
        }
    }
}
