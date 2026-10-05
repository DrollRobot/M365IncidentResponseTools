function Get-AssemblyFileVersion {
    <#
    .SYNOPSIS
    Returns the assembly version of a DLL on disk, without loading it.

    .DESCRIPTION
    Internal helper. Wraps [System.Reflection.AssemblyName]::GetAssemblyName so
    Import-MsalDependency can compare candidate DLLs by version. Keeping the static
    call in one mockable function lets the selection logic be tested without real
    DLLs on disk.

    .PARAMETER Path
    Full path to the DLL.

    .EXAMPLE
    Get-AssemblyFileVersion -Path 'C:\Modules\Foo\Microsoft.IdentityModel.Abstractions.dll'

    Returns the assembly version, e.g. 8.19.2.0.

    .OUTPUTS
    System.Version. The assembly version (not the file version).

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    Import-IRTModule -Name 'PSFramework'

    $Version = [System.Reflection.AssemblyName]::GetAssemblyName($Path).Version
    Write-PSFMessage -Level 9 -Message "Assembly version $Version at: $Path"
    return $Version
}
