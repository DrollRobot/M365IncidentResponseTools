function Disable-IRTDevice {
    <#
	.SYNOPSIS
	Disable Entra device account(s).

	.NOTES
	Version: 1.0.0
	#>
    [Alias('DisableDevice', 'DisableDevices')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $DeviceObject ) {
        $Params['DeviceObject'] = $DeviceObject
    }

    Set-IRTDeviceEnabled @Params
}