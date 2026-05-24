function Remove-IRTDevice {
    <#
	.SYNOPSIS
	Permanently delete Entra and Intune device(s). Requires the user to type each
	device's display name as confirmation before deletion proceeds.

	.DESCRIPTION
	Removes the Entra directory object (Remove-MgDevice) and, when the device is
	Intune-enrolled, the Intune managed device (Remove-MgDeviceManagementManagedDevice)
	for each supplied device object.

	Before any deletion the user is shown the device's DisplayName, Entra ID,
	Intune ID (or '(not enrolled)'), and OS. The user must then type the
	DisplayName exactly to proceed. Use -Force to bypass this prompt (e.g. in
	automated remediation scripts). -WhatIf and -Confirm are also supported.

	.PARAMETER DeviceObject
	One or more combined Entra+Intune device objects as returned by Find-IRTDevice
	or stored in $IRT_DeviceObjects. If omitted, $IRT_DeviceObjects is used.

	.PARAMETER Force
	Skip the manual name-confirmation prompt. The SupportsShouldProcess gate
	(-WhatIf / -Confirm) still applies.

	.EXAMPLE
	Remove-IRTDevice
	Operates on $IRT_DeviceObjects. Prompts for name confirmation before each deletion.

	.EXAMPLE
	Find-IRTDevice DESKTOP-ABC123
	Remove-IRTDevice
	Find a device by name, then delete it (with confirmation prompt).

	.EXAMPLE
	Remove-IRTDevice -Force -WhatIf
	Show what would be deleted without prompting or actually deleting anything.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('DeleteDevice', 'DeleteDevices', 'RemoveDevice', 'RemoveDevices')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [switch] $Force
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
    }

    process {

        foreach ( $ScriptDeviceObject in $ScriptDeviceObjects ) {

            $EntraId     = $ScriptDeviceObject.Entra?.Id
            $IntuneId    = $ScriptDeviceObject.Intune?.Id
            $DisplayName = $ScriptDeviceObject.DisplayName

            if ( -not $EntraId ) {
                Write-IRT "No Entra device object found for: $DisplayName. Skipping." -Level Warn
                continue
            }

            Write-IRT ''
            Write-IRT "Device to delete:" -Level Warn
            Write-IRT "  Display Name : $DisplayName"
            Write-IRT "  Entra ID     : $EntraId"
            Write-IRT "  Intune ID    : $(if ($IntuneId) { $IntuneId } else { '(not enrolled)' })"
            Write-IRT "  OS           : $($ScriptDeviceObject.OperatingSystem)"
            Write-IRT ''

            # --- manual name confirmation (unless -Force) ---
            if ( -not $Force ) {
                $Confirmation = Read-Host "Type the device name exactly to confirm deletion (or press Enter to skip)"

                if ( $Confirmation -ne $DisplayName ) {
                    Write-IRT "Confirmation did not match '$DisplayName'. Skipping." -Level Warn
                    continue
                }
            }

            # --- SupportsShouldProcess gate (-WhatIf / -Confirm) ---
            if ( $PSCmdlet.ShouldProcess($DisplayName, 'Permanently delete device') ) {

                # delete Intune managed device first (if enrolled)
                if ( $IntuneId ) {
                    Write-IRT "Deleting Intune device: $DisplayName"
                    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneId
                    Write-IRT "Intune device deleted."
                }

                # delete Entra device object
                Write-IRT "Deleting Entra device: $DisplayName"
                Remove-MgDevice -DeviceId $EntraId
                Write-IRT "Entra device deleted."
            }
        }

        Write-IRT ''
    }
}
