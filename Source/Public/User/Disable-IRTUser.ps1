function Disable-IRTUser {
    <#
	.SYNOPSIS
	Disable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('DisableUser', 'DisableUsers', 'Lock-GraphUsers',
        'LockUser', 'LockUsers', 'Lock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-UserEnabled @Params
}