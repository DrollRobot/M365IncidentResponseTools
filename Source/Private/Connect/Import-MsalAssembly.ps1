function Import-MsalAssembly {
    <#
    .SYNOPSIS
    Ensures the Microsoft.Identity.Client MSAL assembly is loaded into the AppDomain.

    .DESCRIPTION
    Checks whether Microsoft.Identity.Client is already present in the current AppDomain.
    If not, locates the DLL bundled under the Microsoft.Graph.Authentication module and
    loads it via Add-Type. Throws if the module is unavailable, the DLL path does not
    exist, or Add-Type fails.

    .OUTPUTS
    System.Reflection.Assembly. The loaded Microsoft.Identity.Client assembly.

    .EXAMPLE
    Import-MsalAssembly

    .NOTES
    Version: 1.1.0
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param()

    Import-IRTModule -Name 'PSFramework'

    $Assembly = Get-LoadedAssembly -Name 'Microsoft.Identity.Client'

    if ($Assembly) {
        Write-PSFMessage -Level 8 -Message "MSAL assembly already loaded: $($Assembly.FullName)"
        return $Assembly
    }

    # Microsoft.Graph.Authentication ships the MSAL DLL and is a declared
    # dependency, but Get-Module only sees it once it is imported.
    Import-IRTModule -Name 'Microsoft.Graph.Authentication'
    $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    if (-not $GraphModule) {
        throw ('Microsoft.Graph.Authentication could not be loaded. It is a required ' +
            'dependency and supplies the MSAL assembly.')
    }
    Write-PSFMessage -Level 8 -Message (
        "Microsoft.Graph.Authentication version: " +
        "$($GraphModule.Version)")
    $MsalDllParams = @{
        Path                = $GraphModule.ModuleBase
        ChildPath           = 'Dependencies'
        AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
    }
    $MsalDll = Join-Path @MsalDllParams
    Write-PSFMessage -Level 8 -Message "Loading MSAL assembly from: $MsalDll"
    if (-not (Test-Path -LiteralPath $MsalDll)) {
        throw "MSAL assembly not found at expected path: $MsalDll"
    }
    try {
        Add-Type -Path $MsalDll -ErrorAction Stop
    } catch {
        throw "Failed to load MSAL assembly from '$MsalDll': $_"
    }
    return Get-LoadedAssembly -Name 'Microsoft.Identity.Client'
}
