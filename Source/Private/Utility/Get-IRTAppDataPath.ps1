function Get-IRTAppDataPath {
    <#
    .SYNOPSIS
    Returns the per-user folder where the module keeps its files, or a path inside it.

    .DESCRIPTION
    Internal helper. The module keeps its config, tenant caches, and token cache in a
    per-user application data folder, resolved with [Environment]::GetFolderPath so it
    works on every platform. On Windows that is %APPDATA% (or %LOCALAPPDATA% with
    -Local), where these files have always lived. On Linux and macOS it is the
    platform's equivalent, such as ~/.config. $env:APPDATA and $env:LOCALAPPDATA exist
    only on Windows.

    The folder is not created; callers that write to it create it first.

    .PARAMETER ChildPath
    Path segments to append below the module folder, such as a file name.

    .PARAMETER Local
    Use the machine-local application data folder instead of the roaming one.

    .EXAMPLE
    ```powershell
    $ConfigPath = Get-IRTAppDataPath -ChildPath 'config.json'
    ```
    Returns %APPDATA%\M365IncidentResponseTools\config.json on Windows and
    ~/.config/M365IncidentResponseTools/config.json on Linux.

    .OUTPUTS
    [string] the module folder, or the path below it.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string[]] $ChildPath = @(),
        [switch] $Local
    )

    Import-IRTModule -Name 'PSFramework'

    $SpecialFolder = if ($Local) { 'LocalApplicationData' } else { 'ApplicationData' }
    $BaseDir = [Environment]::GetFolderPath($SpecialFolder)
    if (-not $BaseDir) {
        # .NET returns an empty string when the platform has no such folder, e.g. on
        # Linux with HOME unset.
        throw "Cannot find the per-user $SpecialFolder folder. Is HOME set?"
    }

    $Path = Join-Path -Path $BaseDir -ChildPath 'M365IncidentResponseTools'
    foreach ($Segment in $ChildPath) {
        $Path = Join-Path -Path $Path -ChildPath $Segment
    }
    Write-PSFMessage -Level 9 -Message "Get-IRTAppDataPath ($SpecialFolder): $Path"
    return $Path
}
