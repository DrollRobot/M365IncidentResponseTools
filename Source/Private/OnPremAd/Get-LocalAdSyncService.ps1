function Get-LocalAdSyncService {
    <#
    .SYNOPSIS
    Returns the ADSync service when it runs on this device, or nothing.

    .DESCRIPTION
    Internal helper. The ADSync service (Microsoft Entra Connect Sync) runs only on
    Windows, and Get-Service exists only there. Off Windows there is no such service to
    find, so this returns nothing instead of failing on the missing command.

    .EXAMPLE
    ```powershell
    if (Get-LocalAdSyncService) { Start-ADSyncSyncCycle -PolicyType Delta }
    ```
    Pushes a delta sync when this device runs the sync service.

    .OUTPUTS
    The ADSync service object, or nothing when it is not on this device.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    Import-IRTModule -Name 'PSFramework'

    if (-not (Get-Command -Name 'Get-Service' -ErrorAction Ignore)) {
        Write-PSFMessage -Level 8 -Message 'Get-Service is unavailable; no local ADSync service.'
        return
    }
    Get-Service -Name 'adsync' -ErrorAction SilentlyContinue
}
