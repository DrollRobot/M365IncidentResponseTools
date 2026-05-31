function Set-AdUserEnabled {
    <#
    .SYNOPSIS
    Set Enabled property on on-premises AD user(s).
    Called by Disable-IRTAdUser and Enable-IRTAdUser.

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

        Write-IRT ''

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
            $null = & repadmin /syncall $env:ComputerName /APed *>&1
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
            $Msg = "Azure sync isn't running on this server. " +
            "Run Push-IRTAdSync, or duplicate actions in M365."
            Write-IRT $Msg -Level Error
        }
    }
}