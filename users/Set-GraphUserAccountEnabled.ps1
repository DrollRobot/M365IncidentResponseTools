###############################################################################
#region Disable-GraphUsers

# new aliases
New-Alias -Name 'DisableUser' -Value 'Disable-GraphUsers' -Force
New-Alias -Name 'DisableUsers' -Value 'Disable-GraphUsers' -Force
New-Alias -Name 'Disable-GraphUser' -Value 'Disable-GraphUsers' -Force

# old aliases
New-Alias -Name 'Lock-GraphUsers' -Value 'Disable-GraphUsers' -Force
New-Alias -Name 'LockUser' -Value 'Disable-GraphUsers' -Force
New-Alias -Name 'LockUsers' -Value 'Disable-GraphUsers' -Force
New-Alias -Name 'Lock-GraphUser' -Value 'Disable-GraphUsers' -Force

function Disable-GraphUsers {
    <#
	.SYNOPSIS
	Disable graph user account(s).
	
	.NOTES
	Version: 2.0.0
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObjects ) {
        $Params['UserObjects'] = $UserObjects
    }

    Set-GraphUserAccountEnabled @Params
}


###############################################################################
#region Enable-GraphUsers

# new aliases
New-Alias -Name 'EnableUser' -Value 'Enable-GraphUsers' -Force
New-Alias -Name 'EnableUsers' -Value 'Enable-GraphUsers' -Force
New-Alias -Name 'Enable-GraphUser' -Value 'Enable-GraphUsers' -Force

# old aliases
New-Alias -Name 'Unlock-GraphUsers' -Value 'Enable-GraphUsers' -Force
New-Alias -Name 'UnlockUser' -Value 'Enable-GraphUsers' -Force
New-Alias -Name 'UnlockUsers' -Value 'Enable-GraphUsers' -Force
New-Alias -Name 'Unlock-GraphUser' -Value 'Enable-GraphUsers' -Force

function Enable-GraphUsers {
    <#
	.SYNOPSIS
	Enable graph user account(s).
	
	.NOTES
	Version: 2.0.0
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObjects ) {
        $Params['UserObjects'] = $UserObjects
    }

    Set-GraphUserAccountEnabled @Params
}

###############################################################################
#region Set-GraphUserAccountEnabled

function Set-GraphUserAccountEnabled {
    <#
	.SYNOPSIS
	Set AccountEnabled property on graph user(s). Called by Disable-GraphUsers and Enable-GraphUsers.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [Parameter( Mandatory )]
        [bool] $Enabled
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
        $Red = @{ ForegroundColor = 'Red' }

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # if disabling, force sign outs
            if ( -not $Enabled ) {
                Write-Host @Blue "`nRevoking user sessions."
                Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id | Out-Null
            }

            # disable/enable account
            Write-Host @Blue "`n${Action}ing user account... (set AccountEnabled=$Enabled)"
            Update-MgUser -UserId $ScriptUserObject.Id -AccountEnabled:$Enabled

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

