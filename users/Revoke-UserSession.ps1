function Revoke-UserSession {
    <#
	.SYNOPSI
	Revoke sessions for selected user. (NOTE: There is currently no way to revoke MFA
	sessions through graph APIs. It must be done in the Entra/Azure web portal.)

	.NOTES
	Version: 1.0.0
	#>
    [Alias('RevokeSessions', 'Revoke-UserSessions')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
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
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserPrincipalName = $ScriptUserObject.UserPrincipalName

            Write-IRT "Revoking user sessions for: ${UserPrincipalName}"
            $Result = ( Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id ).Value

            if ( $Result -eq $true ) {
                Write-IRT "Sessions revoked."
            }
            else {
                Write-IRT "Revoking sessions failed." -Level Error
            }
        }
    }
}


