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
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param()

    Import-IRTModule -Name 'PSFramework'

    $Assembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }

    if ($Assembly) {
        Write-PSFMessage -Level 8 -Message "MSAL assembly already loaded: $($Assembly.FullName)"
        return $Assembly
    }

    $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
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
    return [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }
}
