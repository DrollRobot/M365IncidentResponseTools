function Show-IRTAdOus {
    <#
    .SYNOPSIS
    Shows a list of all OUs with a count of users and devices.

    .DESCRIPTION
    Lists all Organizational Units in the current AD domain, sorted by CanonicalName.
    For each OU, counts users and computers directly inside it (OneLevel scope) and
    displays the results in a formatted table.

    Output objects use the custom type 'ShowAdOus' with a DefaultDisplayPropertySet
    so Format-Table shows CanonicalName, Name, Users, Computers, and DistinguishedName
    by default.

    .EXAMPLE
    Show-IRTAdOus
    Lists all OUs with user and computer counts.

    .EXAMPLE
    Show-IRTAdOus | Where-Object { $_.Users -gt 0 }
    Returns only OUs that contain at least one user.

    .OUTPUTS
    PSCustomObject[] (type: ShowAdOus)

    .NOTES
    Version: 1.0.1
    #>
    [Alias(
        'Show-IRTAdOu',
        'Show-AdOu', 'Show-AdOus',
        'ShowIRTAdOu', 'ShowIRTAdOus',
        'ShowAdOu', 'ShowAdOus',
        'AdOus'
    )]
    [CmdletBinding()]
    param (
    )

    begin {
        # custom output view
        $Params = @{
            TypeName                  = 'ShowAdOus'
            DefaultDisplayPropertySet = 'CanonicalName', 'Name', 'Users',
                'Computers', 'DistinguishedName'
            Force                     = $true
        }
        Update-TypeData @Params
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # get all ous
        $Ous = Get-ADOrganizationalUnit -Properties CanonicalName -Filter * |
            Sort-Object CanonicalName

        # create display objects
        foreach ( $Ou in $Ous ) {

            $UserCount = @(
                Get-AdUser -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel
            ).Count
            if ( $UserCount -le 0 ) {
                $UserCount = '-'
            }

            $ComputerCount = @(
                Get-AdComputer -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel
            ).Count
            if ( $ComputerCount -le 0 ) {
                $ComputerCount = '-'
            }

            [pscustomobject]@{
                PSTypeName   = 'ShowAdOus'
                CanonicalName     = $Ou.CanonicalName
                Name              = Split-Path $Ou.CanonicalName -Leaf
                Users             = $UserCount
                Computers         = $ComputerCount
                DistinguishedName = $Ou.DistinguishedName
            }
        }
    }
}


