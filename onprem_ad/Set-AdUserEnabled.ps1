###############################################################################
#region Disable-AdUser

# new aliases
New-Alias -Name 'DisableAdUser'  -Value 'Disable-AdUser' 
New-Alias -Name 'DisableAdUsers' -Value 'Disable-AdUser' 

# old aliases
New-Alias -Name 'Lock-AdUser'  -Value 'Disable-AdUser' 
New-Alias -Name 'Lock-AdUsers' -Value 'Disable-AdUser' 
New-Alias -Name 'LockAdUser'   -Value 'Disable-AdUser' 
New-Alias -Name 'LockAdUsers'  -Value 'Disable-AdUser' 

function Disable-AdUser {
    <#
    .SYNOPSIS
    Disable on-premises AD user account(s).

    .NOTES
    Version: 2.0.0
    #>
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

    Set-AdUserEnabled @Params
}


###############################################################################
#region Enable-AdUser

# new aliases
New-Alias -Name 'EnableAdUser'  -Value 'Enable-AdUser' 
New-Alias -Name 'EnableAdUsers' -Value 'Enable-AdUser' 

# old aliases
New-Alias -Name 'Unlock-AdUser'  -Value 'Enable-AdUser' 
New-Alias -Name 'Unlock-AdUsers' -Value 'Enable-AdUser' 
New-Alias -Name 'UnlockAdUser'   -Value 'Enable-AdUser' 
New-Alias -Name 'UnlockAdUsers'  -Value 'Enable-AdUser' 

function Enable-AdUser {
    <#
    .SYNOPSIS
    Enable on-premises AD user account(s).

    .NOTES
    Version: 2.0.0
    #>
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

    Set-AdUserEnabled @Params
}


###############################################################################
#region Set-AdUserEnabled

function Set-AdUserEnabled {
    <#
    .SYNOPSIS
    Set Enabled property on on-premises AD user(s). Called by Disable-AdUser and Enable-AdUser.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {

        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObjects

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # variables
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $Properties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
        )
        $Cyan = @{ ForegroundColor = 'Cyan' }
        $Red  = @{ ForegroundColor = 'Red' }

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
    }

    process {

        if ( -not (Test-AdAvailable) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        Write-Host ''

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # disable/enable the user object
            Write-Host @Cyan "`n$($Action.TrimEnd('e'))ing $($ScriptUserObject.SamAccountName)."
            $Params = @{
                Identity = $ScriptUserObject
                Server   = $env:ComputerName
            }
            if ( $Enabled ) {
                Enable-AdAccount @Params
            }
            else {
                Disable-AdAccount @Params
            }

            # get new object to show result
            Write-Host @Cyan "`nGetting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $Properties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add( $NewObject )
        }

        # show results
        $OutputObjects | Format-Table $Properties

        # push ad replication
        if ( Test-RunningOnDomainController ) {
            Write-Host @Cyan "Pushing AD replication."
            & repadmin /syncall $env:ComputerName /APed *>&1 | Out-Null
        }
        else {
            Write-Warning "Not running on a domain controller; skipping replication push."
        }

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ( $SyncService ) {
            Write-Host @Cyan "`nPushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            Write-Host @Red "Azure sync isn't running on this server. Force sync, or duplicate actions in M365."
        }
    }
}
