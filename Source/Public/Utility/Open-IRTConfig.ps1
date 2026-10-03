function Open-IRTConfig {
    <#
    .SYNOPSIS
    Opens the IRT config.json file for editing.
    #>
    [Alias('OpenConfig')]
    [CmdletBinding()]
    param()

    $ConfigPath = Get-IRTAppDataPath -ChildPath 'config.json'

    if (-not (Test-Path $ConfigPath)) {
        Import-IRTConfig
    }

    Invoke-Item $ConfigPath
}
