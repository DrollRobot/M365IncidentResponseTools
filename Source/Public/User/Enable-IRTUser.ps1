function Enable-IRTUser {
    <#
	.SYNOPSIS
	Enable graph user account(s).

	.NOTES
	Version: 2.0.0
	#>
    [Alias('EnableUser', 'EnableUsers', 'Unlock-GraphUsers',
        'UnlockUser', 'UnlockUsers', 'Unlock-GraphUser')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-UserEnabled @Params
}