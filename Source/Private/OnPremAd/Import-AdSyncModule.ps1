function Import-AdSyncModule {
    <#
    .SYNOPSIS
    Loads the ADSync module, so Start-ADSyncSyncCycle can run on this device.

    .DESCRIPTION
    Internal helper for the functions that push a sync on a server running the ADSync
    service. The Entra Connect installer adds the ADSync module's folder to the machine's
    list of module folders, but a shell can miss it, such as one opened by a remote
    support tool whose service started before Entra Connect was installed. In that shell,
    Start-ADSyncSyncCycle is "not recognized".

    Does nothing when Start-ADSyncSyncCycle is already available. Otherwise, imports the
    module from the Entra Connect install folder, found from the ADSync service's program
    path, so a custom install folder works too. Reports an error when the module can't be
    found or loaded.

    Uses no PSFramework, like the other on-prem AD functions, so it still works when
    Copy-IRTFunction pastes it onto a server without that module.

    .EXAMPLE
    ```powershell
    if (Import-AdSyncModule) { Start-ADSyncSyncCycle -PolicyType Delta }
    ```
    Pushes a delta sync, loading the ADSync module first if this shell can't find it.

    .OUTPUTS
    System.Boolean. $true when Start-ADSyncSyncCycle is available, otherwise $false.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'Start-ADSyncSyncCycle' -ErrorAction Ignore) {
        return $true
    }

    # the service runs <install folder>\Bin\miiserver.exe, and the module is in Bin\ADSync
    $ServiceParams = @{
        Path        = 'HKLM:\SYSTEM\CurrentControlSet\Services\ADSync'
        Name        = 'ImagePath'
        ErrorAction = 'Ignore'
    }
    $ImagePath = (Get-ItemProperty @ServiceParams).ImagePath
    if (-not $ImagePath) {
        Write-IRT "Can't push sync: ADSync service program path not found." -Level Error
        return $false
    }

    # the path is quoted when it has spaces, and can be followed by arguments
    $ExePath = if ($ImagePath -match '^"(?<Path>[^"]+)"') { $Matches.Path } else { $ImagePath }
    $BinPath = Split-Path -Path $ExePath -Parent
    $ModuleFolder = Join-Path -Path $BinPath -ChildPath 'ADSync'
    $ModulePath = Join-Path -Path $ModuleFolder -ChildPath 'ADSync.psd1'
    if (-not (Test-Path -Path $ModulePath)) {
        Write-IRT "Can't push sync: ADSync module not found at ${ModulePath}." -Level Error
        return $false
    }

    try {
        Import-Module -Name $ModulePath -ErrorAction Stop
    }
    catch {
        $Msg = "Can't push sync: loading ADSync module from ${ModulePath} failed: $_"
        Write-IRT $Msg -Level Error
        return $false
    }
    return $true
}
