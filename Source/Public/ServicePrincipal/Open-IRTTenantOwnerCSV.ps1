function Open-IRTTenantOwnerCSV {
    <#
    .SYNOPSIS
    Opens the local tenant info cache CSV in the default application.

    .DESCRIPTION
    Opens TenantOwnerInfo.csv from the module's per-user folder (%APPDATA%\<ModuleName>
    on Windows, ~/.config/<ModuleName> on Linux and macOS) in the system default
    application. If the file does not exist yet, a warning is displayed.

    .EXAMPLE
    ```powershell
    Open-IRTTenantOwnerCSV
    ```

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param ()

    Import-IRTModule -Name 'PSFramework'

    $cachePath = Get-IRTAppDataPath -ChildPath 'TenantOwnerInfo.csv'

    if (-not (Test-Path $cachePath)) {
        $Msg = "Tenant info cache not found at '$cachePath'. " +
        "Run Get-IRTTenantOwner first to populate it."
        Write-IRT $Msg -Level Warn
        return
    }

    Write-PSFMessage -Level 8 -Message "Opening $cachePath"
    Start-Process $cachePath
}
