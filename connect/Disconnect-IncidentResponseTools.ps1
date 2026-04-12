New-Alias -Name 'IRTDisconnect'  -Value 'Disconnect-IncidentResponseTools' -Force
New-Alias -Name 'DisconnectIRT'   -Value 'Disconnect-IncidentResponseTools' -Force
New-Alias -Name 'Disconnect-IRT'  -Value 'Disconnect-IncidentResponseTools' -Force
New-Alias -Name 'DisconnectIncidentResponseTools'  -Value 'Disconnect-IncidentResponseTools' -Force

function Disconnect-IncidentResponseTools {
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

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [switch] $Graph,

        [switch] $Exchange
    )

    process {

        # if no service switches specified, disconnect from both
        $DisconnectAll = -not ($Graph -or $Exchange)

        $DisconnectGraph    = $DisconnectAll -or $Graph
        $DisconnectExchange = $DisconnectAll -or $Exchange

        # --- Graph ---
        if ($DisconnectGraph) {
            $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
            if ($GraphCtx) {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Write-Host 'Disconnected from Microsoft Graph.' -ForegroundColor Yellow
            }
        }

        # --- Exchange ---
        if ($DisconnectExchange) {
            $ExoConn = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Connected' }
            if ($ExoConn) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host 'Disconnected from Exchange Online.' -ForegroundColor Yellow
            }
        }

        # --- Clear session globals ---
        # Only when both services are now disconnected.
        $GraphStillConnected = [bool](Get-MgContext -ErrorAction SilentlyContinue)
        $ExoStillConnected   = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' })

        if (-not $GraphStillConnected -and -not $ExoStillConnected) {
            # Preserve IRT_OriginalPrompt — needed by the module's OnRemove handler to
            # restore the original prompt when Remove-Module is called.
            Get-Variable -Scope Global -Name 'IRT_*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'IRT_OriginalPrompt' } |
                Remove-Variable -Scope Global -ErrorAction SilentlyContinue
        }
    }
}
