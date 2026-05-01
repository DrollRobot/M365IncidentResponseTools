New-Alias -Name 'RevokeSessions' -Value 'Revoke-UserSession' 
New-Alias -Name 'Revoke-UserSessions' -Value 'Revoke-UserSession' 
function Revoke-UserSession {
    <#
	.SYNOPSI
	Revoke sessions for selected user. (NOTE: There is currently no way to revoke MFA sessions through graph APIs. It must be done in the Entra/Azure web portal.)

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    begin {

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

        # variables

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        $Red = @{ ForegroundColor = 'Red' }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserPrincipalName = $ScriptUserObject.UserPrincipalName

            Write-Host @Blue "`nRevoking user sessions for: ${UserPrincipalName}" | Out-Host
            $Result = ( Revoke-MgUserSignInSession -UserId $ScriptUserObject.Id ).Value

            if ( $Result -eq $true ) {
                Write-Host @Blue "`nSessions revoked." | Out-Host
            }
            else {
                Write-Host @Red "`nRevoking sessions failed." | Out-Host
            }
        }
    }
}


