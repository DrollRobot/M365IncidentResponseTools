New-Alias -Name 'FindAdOu'  -Value 'Find-AdOu' 
New-Alias -Name 'FindAdOus' -Value 'Find-AdOu' 
New-Alias -Name 'Find-AdOus' -Value 'Find-AdOu' 

function Find-AdOu {
    <#
    .SYNOPSIS
    Makes finding specific Ou easier.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string] $Search,
        [switch] $Script
    )

    begin {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $Properties = @(
            'Name'
            'CanonicalName'
            'DistinguishedName'
        )

        # find users whos displayname or email matches search
        $Ous = Get-ADOrganizationalUnit -Filter * -Properties $Properties
    }

    process {

        # find matching ous
        $MatchingOus = $Ous | Where-Object {
            $_.Name -match $Search -or
            $_.CanonicalName -eq $Search -or
            $_.DistinguishedName -eq $Search
        }

        # if one ou found
        if ( @( $MatchingOus ).Count -eq 1 ) {

            if ( $Script ) {
                # return object
                return $MatchingOus
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties
        
                # set variable
                New-Variable -Name "OuObject" -Value $MatchingOus -Scope 'Global'
                Write-Host "Created `$Global:OuObject."
                Write-Host ''
            }
        }
        # if multiple ous found
        elseif ( @( $MatchingOus ).Count -gt 1 ) {

            if ( $Script ) {

                # show ou info
                $MatchingOus | Format-Table $Properties | Out-Default
        
                # tell user to try again
                throw 'Multiple Ous found. Search again.' 
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties
        
                # tell user to try again
                Write-Host 'Multiple Ous found. Search again.' 
            }   
        }
        # if no users found, tell user to search again
        else {

            if ( $Script ) {
                # tell user to try again
                throw "$Search not found. Try a different search."
            }
            else {
                # tell user to try again
                Write-Host "$Search not found. Try a different search."
            }  
        }
    }
}


