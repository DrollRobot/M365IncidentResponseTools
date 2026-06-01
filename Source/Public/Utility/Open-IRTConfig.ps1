function Open-IRTConfig {
    <#
    .SYNOPSIS
    Opens the IRT config.json file for editing.
    #>
    [Alias('OpenConfig')]
    [CmdletBinding()]
    param()

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $JoinParams = @{
        Path                = $env:APPDATA
        ChildPath           = $ModuleName
        AdditionalChildPath = 'config.json'
    }
    $ConfigPath = Join-Path @JoinParams

    if (-not (Test-Path $ConfigPath)) {
        Import-IRTConfig
    }

    Invoke-Item $ConfigPath
}
