New-Alias -Name 'GetAdAdmins' -Value 'Get-AdAdminUsers' 
New-Alias -Name 'AdAdmins'    -Value 'Get-AdAdminUsers' 

function Get-AdAdminUsers {
    <#
	.SYNOPSIS
	Displays a list of admin users.
	
	.NOTES
		Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [switch] $Csv
    )

    begin {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $CustomObjects = [System.Collections.Generic.List[PSObject]]::new()
        $AdminUsers = Get-ADUser -Filter { AdminCount -eq 1 } -Property *
        $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $DomainName = $Domain.Forest -split '\.' | Select-Object -First 1
        $DateString = Get-Date -Format "yy-MM-dd"
        $ExportFileName = "AdAdminUsers_${DomainName}_${DateString}.csv"
        $ExportPath = Join-Path "${env:SystemDrive}\Temp\" -ChildPath $ExportFileName
    }

    process {

        # sort users by enabled then last log on
        $AdminUsers = $AdminUsers | Sort-Object Enabled, LastLogOnDate -Descending

        foreach ( $User in $AdminUsers ) {

            # get group display names
            $UserGroups = ( $User.MemberOf | Get-AdGroup ).Name | Sort-Object

            # check for last logondate before trying to convert to local time to avoid errors
            if ( $User.LastLogOnDate ) {
                $LastLogOnDate = $User.LastLogOnDate.ToLocalTime()
            }
            else {
                $LastLogOnDate = $null
            }

            # create custom object for user
            $CustomObject = [pscustomobject]@{
                Enabled           = $User.Enabled
                LastLogOnDate     = $LastLogOnDate
                DisplayName       = $User.DisplayName
                SamAccountName    = $User.SamAccountName
                UserPrincipalName = $User.UserPrincipalName
                MemberOf          = $UserGroups -join ', '
                DistinguishedName = $User.DistinguishedName
            }
            $CustomObjects.Add( $CustomObject )
        }

        # show table in terminal
        $CustomObjects | Format-Table -AutoSize

        # if csv, output table to file
        if ( $Csv ) {
            Write-Host "Exporting CSV to: ${ExportPath}"
            $CustomObjects | Export-Csv -Path $ExportPath -NoTypeInformation
        }
    }
}


