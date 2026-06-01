function Enable-IRTDevice {
    <#
	.SYNOPSIS
	Enable Entra device account(s).

	.NOTES
	Version: 1.0.0
	#>
    [Alias('EnableDevice', 'EnableDevices')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $DeviceObject ) {
        $Params['DeviceObject'] = $DeviceObject
    }

    Set-IRTDeviceEnabled @Params
}
