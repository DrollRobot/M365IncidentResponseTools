New-Alias -Name 'LockUser' -Value 'Lock-GraphUsers' -Force
New-Alias -Name 'LockUsers' -Value 'Lock-GraphUsers' -Force
New-Alias -Name 'Lock-GraphUser' -Value 'Lock-GraphUsers' -Force
function Lock-GraphUsers {
    <#
	.SYNOPSIS
	Lock/Unlock graph user.	
	
	.NOTES
	Version: 1.0.3
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [switch] $Unlock
    )

    begin {

        # if not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-IRTUserObjects
        
            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }

        # variables
        $GetProperties = @(
            'AccountEnabled'
            'DisplayName'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
            'Id'
        )
        $TimeZoneInfo = [System.TimeZoneInfo]::Local

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        $Red = @{ ForegroundColor = 'Red' }

        # set action string
        if ( $Unlock ) {
            $Action = 'Unlock'
            $BooleanAction = $true
        }
        else {
            $Action = 'Lock'
            $BooleanAction = $false
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # if locking, force sign outs
            if ( -not $Unlock ) {
                Write-Host @Blue "`nRevoking user sessions."
                Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id | Out-Null
            }

            # lock/unlock account
            Write-Host @Blue "`n${Action}ing user account."
            Update-MgUser -UserId $ScriptUserObject.Id -AccountEnabled:$BooleanAction

            # get new user object
            Write-Host @Blue "`nGetting updated user properties."
            $FullUserObject = Get-MgUser -UserId $ScriptUserObject.Id -Property $GetProperties

            # display new object
            $FullUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ( $FullUserObject.OnPremisesSyncEnabled ) {
                Write-Host @Red "`nUser is synced from on-premises. ${Action} user in local AD too!"
            }
        }


        ### show last onprem sync time 
        # get date object
        try {
            $SyncTime = (Get-MgOrganization).OnPremisesLastSyncDateTime.ToLocalTime()
        } catch {
            Write-Host @Red "Unable to retrieve last tenant on-prem sync time. Client may be cloud-only."
        }

        if ( $SyncTime ) {
            # build date string
            $BuildString = $SyncTime.ToLocalTime().ToString('MM/dd/yy hh:mmtt').ToLower()

            # create acronym from timezone full name
            if ( $SyncTime.IsDaylightSavingTime()) {
                $TimeZoneName = $TimeZoneInfo.DaylightName
            }
            else {
                $TimeZoneName = $TimeZoneInfo.StandardName
            }
            $TimeZoneAcronym = -join ( $TimeZoneName -split ' ' | ForEach-Object { $_[0] } )

            # add time zone acronym to string
            $DateString = $BuildString + " " + $TimeZoneAcronym

            Write-Host @Blue "`nLast on-premises sync:"
            Write-Host $DateString
        }
    }
}


