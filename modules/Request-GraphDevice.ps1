function Request-GraphDevice {
    <#
	.SYNOPSIS
    Requests Entra and Intune devices from Microsoft Graph.
    Builds combined device objects and caches them.

    Combined objects expose a flat set of convenience properties
    (DisplayName, DeviceId, OwnerUPN, etc.)
    plus an .Entra property (raw Graph device object) and an .Intune property
    (raw Intune managed-device object, or $null when the device is not enrolled
    / the tenant does not use Intune).

    Devices that appear only in Intune (no matching Entra record) are included with .Entra = $null.

	.NOTES
	Version: 2.0.0
	#>
    [OutputType([System.Object[]], [hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyid','none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = (Get-Date).ToString($FileNameDateFormat)
    }

    process {

        # return cached data if available
        if ($Cached) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Devices' -ErrorAction SilentlyContinue
            if ($Variable) {
                switch ($Return) {
                    'objects'   {return $Global:IRT_Devices}
                    'tablebyid' {return $Global:IRT_DevicesById}
                    'none'      {return}
                }
            }
        }

        # get client domain name
        $DomainName = Get-IRTDefaultDomain

        # --- Entra devices ---
        Write-Verbose "${FunctionName}: Get-MgDevice $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $EntraDevices = Get-MgDevice -All -ExpandProperty 'RegisteredOwners'

        # --- Intune devices (optional - skipped when not licensed / no permission) ---
        $IntuneDevices   = Request-IntuneDevice   # returns $null when Intune is unavailable
        $TenantHasIntune = $null -ne $IntuneDevices

        # build local lookup keyed by AzureADDeviceId for the Entra-Intune join
        $IntuneDevicesByEntraId = @{}
        if ($TenantHasIntune) {
            foreach ($Device in $IntuneDevices) {
                if ($Device.AzureADDeviceId -and
                    $Device.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000'
                ) {
                    $IntuneDevicesByEntraId[$Device.AzureADDeviceId] = $Device
                }
            }
        }

        # --- Build combined objects ---
        $CombinedObjects = [System.Collections.Generic.List[PSObject]]::new()
        $SeenIntuneIds   = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($EntraDevice in $EntraDevices) {

            $OwnerUpn = ($EntraDevice.RegisteredOwners | ForEach-Object {
                $_.AdditionalProperties['userPrincipalName']
            }) -join ', '

            $IntuneDevice = $TenantHasIntune ?
                $IntuneDevicesByEntraId[$EntraDevice.DeviceId] : $null
            if ($IntuneDevice) {[void]$SeenIntuneIds.Add($IntuneDevice.Id)}

            $Combined = [PSCustomObject]@{
                DisplayName     = $EntraDevice.DisplayName
                DeviceId        = $EntraDevice.DeviceId   # AAD device GUID - links Entra, Intune
                OperatingSystem = $EntraDevice.OperatingSystem
                OwnerUPN        = $OwnerUpn
                AccountEnabled  = $EntraDevice.AccountEnabled
                Entra           = $EntraDevice
                Intune          = $IntuneDevice
            }
            $CombinedObjects.Add($Combined)
        }

        # --- Intune-only devices (managed but no Entra record, e.g. some BYOD scenarios) ---
        if ($TenantHasIntune) {
            foreach ($IntuneDevice in $IntuneDevices) {
                if ($SeenIntuneIds.Contains($IntuneDevice.Id)) { continue }

                $AadId = ($IntuneDevice.AzureADDeviceId -and
                    $IntuneDevice.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000') ?
                    $IntuneDevice.AzureADDeviceId : $null

                $Combined = [PSCustomObject]@{
                    DisplayName     = $IntuneDevice.DeviceName
                    DeviceId        = $AadId
                    OperatingSystem = $IntuneDevice.OperatingSystem
                    OwnerUPN        = $IntuneDevice.UserPrincipalName
                    AccountEnabled  = $null
                    Entra           = $null
                    Intune          = $IntuneDevice
                }
                $CombinedObjects.Add($Combined)
            }
        }

        $Objects = @($CombinedObjects)

        # store in global variables
        $Global:IRT_Devices = $Objects
        $Global:IRT_DevicesById = [hashtable]::Synchronized(@{})
        foreach ( $Device in $Objects ) {
            if ( $Device.DeviceId ) { $Global:IRT_DevicesById[$Device.DeviceId] = $Device }
        }

        # export to file
        if ($Xml) {
            $FileName = "Devices_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            Write-Verbose "${FunctionName}: Export-Clixml $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
            $Objects | Export-Clixml -Depth 8 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects'   {return $Global:IRT_Devices}
            'tablebyid' {return $Global:IRT_DevicesById}
            'none'      {return}
        }
    }
}


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
