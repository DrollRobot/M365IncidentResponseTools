New-Alias -Name 'MailboxAccess' -Value 'Show-MailboxAccess' -Force
New-Alias -Name 'ShowAccess' -Value 'Show-MailboxAccess' -Force
New-Alias -Name 'ShowFullAccess' -Value 'Show-MailboxAccess' -Force

function Show-MailboxAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName

        $Blue = @{ ForegroundColor = 'Blue' }
        $Red = @{ ForegroundColor = 'Red' }

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-IRTUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-Host @Red "${Function}: No user objects passed or found in global variables."
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "No -UserObject argument used, no `$Global:IRT_UserObjects present."
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
                Write-Host @Red "${Function}: No mailbox for ${UserEmail}"
                continue
            }

            # show users who have access to target mailbox
            Write-Host @Blue "Showing users who have access to ${UserEmail}" | Out-Host
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