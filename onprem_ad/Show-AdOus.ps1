New-Alias -Name 'ShowAdOus' -Value 'Show-AdOus' 
New-Alias -Name 'AdOus'     -Value 'Show-AdOus' 

function Show-AdOus {
    <#
	.SYNOPSIS
	Shows a list of all OUs with a count of users/devices.
	
	.NOTES
		Version: 1.0.1
	#>
    [CmdletBinding()]
    param (
    )

    begin {
        # custom output view
        $Params = @{
            TypeName                  = 'ShowAdOus'
            DefaultDisplayPropertySet = 'CanonicalName','Name','Users','Computers','DistinguishedName'
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
        $Ous = Get-ADOrganizationalUnit -Properties CanonicalName -Filter * | Sort-Object CanonicalName
        
        # create display objects
        foreach ( $Ou in $Ous ) {

            $UserCount = @( Get-AdUser -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel ).Count
            if ( $UserCount -le 0 ) {
                $UserCount = '-'
            }

            $ComputerCount = @( Get-AdComputer -Filter * -SearchBase $Ou.DistinguishedName -SearchScope OneLevel ).Count
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


