function Reset-AdUserPassword {
    <#
    .SYNOPSIS
    Resets an Active Directory user's password.

    .DESCRIPTION
    Resets the on-premises AD password for one or more users. Two modes are available:

    - RandomCharacters (default): generates a 30-character random password using
      Get-RandomPassword and writes it directly to [Console]::WriteLine to intentionally
      bypass transcript logging.
    - Custom: prompts interactively via Read-Host -AsSecureString.

    After the reset, the user object is re-fetched to confirm PasswordLastSet changed.
    If running on a domain controller, intra-AD replication is triggered via repadmin.
    If the ADSync service is local, an Azure AD delta sync is started.

    Falls back to $Global:UserObjects if no -UserObjects is passed.

    .PARAMETER UserObjects
    One or more AD user objects to reset. Falls back to global session objects if omitted.

    .PARAMETER Custom
    Prompt for a custom password instead of generating a random one.

    .PARAMETER RandomCharacters
    Generate a 30-character random password (default behavior).

    .EXAMPLE
    Reset-AdUserPassword
    Generates and sets a random password for the user in the global session.

    .EXAMPLE
    Reset-AdUserPassword -UserObjects $User -Custom
    Prompts for a custom password for a specific user.

    .OUTPUTS
    None. The new password is written to the console (bypassing transcripts).

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ResetAdPassword', 'ResetAdPasswords', 'Reset-AdPassword')]
    [CmdletBinding( DefaultParameterSetName = 'RandomCharacters' )]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [Parameter( ParameterSetName = 'Custom' )]
        [switch] $Custom,

        [Parameter( ParameterSetName = 'RandomCharacters' )]
        [Alias( 'Random' )]
        [switch] $RandomCharacters
    )

    begin {
        $ParameterSet = $PSCmdlet.ParameterSetName
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $UserProperties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
            'PasswordLastSet'
        )

        # if not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

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

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        Write-Host ''

        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $Username = $ScriptUserObject.SamAccountName

            switch ($true) {
                $Custom {
                    $Password = Read-Host -AsSecureString "Enter new password for ${Username}"
                    break
                }
                $RandomCharacters {

                    $PlainTextPassword = Get-RandomPassword 30
                    $ConvertParams = @{
                        String      = $PlainTextPassword
                        AsPlainText = $true
                        Force       = $true
                    }
                    $Password = ConvertTo-SecureString @ConvertParams

                    Write-IRT "`n${Username} new password:"
                    # Console WriteLine prevents password from bring recorded in logs/transcripts
                    [Console]::WriteLine($PlainTextPassword)
                }
            }

            # reset password
            $ResetParams = @{
                 Identity = $ScriptUserObject
                 Reset = $true
                 NewPassword = $Password
                 Server = $Env:ComputerName
            }
            Set-AdAccountPassword @ResetParams

            # get new object to show result
            Write-IRT "`nGetting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $UserProperties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add($NewObject)
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


