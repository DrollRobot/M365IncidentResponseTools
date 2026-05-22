#region Show-DeviceInfo
function Show-DeviceInfo {
    <#
    .SYNOPSIS
    Displays Entra and Intune device properties for combined device objects produced by Find-IRTDevice.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('ShowDevice', 'ShowDevices')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject
    )

    begin {

        # if not passed directly, fall back to global variable
        if ( -not $DeviceObject -or $DeviceObject.Count -eq 0 ) {
            $ScriptDeviceObjects = @( $Global:IRT_DeviceObjects )
            if ( -not $ScriptDeviceObjects -or $ScriptDeviceObjects.Count -eq 0 ) {
                throw "No device objects passed or found in global variables."
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }
    }

    process {

        foreach ($ScriptDeviceObject in $ScriptDeviceObjects) {

            $DeviceName  = $ScriptDeviceObject.DisplayName
            $EntraId     = $ScriptDeviceObject.Entra?.Id    # Entra directory object ID (null for Intune-only devices)
            $IntuneId    = $ScriptDeviceObject.Intune?.Id   # Intune managed device ID

            # --- Entra device ---
            if ( $EntraId ) {
                try {
                    $FullEntraDevice = Get-MgDevice -DeviceId $EntraId -ExpandProperty 'RegisteredOwners' -ErrorAction Stop

                    $OwnerUpn = ($FullEntraDevice.RegisteredOwners | ForEach-Object {
                        $_.AdditionalProperties['userPrincipalName']
                    }) -join ', '
                    $FullEntraDevice | Add-Member -NotePropertyName 'RegisteredOwnerUPN' -NotePropertyValue $OwnerUpn -Force

                    Write-IRT "Showing Entra device properties for: ${DeviceName}"
                    $FullEntraDevice | Show-GraphDeviceTree | Out-Host
                }
                catch {
                    Write-IRT "Failed to get Entra device object: $($_.Exception.Message)" -Level Error
                }
            }
            else {
                Write-IRT "No Entra record for: ${DeviceName}" -Level Warn
            }

            # --- Intune device ---
            if ( $IntuneId ) {
                try {
                    $FullIntuneDevice = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneId -ErrorAction Stop

                    Write-IRT "Showing Intune device properties for: ${DeviceName}"
                    $FullIntuneDevice | Format-Tree -Depth 5 -OmitNullOrEmpty | Out-Host
                }
                catch {
                    Write-IRT "Failed to get Intune device object: $($_.Exception.Message)" -Level Error
                }
            }
            else {
                Write-IRT "Device is not enrolled in Intune." -Level Warn
            }
        }
    }
}


#region Show-GraphDeviceTree
function Show-GraphDeviceTree {
    <#
    .SYNOPSIS
    Shows an Entra device object in a compact tree view.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('DeviceObjects')]
        [psobject[]] $DeviceObject,

        [int] $Depth = 10
    )

    begin {
        $Exclude = @(
            'AdditionalProperties',
            'AlternativeSecurityIds',
            'RegisteredOwners',
            'RegisteredUsers'
        )
    }

    process {
        foreach ($DeviceObjectItem in $DeviceObject) {
            if ($null -eq $DeviceObjectItem) { continue }

            $Projected = $DeviceObjectItem | Select-Object -Property * -ExcludeProperty $Exclude

            $Params = @{
                Depth           = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
