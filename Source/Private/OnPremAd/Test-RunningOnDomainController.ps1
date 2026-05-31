function Test-RunningOnDomainController {
    <#
    .SYNOPSIS
    Returns true if the current machine is a domain controller.

    .DESCRIPTION
    Internal helper. Compares $env:ComputerName against the list of domain controllers
    returned by Get-ADDomainController -Filter *. Returns $false on any error. Used to
    gate repadmin calls that must run on a DC.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    try {
        $DomainControllerNames = (Get-ADDomainController -Filter *).Name
        return $env:ComputerName -in $DomainControllerNames
    }
    catch {
        return $false
    }
}