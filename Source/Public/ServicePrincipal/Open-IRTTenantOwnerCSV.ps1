function Open-IRTTenantOwnerCSV {
    <#
    .SYNOPSIS
    Opens the local tenant info cache CSV in the default application.

    .DESCRIPTION
    Opens $env:APPDATA\<ModuleName>\TenantOwnerInfo.csv in the system default
    application (typically Excel or Notepad), where <ModuleName> is resolved at
    runtime. If the file does not exist yet, a warning is displayed.

    .EXAMPLE
    Open-IRTTenantOwnerCSV

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param ()

    $moduleName = $MyInvocation.MyCommand.ModuleName
    $JpParams = @{
        Path                = $env:APPDATA
        ChildPath           = $moduleName
        AdditionalChildPath = 'TenantOwnerInfo.csv'
    }
    $cachePath = Join-Path @JpParams

    if (-not (Test-Path $cachePath)) {
        $Msg = "Tenant info cache not found at '$cachePath'. " +
        "Run Get-IRTTenantOwner first to populate it."
        Write-IRT $Msg -Level Warn
        return
    }

    Write-PSFMessage -Level 8 -Message "Opening $cachePath"
    Start-Process $cachePath
}
