New-Alias -Name 'UnlockUser' -Value 'Unlock-GraphUsers' -Force
New-Alias -Name 'UnlockUsers' -Value 'Unlock-GraphUsers' -Force
New-Alias -Name 'Unlock-GraphUser' -Value 'Unlock-GraphUsers' -Force
function Unlock-GraphUsers {
    <#
	.SYNOPSIS
	Unlock/Enable user account. Wrapper for Lock-GraphUser
	
	.NOTES
	Version: 1.0.2
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObjects
    )

    $Params = @{
        Unlock = $true
    }
    if ( $UserObjects ) {
        $Params['UserObjects'] = $UserObjects
    }
    
    Lock-GraphUser @Params
}