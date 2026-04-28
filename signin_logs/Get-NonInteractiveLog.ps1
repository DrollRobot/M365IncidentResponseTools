New-Alias -Name 'NILog' -Value 'Get-NonInteractiveLog' -Force
New-Alias -Name 'NILogs' -Value 'Get-NonInteractiveLog' -Force
New-Alias -Name 'GetNILog' -Value 'Get-NonInteractiveLog' -Force
New-Alias -Name 'GetNILogs' -Value 'Get-NonInteractiveLog' -Force
function Get-NonInteractiveLog {
	<#
	.SYNOPSIS
	A wrapper for Get-SignInLog.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [int] $Days,
        [boolean] $Beta = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Script = $false,
        [boolean] $Open = $true
    )

    begin {

        # variables
        $Params = @{
            UserObjects = $UserObject
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
        Get-SignInLog @Params
    }
}