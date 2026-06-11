function Import-MsalExtensionAssembly {
    <#
    .SYNOPSIS
    Ensures the Microsoft.Identity.Client.Extensions.Msal assembly is loaded.

    .DESCRIPTION
    Internal helper. If the assembly is not already loaded into the AppDomain,
    loads the copy bundled with the module under Data\ via Add-Type. Throws if
    the bundled DLL is missing, or if the loaded MSAL version is older than the
    bundled Extensions.Msal requires.

    The DLL is committed to the repo and restored by Build\PreBuild.ps1 if it
    goes missing, so there is no runtime download.

    .EXAMPLE
    Import-MsalExtensionAssembly

    .OUTPUTS
    [string] - the path to the loaded Extensions DLL.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    Import-IRTModule -Name 'PSFramework'

    # Bundled version. Bump when Graph SDK's bundled MSAL outpaces this.
    $MsalFloor = [version]'4.61.3'  # Extensions.Msal 4.66.x minimum MSAL

    # Already loaded?
    $Loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client.Extensions.Msal' }
    if ($Loaded) {
        Write-PSFMessage -Level 8 -Message (
            "Import-MsalExtensionAssembly: Already loaded from $($Loaded.Location)")
        return $Loaded.Location
    }

    # Verify the MSAL DLL Graph loaded meets the Extensions floor.
    $Msal = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
        Select-Object -First 1
    if (-not $Msal) {
        throw 'Microsoft.Identity.Client is not loaded. ' +
        'Call Import-MsalAssembly before calling Import-MsalExtensionAssembly.'
    }
    $MsalVersion = [version]$Msal.GetName().Version
    Write-PSFMessage -Level 8 -Message (
        "Import-MsalExtensionAssembly: Loaded MSAL version: $MsalVersion (floor: $MsalFloor)")
    if ($MsalVersion -lt $MsalFloor) {
        throw ("Loaded MSAL version $MsalVersion is older than the bundled Extensions.Msal " +
            "requires ($MsalFloor). Update Microsoft.Graph.Authentication.")
    }

    # Resolve the bundled DLL relative to the module root. Works in both source
    # mode (Source\Data\) and built mode (module root Data\).
    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
    $DllPathParams = @{
        Path                = $ModuleRoot
        ChildPath           = 'Data'
        AdditionalChildPath = 'Microsoft.Identity.Client.Extensions.Msal.dll'
    }
    $DllPath = Join-Path @DllPathParams

    Write-PSFMessage -Level 8 -Message "Import-MsalExtensionAssembly: DLL path: $DllPath"
    if (-not (Test-Path -LiteralPath $DllPath)) {
        throw ("Bundled MSAL extensions assembly not found at: $DllPath. " +
            'The module build is incomplete - re-install the module or run Build.ps1.')
    }

    Add-Type -Path $DllPath
    return $DllPath
}
