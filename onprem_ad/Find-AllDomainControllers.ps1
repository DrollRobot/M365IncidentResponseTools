function Find-AllDomainControllers {
    <#
    .SYNOPSIS
    Lists the names of all domain controllers in the current AD domain.

    .DESCRIPTION
    Queries Active Directory for all domain controllers via Get-ADDomainController
    and returns their computer names. Requires the ActiveDirectory RSAT module and
    a reachable domain controller; exits with an error if AD is unavailable.

    .EXAMPLE
    Find-AllDomainControllers
    Returns the Name of every domain controller in the domain.

    .EXAMPLE
    $DCs = Find-AllDomainControllers
    Captures the list of DC names for use in a loop or downstream command.

    .OUTPUTS
    Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
    #>
    [Alias('FindDCs', 'FindDomainControllers', 'Find-DCs')]
    param()

    if ( -not ( Test-AdAvailable ) ) {
        Write-Error 'ActiveDirectory RSAT module not available.'
        return
    }

    Get-ADDomainController -Filter * | Select-Object Name
}


