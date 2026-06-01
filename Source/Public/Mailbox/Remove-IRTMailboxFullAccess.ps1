function Remove-IRTMailboxFullAccess {
    <#
	.SYNOPSIS
	Remove full access to the target user's mailbox

	.NOTES
	Version: 1.0.0
	#>
    [Alias('RemoveFullAccess')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo
    )

    begin {
        Update-IRTToken -Service 'Exchange'
    }

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
        $Target = if ($UserObject) {
            ($UserObject | Select-Object -First 1).UserPrincipalName
        } else {
            $GrantAccessTo
        }
        if ($PSCmdlet.ShouldProcess($Target, 'Remove full mailbox access')) {
            Add-IRTMailboxFullAccess @Params
        }
    }
}
