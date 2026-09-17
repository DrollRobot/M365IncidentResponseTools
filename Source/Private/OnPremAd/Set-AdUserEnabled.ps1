function Set-AdUserEnabled {
    <#
    .SYNOPSIS
    Set Enabled property on on-premises AD user(s).
    Called by Disable-IRTAdUser and Enable-IRTAdUser.

    .DESCRIPTION
    Core implementation for enabling or disabling AD user accounts. Picks one writable
    domain controller (this computer if it is one, otherwise a discovered DC), then for
    each user calls Enable-AdAccount or Disable-AdAccount on that DC and re-fetches the
    account from it to confirm the Enabled state changed. Runs
    from any device with the ActiveDirectory module, not only a DC. Pushes AD replication
    from that DC via repadmin (skipped with a warning if repadmin isn't installed), and
    runs Start-ADSyncSyncCycle if the ADSync service is local. Not typically called
    directly - use Disable-AdUser or Enable-AdUser instead.

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
    Version: 1.1.0
    1.1.0 - Targets one writable DC (this computer if it is one, otherwise a discovered
            DC), so it no longer needs to run on a DC. Replication is pushed from that DC.
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
                # FIXME: replace throw; add function name to output
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

        # make every change on one writable DC, so the readback sees it and replication
        # pushes it from where it was made
        $DomainController = Get-TargetDomainController

        Write-IRT ''

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # disable/enable the user object
            Write-IRT "`n$($Action.TrimEnd('e'))ing $($ScriptUserObject.SamAccountName)."
            $Params = @{
                Identity = $ScriptUserObject
                Server   = $DomainController
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
                Server     = $DomainController
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add( $NewObject )
        }

        # show results
        $OutputObjects | Format-Table $UserProperties

        Push-AdReplication -Server $DomainController

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ( $SyncService ) {
            Write-IRT "`nPushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            $Msg = "Azure sync isn't running on this server. " +
            "Run Push-IRTAdSync, or duplicate actions in M365."
            Write-IRT $Msg -Level Error
        }
    }
}
