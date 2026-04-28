function Request-IntuneDevice {
    <#
    .SYNOPSIS
    Requests all managed devices from Intune (Microsoft Graph). Caches in global variables.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [switch] $Cached
    )

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_IntuneDevices' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                return $Global:IRT_IntuneDevices
            }
        }

        # query graph - throws on no permission / no Intune license so callers can catch
        $Objects = @( Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop )

        # cache flat array
        $Global:IRT_IntuneDevices = $Objects

        # cache lookup by AzureADDeviceId (skips placeholder all-zeros GUIDs)
        $Global:IRT_IntuneDevicesByEntraId = @{}
        foreach ( $o in $Objects ) {
            if ( $o.AzureADDeviceId -and $o.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000' ) {
                $Global:IRT_IntuneDevicesByEntraId[$o.AzureADDeviceId] = $o
            }
        }

        return $Global:IRT_IntuneDevices
    }
}
