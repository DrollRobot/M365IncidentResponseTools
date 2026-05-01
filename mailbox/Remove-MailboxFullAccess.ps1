New-Alias -Name 'RemoveFullAccess' -Value 'Remove-MailboxFullAccess' 
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
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo
    )

    begin {}

    process {

        $Params = @{
            Remove = $true
        }
        if ($UserObject) {
            $Params['UserObject'] = $UserObject
        }
        if ($GrantAccessTo) {
            $Params['GrantAccessTo'] = $GrantAccessTo
        }
        Grant-MailboxFullAccess @Params
    }
}



