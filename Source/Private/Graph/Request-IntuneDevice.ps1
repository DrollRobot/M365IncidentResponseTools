function Request-IntuneDevice {
    <#
    .SYNOPSIS
    Requests all managed devices from Intune (Microsoft Graph).
    Returns $null when the tenant has no Intune license or the caller lacks permission.

    .DESCRIPTION
    Internal helper. A tenant without an Intune license rejects the managedDevices call
    with the same 403 Forbidden as a caller without permission, so the error alone cannot
    tell the two apart. After a failure, the tenant's licenses are checked. With an
    active Intune plan the failure is unexpected and is reported as an error; otherwise
    the tenant is treated as not using Intune and the failure is only logged.

    .OUTPUTS
    [object[]] - Intune managed device objects, or $null when they could not be read.

    .NOTES
    Version: 1.2.0
    1.2.0 - A failure in a tenant with an active Intune plan is reported as an error.
    #>
    [OutputType([System.Object[]])]
    [CmdletBinding()]
    param ()

    begin {
        $ImportParams = @{
            Name = @(
                'Microsoft.Graph.DeviceManagement'
                'Microsoft.Graph.Identity.DirectoryManagement'
                'PSFramework'
            )
        }
        Import-IRTModule @ImportParams

        # service plans that include Intune device management. Basic Mobility and
        # Security (INTUNE_O365) is left out on purpose.
        $IntunePlanNames = @('INTUNE_A', 'INTUNE_EDU', 'INTUNE_SMBIZ')
    }

    process {

        try {
            $Devices = @(Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop)
            Write-PSFMessage -Level 8 -Message (
                "Request-IntuneDevice: $($Devices.Count) managed device(s) returned.")
            return $Devices
        }
        catch {
            $Message = $_.Exception.Message
            Write-PSFMessage -Level 8 -Message (
                "Request-IntuneDevice: Intune unavailable or insufficient permissions: $Message")
        }

        # Decide whether the failure was expected. A license check that itself fails
        # leaves the answer unknown, so it is treated like a tenant without Intune.
        $ActivePlans = @()
        try {
            $ActivePlans = @(
                Get-MgSubscribedSku -ErrorAction Stop |
                    Where-Object { $_.CapabilityStatus -in 'Enabled', 'Warning' } |
                    ForEach-Object { $_.ServicePlans } |
                    Where-Object {
                        $_.ServicePlanName -in $IntunePlanNames -and
                        $_.ProvisioningStatus -eq 'Success'
                    }
            )
        }
        catch {
            Write-PSFMessage -Level 8 -Message (
                "Request-IntuneDevice: License check failed: $($_.Exception.Message)")
        }
        Write-PSFMessage -Level 8 -Message (
            "Request-IntuneDevice: $($ActivePlans.Count) active Intune plan(s) found.")

        if ($ActivePlans.Count -gt 0) {
            Write-IRT ('Intune is licensed in this tenant, but its devices could not be ' +
                "read, so device results leave out Intune data: $Message") -Level Error
        }
        return $null
    }
}
