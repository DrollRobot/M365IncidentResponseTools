New-Alias -Name 'ShowAdUser'  -Value 'Show-AdUserInfo' -Force
New-Alias -Name 'ShowAdUsers' -Value 'Show-AdUserInfo' -Force
New-Alias -Name 'AdUserInfo'  -Value 'Show-AdUserInfo' -Force

function Show-AdUserInfo {
    <#
	.SYNOPSIS
	Displays user properties.	
	
	.NOTES
		Version: 1.1.2
    1.1.2 - Added pwdLastSet
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects
    )

    begin {

        # if not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObjects

            # if none found, exit
            if ( -not $ScriptUserObjects ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # get user object with all properties
            $FullObject = $ScriptUserObject | Get-AdUser -Property *

            try {
                $WhenCreated = $FullObject.WhenCreated.ToLocalTime()
                $LastLogOnDate = $FullObject.LastLogOnDate.ToLocalTime()
                $PasswordLastSet = $FullObject.PasswordLastSet.ToLocalTime()
            }
            catch {}

            $OutputTable = [PSCustomObject]@{
                Enabled                    = $FullObject.Enabled
                WhenCreated                = $WhenCreated
                LastLogOnDate              = $LastLogOnDate
                PasswordLastSet            = $PasswordLastSet
                pwdLastSet                 = $FullObject.pwdLastSet
                PasswordNeverExpires       = $FullObject.PasswordNeverExpires
                GivenName                  = $FullObject.GivenName
                Surname                    = $FullObject.Surname
                Name                       = $FullObject.Name
                DisplayName                = $FullObject.DisplayName
                Description                = $FullObject.Description
                Office                     = $FullObject.Office
                UserPrincipalName          = $FullObject.UserPrincipalName
                EmailAddress               = $FullObject.EmailAddress
                SamAccountName             = $FullObject.SamAccountName
                StreetAddress              = $FullObject.StreetAddress
                City                       = $FullObject.City
                State                      = $FullObject.State
                Country                    = $FullObject.Country
                PostalCode                 = $FullObject.PostalCode
                ProfilePath                = $FullObject.ProfilePath
                ScriptPath                 = $FullObject.ScriptPath
                Homedrive                  = $FullObject.Homedrive
                HomeDirectory              = $FullObject.HomeDirectory
                OfficePhone                = $FullObject.OfficePhone
                MobilePhone                = $FullObject.MobilePhone
                Title                      = $FullObject.Title
                Department                 = $FullObject.Department
                Company                    = $FullObject.Company
                Manager                    = $FullObject.Manager
                MsnpAllowDialIn            = $FullObject.MsnpAllowDialIn
                msExchHideFromAddressLists = $FullObject.msExchHideFromAddressLists
                mailNickname               = $FullObject.mailNickname
                proxyAddresses             = $FullObject.proxyAddresses
                MemberOf                   = $FullObject.MemberOf
                DistinguishedName          = $FullObject.DistinguishedName
            }

            $OutputTable | Format-List 
        }
    }
}


