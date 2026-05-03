function Remove-MailboxFullAccess {
    <#
	.SYNOPSIS
	Remove full access to the target user's mailbox

	.NOTES
	Version: 1.0.0
	#>
    [Alias('RemoveFullAccess')]
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


