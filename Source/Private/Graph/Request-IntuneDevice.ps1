function Request-IntuneDevice {
    <#
    .SYNOPSIS
    Requests all managed devices from Intune (Microsoft Graph).
    Returns $null when the tenant has no Intune license or the caller lacks permission.

    .NOTES
    Version: 1.1.0
    #>
    [OutputType([System.Object[]])]
    [CmdletBinding()]
    param ()

    begin {
        Import-IRTModule -Name 'Microsoft.Graph.DeviceManagement', 'PSFramework'
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
            return $null
        }
    }
}
