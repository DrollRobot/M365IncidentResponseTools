function Reset-IRTUserPassword {
    <#
    .SYNOPSIS
    Resets an Entra ID user's password.

    .DESCRIPTION
    Resets the password for one or more Entra ID users via the Microsoft Graph API. Exactly
    one of the three password mode switches must be specified:

      -RandomCharacters     Generates a random 30-character password and sets it immediately.
                            The new password is printed to the console via [Console]::WriteLine
                            so it is NOT captured in PowerShell transcripts.

      -Custom               Prompts the operator to enter a password interactively via
                            Read-Host. The password is set immediately with no forced
                            change on next sign-in.

      -ForceChangePasswordNextSignIn
                            Does not set a new password. Instead, sets
                            ForceChangePasswordNextSignInWithMfa = $true on the account,
                            which forces the user to choose a new password (with MFA
                            verification) on their next login.

      -ClearForceChangePasswordNextSignIn
                            Clears the force-change flag. Sets both
                            ForceChangePasswordNextSignIn and
                            ForceChangePasswordNextSignInWithMfa to $false without
                            changing the current password.

    If no -UserObject is supplied, the function falls back to the global session objects
    stored in $Global:IRT_UserObjects (populated by Get-IRTUserObject). An error is thrown
    if neither source yields a user.

    After the reset, updated account properties are retrieved and displayed as a table.
    If the user is synced from on-premises Active Directory, a warning is shown reminding
    the operator to also reset the password in the local AD.

    Supports -WhatIf and -Confirm via SupportsShouldProcess.

    .PARAMETER UserObject
    One or more Entra ID user objects whose passwords will be reset. Falls back to
    $Global:IRT_UserObjects if omitted.

    .PARAMETER RandomCharacters
    Generates a random password of the specified length (default: 30 characters) and
    applies it to the account. The password is written directly to the console (bypassing
    transcript logging) so it can be recorded securely by the operator.

    .PARAMETER Length
    The length of the randomly generated password. Only valid with -RandomCharacters.
    Must be at least 4 characters. Defaults to 30.

    .PARAMETER Custom
    Prompts the operator to enter a custom password via Read-Host. The password is applied
    immediately with ForceChangePasswordNextSignIn set to $false.

    .PARAMETER ForceChangePasswordNextSignIn
    Sets ForceChangePasswordNextSignInWithMfa = $true on the account without changing the
    current password. The user will be required to set a new password (verified with MFA)
    on their next sign-in.

    .PARAMETER ClearForceChangePasswordNextSignIn
    Clears the forced-change-on-next-sign-in flag. Sets both ForceChangePasswordNextSignIn
    and ForceChangePasswordNextSignInWithMfa to $false without changing the current password.
    Use this to undo a previous -ForceChangePasswordNextSignIn call.

    .EXAMPLE
    Reset-IRTUserPassword -RandomCharacters
    Resets the password for the user stored in the global session using a random password.
    The new password is printed to the console.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -RandomCharacters
    Resets the password for a specific user object using a random password.

    .EXAMPLE
    Reset-IRTUserPassword -Custom
    Prompts the operator to enter a custom password, then applies it to the global session user.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -ForceChangePasswordNextSignIn
    Forces the user to set a new password (with MFA) on their next sign-in, without
    changing the current password.

    .EXAMPLE
    Reset-IRTUserPassword -RandomCharacters -Length 48
    Resets the password using a random 48-character password.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -RandomCharacters -WhatIf
    Shows what would happen without actually resetting the password.

    .EXAMPLE
    Reset-IRTUserPassword -UserObject $User -ClearForceChangePasswordNextSignIn
    Clears the forced-change flag on the user's account.

    .OUTPUTS
    None. Updated user properties are displayed as a formatted table in the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Added ClearForceChangePasswordNextSignIn parameter set to undo the force-change flag.
    1.1.0 - Added ForceChangePasswordNextSignIn parameter set. Removed default parameter set;
            operator must now explicitly choose a password mode. Renamed to Reset-IRTUserPassword.
    1.0.1 - Updated to output password in safe way. Fixed bug preventing password reset.
            Updated variable names.
    #>
    [Alias('ResetPassword', 'ResetPasswords')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [Alias('Random')]
        [switch] $RandomCharacters,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [ValidateRange(4, [int]::MaxValue)]
        [int] $Length = 30,

        # [Parameter(ParameterSetName = 'PassPhrase')] # FIXME this would be cool, right?
        # [Alias('Phrase')]
        # [switch] $PassPhrase,

        [Parameter(ParameterSetName = 'Custom')]
        [switch] $Custom,

        [Parameter(ParameterSetName = 'ForceChangePasswordNextSignIn')]
        [switch] $ForceChangePasswordNextSignIn,

        [Parameter(ParameterSetName = 'ClearForceChangePasswordNextSignIn')]
        [Alias('UndoForceChangePasswordNextSignIn')]
        [switch] $ClearForceChangePasswordNextSignIn
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

        foreach ($LoopObject in $LoopObjects) {

            switch ($true) {
                $Custom {
                    $Password = Read-Host -Prompt "Enter new password"
                    $PasswordProfile = @{
                        Password = $Password
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                    break
                }
                $ForceChangePasswordNextSignIn {
                    $PasswordProfile = @{
                        ForceChangePasswordNextSignInWithMfa = $true
                    }
                    break
                }
                $ClearForceChangePasswordNextSignIn {
                    $PasswordProfile = @{
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                    break
                }
                $RandomCharacters {
                    # RandomCharacters
                    $UserEmail = $LoopObject.UserPrincipalName
                    $Password = Get-RandomPassword $Length
                    Write-IRT "${UserEmail} new password:"
                    # Console WriteLine prevents password from being recorded in transcripts
                    [Console]::WriteLine($Password)
                    $PasswordProfile = @{
                        Password = $Password
                        ForceChangePasswordNextSignIn = $false
                        ForceChangePasswordNextSignInWithMfa = $false
                    }
                }
            }

            # create password profile and reset password
            if ($PSCmdlet.ShouldProcess($LoopObject.UserPrincipalName, 'Reset password')) {
                Update-MgUser -UserId $LoopObject.Id -PasswordProfile $PasswordProfile
            }

            # get new user object
            Write-IRT "Getting updated user information."
            $FullUserObject = Get-MgUser -UserId $LoopObject.Id -Property $GetProperties
            try {
                $FullUserObject.LastPasswordChangeDateTime =
                    $FullUserObject.LastPasswordChangeDateTime.ToLocalTime()
            }
            catch {}

            # display new object
            $FullUserObject | Format-Table $DisplayProperties

            # warn user if onpremsynced
            if ( $FullUserObject.OnPremisesSyncEnabled ) {
                $Msg = 'User is synced from on-premises. Reset password in local AD too!'
                Write-IRT $Msg -Level Error
            }
        }
    }
}
