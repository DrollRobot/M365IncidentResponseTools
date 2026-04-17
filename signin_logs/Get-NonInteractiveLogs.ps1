New-Alias -Name 'NILog' -Value 'Get-NonInteractiveLogs' -Force
New-Alias -Name 'NILogs' -Value 'Get-NonInteractiveLogs' -Force
New-Alias -Name 'GetNILog' -Value 'Get-NonInteractiveLogs' -Force
New-Alias -Name 'GetNILogs' -Value 'Get-NonInteractiveLogs' -Force
New-Alias -Name 'Get-NonInteractiveLog' -Value 'Get-NonInteractiveLogs' -Force
function Get-NonInteractiveLogs {
	<#
	.SYNOPSIS
	A wrapper for Get-SignInLogs.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [int] $Days,
        [boolean] $Beta = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Script = $false,
        [boolean] $Open = $true
    )

    begin {

        # variables
        $Params = @{
            UserObjects = $UserObjects
            NonInteractive = $true
            Days = $Days
            Xml = $Xml
            Beta = $Beta
            Open = $Open
        }
        if ( $Script ) {
            $Params['Script'] = $true
        }
	}

    process {

        # run command
        Get-SignInLogs @Params
    }
}