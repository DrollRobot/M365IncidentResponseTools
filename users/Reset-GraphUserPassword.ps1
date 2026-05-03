function Reset-GraphUserPassword {
    <#
	.SYNOPSIS
	Resets Graph user password.

	.NOTES
	Version: 1.0.1
    1.0.1 - Updated to output password in safe way. Fixed bug preventing password reset. Updated variable names.
	#>
    [Alias('ResetPassword', 'ResetPasswords')]
    [CmdletBinding( DefaultParameterSetName = 'RandomCharacters' )]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter( ParameterSetName = 'RandomCharacters' )]
        [Alias( 'Random' )]
        [switch] $RandomCharacters,

        # [Parameter( ParameterSetName = 'PassPhrase' )]
        # [Alias( 'Phrase' )]
        # [switch] $PassPhrase,

        [Parameter( ParameterSetName = 'Custom' )]
        [switch] $Custom
    )

    begin {
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $LoopObjects = Get-IRTUserObject

            # if none found, exit
            if ( -not $LoopObjects -or $LoopObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $LoopObjects = $UserObject
        }

        # variables
        if ( $PSCmdlet.ParameterSetName -eq 'RandomCharacters' ) {
            $RandomCharacters = $true
        }
        $GetProperties = @(
            'AccountEnabled'
            'DisplayName'
            'Id'
            'LastPasswordChangeDateTime'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'LastPasswordChangeDateTime'
            'AccountEnabled'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
        )
    }

    process {

        foreach ( $LoopObject in $LoopObjects ) {

            switch ( $PSCmdlet.ParameterSetName ) {
                'Custom' {
                    $Password = Read-Host -Prompt "`nEnter new password"
                }
                'RandomCharacters' {
                    $UserEmail = $LoopObject.UserPrincipalName
                    $Password = Get-RandomPassword 30
                    Write-IRT "`n${UserEmail} new password:"
                    # Console WriteLine prevents password from bring recorded in transcripts
                    [Console]::WriteLine($Password)
                }
            }

            # create password profile and reset password
            $PasswordProfile = @{
                Password = $Password
                ForceChangePasswordNextSignIn = $false
                ForceChangePasswordNextSignInWithMfa = $false
            }
            Update-MgUser -UserId $LoopObject.Id -PasswordProfile $PasswordProfile

            # get new user object
            Write-IRT "`nGetting updated user information."
            $FullUserObject = Get-MgUser -UserId $LoopObject.Id -Property $GetProperties
            try {
                $FullUserObject.LastPasswordChangeDateTime = $FullUserObject.LastPasswordChangeDateTime.ToLocalTime()
            }
            catch {}

            # display new object
            $FullUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ( $FullUserObject.OnPremisesSyncEnabled ) {
                Write-IRT "`nUser is synced from on-premises. Reset password in local AD too!" -Level Error
            }
        }
    }
}
