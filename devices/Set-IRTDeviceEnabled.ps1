###############################################################################
#region Disable-IRTDevice

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


###############################################################################
#region Enable-IRTDevice

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

###############################################################################
#region Set-IRTDeviceEnabled

function Set-IRTDeviceEnabled {
    <#
	.SYNOPSIS
	Set AccountEnabled property on Entra device(s). Called by Disable-IRTDevice and Enable-IRTDevice.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        # if not passed directly, find global
        if ( -not $DeviceObject -or $DeviceObject.Count -eq 0 ) {

            # get from global variables
            $ScriptDeviceObjects = @( $Global:IRT_DeviceObjects )

            # if none found, exit
            if ( -not $ScriptDeviceObjects -or $ScriptDeviceObjects.Count -eq 0 ) {
                throw "No device objects passed or found in global variables."
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }

        # variables
        $GetProperties = @(
            'accountEnabled'
            'displayName'
            'deviceId'
            'id'
            'operatingSystem'
            'operatingSystemVersion'
        )
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'DeviceId'
            'OperatingSystem'
            'Id'
        )

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
    }

    process {

        foreach ( $ScriptDeviceObject in $ScriptDeviceObjects ) {

            # get the Entra directory object ID
            $EntraId = $ScriptDeviceObject.Entra?.Id

            if ( -not $EntraId ) {
                Write-IRT "No Entra record for: $($ScriptDeviceObject.DisplayName). Skipping." -Level Warn
                continue
            }

            # disable/enable device
            Write-IRT "$($Action.TrimEnd('e'))ing device account..."
            if ($PSCmdlet.ShouldProcess($ScriptDeviceObject.DisplayName, "$Action device")) {
                Update-MgDevice -DeviceId $EntraId -AccountEnabled:$Enabled
            }

            # get updated device object
            Write-IRT "Getting updated device properties."
            $NewDeviceObject = Get-MgDevice -DeviceId $EntraId -Property $GetProperties

            # display updated object
            $NewDeviceObject | Format-Table $DisplayProperties
        }
    }
}
