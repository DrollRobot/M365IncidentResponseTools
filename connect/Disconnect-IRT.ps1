New-Alias -Name 'IRTDisconnect'              -Value 'Disconnect-IRT' -Force
New-Alias -Name 'DisconnectIRT'              -Value 'Disconnect-IRT' -Force

function Disconnect-IRT {
    <#
    .SYNOPSIS
    Disconnects from Microsoft Graph and Exchange Online and cleans up session state.

    .DESCRIPTION
    Disconnects from Graph and Exchange Online, clears all auth-related global variables,
    and restores the original PowerShell prompt.

    .PARAMETER Graph
    Disconnect from Microsoft Graph only.

    .PARAMETER Exchange
    Disconnect from Exchange Online only.

    .PARAMETER IPPS
    Disconnect from Security & Compliance PowerShell (IPPS) only.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [switch] $Graph,
        [switch] $Exchange,
        [switch] $IPPS
    )

    process {

        # if no service switches specified, disconnect from all
        $DisconnectAll = -not ($Graph -or $Exchange -or $IPPS)

        $DisconnectGraph    = $DisconnectAll -or $Graph
        $DisconnectExchange = $DisconnectAll -or $Exchange
        $DisconnectIPPS     = $DisconnectAll -or $IPPS

        # --- Graph ---
        if ($DisconnectGraph) {
            $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
            if ($GraphCtx) {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Write-Host 'Disconnected from Microsoft Graph.' -ForegroundColor Yellow
            }
        }

        # --- Exchange ---
        # Disconnect-ExchangeOnline -ConnectionId allows targeting one session
        # without taking down sibling EXO/IPPS sessions.
        if ($DisconnectExchange) {
            $ExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -notmatch 'compliance\.protection\.(outlook\.com|office365\.us)'
                }
            foreach ($Conn in $ExoConns) {
                Disconnect-ExchangeOnline -ConnectionId $Conn.ConnectionId -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($ExoConns) {
                Write-Host 'Disconnected from Exchange Online.' -ForegroundColor Yellow
            }
        }

        # --- IPPS ---
        if ($DisconnectIPPS) {
            $IppsConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -eq 'Connected' -and
                    $_.ConnectionUri -match 'compliance\.protection\.(outlook\.com|office365\.us)'
                }
            foreach ($Conn in $IppsConns) {
                Disconnect-ExchangeOnline -ConnectionId $Conn.ConnectionId -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($IppsConns) {
                Write-Host 'Disconnected from IPPS (Security & Compliance).' -ForegroundColor Yellow
            }
        }

        # --- Clear session globals ---
        # Only when all services are now disconnected.
        $GraphStillConnected = [bool](Get-MgContext -ErrorAction SilentlyContinue)
        $ExoOrIppsStillConnected = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' })

        if (-not $GraphStillConnected -and -not $ExoOrIppsStillConnected) {
            # Preserve IRT_OriginalPrompt — needed by the module's OnRemove handler to
            # restore the original prompt when Remove-Module is called.
            Get-Variable -Scope Global -Name 'IRT_*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'IRT_OriginalPrompt' } |
                Remove-Variable -Scope Global -ErrorAction SilentlyContinue
        }
    }
}
