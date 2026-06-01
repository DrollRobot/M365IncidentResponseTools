function Show-IRTMailboxAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('MailboxAccess', 'ShowAccess', 'ShowFullAccess')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            # show users who have access to target mailbox
            Write-IRT "Showing users who have access to ${UserEmail}"
            $Properties = @(
                'User'
                'AccessRights'
                'IsInherited'
                'InheritanceType'
            )
            $MailboxPermissions = Get-MailboxPermission -Identity $UserEmail
            $MailboxPermissions | Format-Table $Properties -AutoSize
        }
    }
}
