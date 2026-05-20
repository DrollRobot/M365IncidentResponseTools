###############################################################################
#region Disable-AdUser

# new aliases

# old aliases

function Disable-AdUser {
    <#
    .SYNOPSIS
    Disable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $false. Disables one or
    more AD user accounts, re-fetches each account to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to disable. Falls back to global session objects if omitted.

    .EXAMPLE
    Disable-AdUser
    Disables the user(s) in the global session.

    .EXAMPLE
    Disable-AdUser -UserObject $AdUser
    Disables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias('DisableAdUser', 'DisableAdUsers', 'Lock-AdUser', 'Lock-AdUsers', 'LockAdUser', 'LockAdUsers')]
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

# old aliases

function Enable-AdUser {
    <#
    .SYNOPSIS
    Enable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $true. Re-enables one or
    more disabled AD user accounts, re-fetches each to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to enable. Falls back to global session objects if omitted.

    .EXAMPLE
    Enable-AdUser
    Re-enables the user(s) in the global session.

    .EXAMPLE
    Enable-AdUser -UserObject $AdUser
    Re-enables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias('EnableAdUser', 'EnableAdUsers', 'Unlock-AdUser', 'Unlock-AdUsers', 'UnlockAdUser', 'UnlockAdUsers')]
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

    .DESCRIPTION
    Core implementation for enabling or disabling AD user accounts. For each user, calls
    Enable-AdAccount or Disable-AdAccount using $env:ComputerName as the target DC, then
    re-fetches the account to confirm the Enabled state changed. Triggers AD replication
    via repadmin if running on a DC, and Start-ADSyncSyncCycle if the ADSync service is
    local. Not typically called directly - use Disable-AdUser or Enable-AdUser instead.

    .PARAMETER UserObject
    One or more AD user objects to modify. Falls back to global session objects if omitted.

    .PARAMETER Enabled
    Required. $true to enable the account, $false to disable it.

    .EXAMPLE
    Set-AdUserEnabled -UserObject $AdUser -Enabled $false
    Disables the specified user account.

    .OUTPUTS
    None. Status is written to the console.

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
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $UserProperties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
        )

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }

        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
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
            Write-IRT "`n$($Action.TrimEnd('e'))ing $($ScriptUserObject.SamAccountName)."
            $Params = @{
                Identity = $ScriptUserObject
                Server   = $env:ComputerName
            }
            if ($PSCmdlet.ShouldProcess($ScriptUserObject.SamAccountName, "$Action account")) {
                if ( $Enabled ) {
                    Enable-AdAccount @Params
                }
                else {
                    Disable-AdAccount @Params
                }
            }

            # get new object to show result
            Write-IRT "`nGetting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $UserProperties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add( $NewObject )
        }

        # show results
        $OutputObjects | Format-Table $UserProperties

        # push ad replication
        if ( Test-RunningOnDomainController ) {
            Write-IRT "Pushing AD replication."
            & repadmin /syncall $env:ComputerName /APed *>&1 | Out-Null
        }
        else {
            Write-Warning "Not running on a domain controller; skipping replication push."
        }

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ( $SyncService ) {
            Write-IRT "`nPushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            Write-IRT "Azure sync isn't running on this server. Run Push-AdSync, or duplicate actions in M365." -Level Error
        }
    }
}
