function Reset-IRTAdUserPassword {
    <#
    .SYNOPSIS
    Resets an Active Directory user's password.

    .DESCRIPTION
    Resets the on-premises AD password for one or more users. Exactly one of the three
    password mode switches must be specified:

      -RandomCharacters     Generates a random password (default length: 30 characters)
                            and sets it immediately. The new password is printed to the
                            console via [Console]::WriteLine so it is NOT captured in
                            PowerShell transcripts.

      -Custom               Prompts the operator to enter a password interactively via
                            Read-Host -AsSecureString. The password is set immediately.

      -ForceChangePasswordNextSignIn
                            Does not set a new password. Instead, sets
                            ChangePasswordAtLogon = $true on the account, which forces
                            the user to choose a new password on their next login.

    If no -UserObjects is supplied, the function falls back to the global session objects
    stored via Get-AdGlobalUserObject. An error is thrown if neither source yields a user.

    All changes and the readback go to one writable domain controller: this computer if it
    is one, otherwise a discovered DC. So this runs from any device with the
    ActiveDirectory module, not only a DC. After the reset,
    updated account properties are retrieved and displayed as a table, and AD replication
    is pushed from that DC via repadmin (skipped with a warning if repadmin isn't
    installed). If the ADSync service is local, an Azure AD delta sync is started.

    Supports -WhatIf and -Confirm via SupportsShouldProcess.

    .PARAMETER UserObjects
    One or more AD user objects whose passwords will be reset. Falls back to
    global session objects if omitted.

    .PARAMETER RandomCharacters
    Generates a random password of the specified length (default: 30 characters) and
    applies it to the account. The password is written directly to the console (bypassing
    transcript logging) so it can be recorded securely by the operator.

    .PARAMETER Length
    The length of the randomly generated password. Only valid with -RandomCharacters.
    Must be at least 4 characters. Defaults to 30.

    .PARAMETER Custom
    Prompts the operator to enter a custom password via Read-Host -AsSecureString.

    .PARAMETER ForceChangePasswordNextSignIn
    Sets ChangePasswordAtLogon = $true on the account without changing the current
    password. The user will be required to set a new password on their next sign-in.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -RandomCharacters
    ```
    Generates and sets a random password for the user in the global session.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters
    ```
    Resets the password for a specific user object using a random password.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -Custom
    ```
    Prompts the operator to enter a custom password for the global session user.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -UserObjects $User -ForceChangePasswordNextSignIn
    ```
    Forces the user to set a new password on their next sign-in, without changing
    the current password.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -RandomCharacters -Length 48
    ```
    Resets the password using a random 48-character password.

    .EXAMPLE
    ```powershell
    Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters -WhatIf
    ```
    Shows what would happen without actually resetting the password.

    .OUTPUTS
    None. Updated user properties are displayed as a formatted table in the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Targets one writable DC (this computer if it is one, otherwise a discovered
            DC), so it no longer needs to run on a DC. Replication is pushed from that DC.
    1.1.0 - Added ForceChangePasswordNextSignIn parameter set. Removed default parameter
            set; operator must now explicitly choose a password mode. Added -Length
            parameter. Renamed to Reset-IRTAdUserPassword.
    1.0.0 - Initial version as Reset-AdUserPassword.
    #>
    [Alias('ResetAdPassword', 'ResetAdPasswords', 'Reset-AdPassword')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0)]
        [Alias('UserObject')]
        [psobject[]] $UserObjects,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [Alias('Random')]
        [switch] $RandomCharacters,

        [Parameter(ParameterSetName = 'RandomCharacters')]
        [ValidateRange(4, [int]::MaxValue)]
        [int] $Length = 30,

        [Parameter(ParameterSetName = 'Custom')]
        [switch] $Custom,

        [Parameter(ParameterSetName = 'ForceChangePasswordNextSignIn')]
        [switch] $ForceChangePasswordNextSignIn
    )

    begin {
        $OutputObjects = [System.Collections.Generic.List[PsObject]]::new()
        $UserProperties = @(
            'Enabled'
            'DisplayName'
            'SamAccountName'
            'UserPrincipalName'
            'PasswordLastSet'
        )

        # if not passed directly, find global
        if (-not $UserObjects -or $UserObjects.Count -eq 0) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if (-not $ScriptUserObjects) {
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

        # make every change on one writable DC, so the readback sees it and replication
        # pushes it from where it was made
        $DomainController = Get-TargetDomainController

        Write-IRT ''

        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $Username = $ScriptUserObject.SamAccountName
            $ResetPassword = $true

            switch ($true) {
                $Custom {
                    $Password = Read-Host -AsSecureString "Enter new password for ${Username}"
                    break
                }
                $ForceChangePasswordNextSignIn {
                    $ResetPassword = $false
                    $ShouldChange = $PSCmdlet.ShouldProcess($Username,
                        'Force password change at next sign-in')
                    if ($ShouldChange) {
                        $SetParams = @{
                            Identity              = $ScriptUserObject
                            ChangePasswordAtLogon = $true
                            Server                = $DomainController
                        }
                        Set-ADUser @SetParams
                    }
                    break
                }
                $RandomCharacters {
                    $PlainTextPassword = Get-RandomPassword $Length
                    $ConvertParams = @{
                        String      = $PlainTextPassword
                        AsPlainText = $true
                        Force       = $true
                    }
                    $Password = ConvertTo-SecureString @ConvertParams
                    Write-IRT "${Username} new password:"
                    # Console WriteLine prevents password from being recorded in logs/transcripts
                    [Console]::WriteLine($PlainTextPassword)
                }
            }

            if ($ResetPassword) {
                $ResetParams = @{
                    Identity    = $ScriptUserObject
                    Reset       = $true
                    NewPassword = $Password
                    Server      = $DomainController
                }
                if ($PSCmdlet.ShouldProcess($Username, 'Reset password')) {
                    Set-AdAccountPassword @ResetParams
                }
            }

            # get new object to show result
            Write-IRT "Getting updated user info."
            $Params = @{
                Identity   = $ScriptUserObject
                Properties = $UserProperties
                Server     = $DomainController
            }
            $NewObject = Get-AdUser @Params
            $OutputObjects.Add($NewObject)
        }

        # show results
        $OutputObjects | Format-Table $UserProperties

        Push-AdReplication -Server $DomainController

        # push azure sync, if on this server
        $SyncService = Get-Service -Name "adsync" -ErrorAction SilentlyContinue
        if ($SyncService) {
            Write-IRT "Pushing Azure sync."
            Start-ADSyncSyncCycle -PolicyType Delta
        }
        else {
            $Msg = "Azure sync isn't running on this server. " +
            "Run Push-IRTAdSync, or duplicate actions in M365."
            Write-IRT $Msg -Level Error
        }
    }
}
