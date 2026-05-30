function Find-IRTAllDomainController {
    <#
    .SYNOPSIS
    Lists the names of all domain controllers in the current AD domain.

    .DESCRIPTION
    Queries Active Directory for all domain controllers via Get-ADDomainController
    and returns their computer names. Requires the ActiveDirectory RSAT module and
    a reachable domain controller; exits with an error if AD is unavailable.

    .EXAMPLE
    Find-IRTAllDomainController
    Returns the Name of every domain controller in the domain.

    .EXAMPLE
    $DCs = Find-IRTAllDomainController
    Captures the list of DC names for use in a loop or downstream command.

    .OUTPUTS
    Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
    #>
    [Alias(
        # AllDomainController
        'Find-IRTAllDomainControllers',
        'Find-AllDomainController', 'Find-AllDomainControllers',
        'FindIRTAllDomainController', 'FindIRTAllDomainControllers',
        'FindAllDomainController', 'FindAllDomainControllers',
        # DomainController
        'Find-IRTDomainController', 'Find-IRTDomainControllers',
        'Find-DomainController', 'Find-DomainControllers',
        'FindIRTDomainController', 'FindIRTDomainControllers',
        'FindDomainController', 'FindDomainControllers',
        # DC
        'Find-IRTDC', 'Find-IRTDCs',
        'Find-DC', 'Find-DCs',
        'FindIRTDC', 'FindIRTDCs',
        'FindDC', 'FindDCs'
    )]
    param()

    if ( -not ( Test-AdAvailable ) ) {
        Write-Error 'ActiveDirectory RSAT module not available.'
        return
    }

    Get-ADDomainController -Filter * | Select-Object Name
}


