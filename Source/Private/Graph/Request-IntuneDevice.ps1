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

    process {

        try {
            return @(Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop)
        }
        catch {
            $Message = $_.Exception.Message
            Write-Verbose "Intune not available or insufficient permissions: $Message"
            return $null
        }
    }
}