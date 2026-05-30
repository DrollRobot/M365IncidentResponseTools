###############################################################################
#region Disable-GraphUser

# new aliases

# old aliases

function Disable-GraphUser {
    <#
	.SYNOPSIS
	Disable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('DisableUser', 'DisableUsers', 'Lock-GraphUsers',
        'LockUser', 'LockUsers', 'Lock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-IRTUserEnabled @Params
}


###############################################################################
#region Enable-GraphUser

# new aliases

# old aliases

function Enable-GraphUser {
    <#
	.SYNOPSIS
	Enable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('EnableUser', 'EnableUsers', 'Unlock-GraphUsers',
        'UnlockUser', 'UnlockUsers', 'Unlock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-IRTUserEnabled @Params
}

###############################################################################
#region Set-IRTUserEnabled

function Set-IRTUserEnabled {
    <#
	.SYNOPSIS
	Set AccountEnabled property on graph user(s). Called by Disable-GraphUser and Enable-GraphUser.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-IRTUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
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
                Write-IRT "Revoking user sessions..."
                $Upn = $ScriptUserObject.UserPrincipalName
                if ($PSCmdlet.ShouldProcess($Upn, 'Revoke sign-in sessions')) {
                    $null = Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id
                }
            }

            # disable/enable account
            Write-IRT "$($Action.TrimEnd('e'))ing user account..."
            if ($PSCmdlet.ShouldProcess($ScriptUserObject.UserPrincipalName, "$Action account")) {
                Update-MgUser -UserId $ScriptUserObject.Id -AccountEnabled:$Enabled
            }

            # get new user object
            Write-IRT "Getting updated user properties."
            $NewUserObject = Get-MgUser -UserId $ScriptUserObject.Id -Property $GetProperties

            # display new object
            $NewUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ($NewUserObject.OnPremisesSyncEnabled) {
                $Msg = "User is synced from on-premises. ${Action} user in local AD too!"
                Write-IRT $Msg -Level Error
            }
        }


        ### show last onprem sync time
        # get date object
        if ($NewUserObject.OnPremisesSyncEnabled) {
            $LastOrgSync = (Get-MgOrganization).OnPremisesLastSyncDateTime
        }
        if ($LastOrgSync) {
            # build date string
            $BuildString = $LastOrgSync.ToLocalTime().ToString('MM/dd/yy hh:mmtt').ToLower()

            # create acronym from timezone full name
            if ($LastOrgSync.IsDaylightSavingTime()) {
                $TimeZoneName = $TimeZoneInfo.DaylightName
            }
            else {
                $TimeZoneName = $TimeZoneInfo.StandardName
            }
            $TimeZoneAcronym = -join ($TimeZoneName -split ' ' | ForEach-Object {$_[0]})

            # add time zone acronym to string
            $DateString = $BuildString + " " + $TimeZoneAcronym

            Write-IRT "Last on-premises sync:"
            Write-IRT $DateString
        }
    }
}

