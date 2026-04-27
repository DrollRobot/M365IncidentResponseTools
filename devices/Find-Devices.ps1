New-Alias -Name 'FindDevice' -Value 'Find-Devices' -Force
New-Alias -Name 'FindDevices' -Value 'Find-Devices' -Force
New-Alias -Name 'Find-Device' -Value 'Find-Devices' -Force
function Find-Devices {
    <#
    .SYNOPSIS
    Finds devices by display name, device ID, operating system, registered owner, serial number, or other
    Entra/Intune identifiers. Creates $IRT_DeviceObjects from combined Entra + Intune device records.

    .EXAMPLE
    Find-Devices DESKTOP-ABC123
    Find-Devices -Search DESKTOP-ABC123,LAPTOP-XYZ789
    Find-Devices flast@domain.com
    Find-Devices -Search bf7573a5844f   # partial device id / Entra id / Intune id
    Find-Devices -Search SN1234567890   # serial number (Intune)

    .NOTES
    Version: 1.1.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script,
        [string] $TenantId
    )

    begin {

        # variables
        $ScriptDeviceObjects = [System.Collections.Generic.List[PsObject]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'OperatingSystem'
            'DisplayName'
            'OwnerUPN'
            'DeviceId'
        )

        # colors
        $Blue = @{ForegroundColor = 'Blue'}
        $Red = @{ForegroundColor = 'Red'}

        # get all combined device objects from cache
        $AllDevices = Request-GraphDevices -Cached
    }

    process {

        Write-Host ''

        foreach ($SearchString in $Search) {

            # match against flat convenience properties, Entra sub-object, and Intune sub-object
            $MatchingDevices = $AllDevices | Where-Object {
                $_.DisplayName     -match $SearchString -or
                $_.DeviceId        -match $SearchString -or
                $_.Entra.Id        -match $SearchString -or
                $_.Intune.Id       -match $SearchString -or
                $_.OperatingSystem -match $SearchString -or
                $_.OwnerUPN        -match $SearchString -or
                # Entra registered-owner display names (not always in OwnerUPN)
                ($_.Entra -and (
                    $_.Entra.RegisteredOwners | Where-Object {
                        $_.AdditionalProperties['displayName'] -match $SearchString
                    }
                )) -or
                # Intune-specific identifiers
                ($_.Intune -and (
                    $_.Intune.DeviceName   -match $SearchString -or
                    $_.Intune.SerialNumber -match $SearchString -or
                    $_.Intune.EmailAddress -match $SearchString -or
                    $_.Intune.Imei         -match $SearchString
                ))
            }

            if (($MatchingDevices | Measure-Object).Count -eq 1) {
                
                if (-not $Script) {

                    # show device info
                    Write-Host @Blue "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                }

                # add device to array
                $ScriptDeviceObjects.Add( ( $MatchingDevices | Select-Object -First 1 ) )
            }
            elseif (($MatchingDevices | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    # show device info
                    Write-Host @Blue "Showing results for search: ${SearchString}"
                    $MatchingDevices | Format-Table $DisplayProperties
                    Write-Host @Red 'Multiple devices found. Refine search.'
                }
            }
            else {
                if (-not $Script) {
                    Write-Host @Red "$SearchString not found. Try a different search."
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return @($ScriptDeviceObjects)
        }

        if ( $ScriptDeviceObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}DeviceObjects"
                Value = @($ScriptDeviceObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-Host @Blue "`nCreated `$IRT_${VarPrefix}DeviceObjects"

            if ( $ScriptDeviceObjects.Count -gt 1 ) {
                $ScriptDeviceObjects | Format-Table $DisplayProperties
            }
        }        
    }
}
