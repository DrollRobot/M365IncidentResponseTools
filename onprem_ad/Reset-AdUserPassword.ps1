New-Alias -Name 'ResetAdPassword'  -Value 'Reset-AdUserPassword' 
New-Alias -Name 'ResetAdPasswords' -Value 'Reset-AdUserPassword' 
New-Alias -Name 'Reset-AdPassword' -Value 'Reset-AdUserPassword' 

function Reset-AdUserPassword {
    <#
	.SYNOPSIS
	Resets active directory user's password.
	
	.NOTES
		Version: 1.0.0
	#>
    [CmdletBinding( DefaultParameterSetName = 'RandomCharacters' )]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [Parameter( ParameterSetName = 'Custom' )]
        [switch] $Custom,

        # [Parameter( ParameterSetName = 'PassPhrase' )]
        # [Alias( 'Phrase' )]
        # [switch] $PassPhrase,

        [Parameter( ParameterSetName = 'RandomCharacters' )]
        [Alias( 'Random' )]
        [switch] $RandomCharacters
    )

    begin {

        # variables
        $ParameterSet = $PSCmdlet.ParameterSetName
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $Properties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
            'PasswordLastSet'
        )
        $Cyan = @{
            ForegroundColor = 'Cyan'
        }
        $FgRed = @{
            ForegroundColor = 'Red'
        }

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

        Write-Host ''

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $Username = $ScriptUserObject.SamAccountName

            switch ( $ParameterSet ) {
                'Custom' { 
                    $Password = Read-Host -AsSecureString "Enter new password for ${Username}"
                }
                'RandomCharacters' {

                    $PlainTextPassword = Get-RandomPassword 30
                    $ConvertParams = @{
                        String      = $PlainTextPassword
                        AsPlainText = $true
                        Force       = $true
                    }
                    $Password = ConvertTo-SecureString @ConvertParams

                    Write-Host @Green "`n${UserEmail} new password:"
                    # Console WriteLine prevents password from bring recorded in transcripts
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
            Write-Host @Cyan "`nGetting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $Properties
                Server     = $env:ComputerName
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add($NewObject)
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
            Write-Host @FgRed "Azure sync isn't running on this server. Force sync, or duplicate actions in M365."
        }
    }
}


