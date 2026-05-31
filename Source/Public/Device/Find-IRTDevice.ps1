function Find-IRTDevice {
    <#
    .SYNOPSIS
    Finds devices by display name, device ID, operating system, registered owner, serial number,
    or other Entra/Intune identifiers. Creates $IRT_DeviceObjects from combined Entra + Intune
    device records.

    .EXAMPLE
    Find-IRTDevice DESKTOP-ABC123
    Find-IRTDevice -Search DESKTOP-ABC123,LAPTOP-XYZ789
    Find-IRTDevice flast@domain.com
    Find-IRTDevice -Search bf7573a5844f   # partial device id / Entra id / Intune id
    Find-IRTDevice -Search SN1234567890   # serial number (Intune)

    .NOTES
    Version: 1.2.0
    1.2.0 - Added -AllMatches to collect all matching devices and deduplicate results.
    #>
    [Alias('FindDevice', 'FindDevices')]
    [OutputType([psobject[]])]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $ScriptDeviceObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'OperatingSystem'
            'DisplayName'
            'OwnerUPN'
            'DeviceId'
        )

        # get all combined device objects from cache
        $AllDevices = Request-GraphDevice -Cached
    }

    process {

        Write-IRT ''

        foreach ($SearchString in $Search) {

            # match against flat convenience properties, Entra sub-object, and Intune sub-object
            $MatchingDevices = $AllDevices | Where-Object {
                $_.DisplayName -match $SearchString -or
                $_.DeviceId -match $SearchString -or
                $_.Entra.Id -match $SearchString -or
                $_.Intune.Id -match $SearchString -or
                $_.OperatingSystem -match $SearchString -or
                $_.OwnerUPN -match $SearchString -or
                # Entra registered-owner display names (not always in OwnerUPN)
                ($_.Entra -and (
                    $_.Entra.RegisteredOwners | Where-Object {
                        $_.AdditionalProperties['displayName'] -match $SearchString
                    }
                )) -or
                # Intune-specific identifiers
                ($_.Intune -and (
                    $_.Intune.DeviceName -match $SearchString -or
                    $_.Intune.SerialNumber -match $SearchString -or
                    $_.Intune.EmailAddress -match $SearchString -or
                    $_.Intune.Imei -match $SearchString
                ))
            }

            if (($MatchingDevices | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    # show device info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                }

                $Device = $MatchingDevices | Select-Object -First 1
                if ($SeenIds.Add($Device.Entra.Id)) {
                    $ScriptDeviceObjects.Add($Device)
                }
            }
            elseif (($MatchingDevices | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    # show device info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($Device in $MatchingDevices) {
                        if ($SeenIds.Add($Device.Entra.Id)) {
                            $ScriptDeviceObjects.Add($Device)
                        }
                    }
                } elseif (-not $Script) {
                    $Msg = 'Multiple devices found. Refine search or use -AllMatches.'
                    Write-IRT $Msg -Level Error
                }
            }
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return [psobject[]]$ScriptDeviceObjects
        }

        if ( $ScriptDeviceObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}DeviceObjects"
                Value = @($ScriptDeviceObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}DeviceObjects"

            if ( $ScriptDeviceObjects.Count -gt 1 ) {
                $ScriptDeviceObjects | Format-Table $DisplayProperties
            }
        }
    }
}