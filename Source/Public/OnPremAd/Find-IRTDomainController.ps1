function Find-IRTDomainController {
    <#
    .SYNOPSIS
    Lists the names of all domain controllers in the current AD domain.

    .DESCRIPTION
    Queries Active Directory for all domain controllers via Get-ADDomainController
    and returns their computer names. Requires the ActiveDirectory RSAT module and
    a reachable domain controller; exits with an error if AD is unavailable.

    .EXAMPLE
    Find-IRTDomainController
    Returns the Name of every domain controller in the domain.

    .EXAMPLE
    $DCs = Find-IRTDomainController
    Captures the list of DC names for use in a loop or downstream command.

    .OUTPUTS
    Microsoft.ActiveDirectory.Management.ADDomainController (Name property selected)
    #>
    [Alias(
        # DomainController
        'FindIRTDomainController', 'Find-IRTDomainControllers', 'FindIRTDomainControllers',
        'Find-DomainController', 'FindDomainController', 'Find-DomainControllers', 'FindDomainControllers',
        # DC
        'Find-DC', 'FindDC', 'Find-DCs', 'FindDCs',
        'DC', 'DCs'
    )]
    param()

    if ( -not ( Test-AdAvailable ) ) {
        Write-Error 'ActiveDirectory RSAT module not available.'
        return
    }

    Get-ADDomainController -Filter * | Select-Object Name
}