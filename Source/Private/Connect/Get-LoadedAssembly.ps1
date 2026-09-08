function Get-LoadedAssembly {
    <#
    .SYNOPSIS
    Returns an assembly already loaded into the current AppDomain, by simple name.

    .DESCRIPTION
    Internal helper. Wraps the AppDomain assembly query the MSAL loaders use to
    decide whether they still need to call Add-Type. Assemblies cannot be
    unloaded from a running process, so keeping this query in one mockable
    function is what lets the loaders' Add-Type branches be tested regardless of
    what the rest of the session has already loaded.

    Matching is on the assembly's simple name, so 'Microsoft.Identity.Client'
    does not match 'Microsoft.Identity.Client.Extensions.Msal'.

    .PARAMETER Name
    The simple assembly name to look for, e.g. 'Microsoft.Identity.Client'.

    .EXAMPLE
    Get-LoadedAssembly -Name 'Microsoft.Identity.Client'

    Returns the loaded core MSAL assembly, or $null when it is not loaded.

    .OUTPUTS
    System.Reflection.Assembly. The first matching assembly, or $null.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([System.Reflection.Assembly])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq $Name } |
        Select-Object -First 1
}
