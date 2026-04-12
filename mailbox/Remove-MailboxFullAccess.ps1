New-Alias -Name 'RemoveFullAccess' -Value 'Remove-MailboxFullAccess' -Force
function Remove-MailboxFullAccess {
    <#
	.SYNOPSIS
	Remove full access to the target user's mailbox
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [string] $GrantAccessTo
    )

    begin {}

    process {

        $Params = @{
            Remove = $true
        }
        if ($UserObjects) {
            $Params['UserObjects'] = $UserObjects
        }
        if ($GrantAccessTo) {
            $Params['GrantAccessTo'] = $GrantAccessTo
        }
        Grant-MailboxFullAccess @Params
    }
}



