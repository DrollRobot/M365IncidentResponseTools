function Get-LocalAdSyncService {
    <#
    .SYNOPSIS
    Returns the ADSync service when it runs on this device, or nothing.

    .DESCRIPTION
    Internal helper. The ADSync service (Microsoft Entra Connect Sync) runs only on
    Windows, and Get-Service exists only there. Off Windows there is no such service to
    find, so this returns nothing instead of failing on the missing command.

    Uses no PSFramework, like the other on-prem AD functions, so it still works when
    Copy-IRTFunction pastes it onto a server without that module.

    .EXAMPLE
    ```powershell
    if (Get-LocalAdSyncService) { Start-ADSyncSyncCycle -PolicyType Delta }
    ```
    Pushes a delta sync when this device runs the sync service.

    .OUTPUTS
    The ADSync service object, or nothing when it is not on this device.

    .NOTES
    Version: 1.0.1
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-Service' -ErrorAction Ignore)) {
        return
    }
    Get-Service -Name 'adsync' -ErrorAction SilentlyContinue
}
