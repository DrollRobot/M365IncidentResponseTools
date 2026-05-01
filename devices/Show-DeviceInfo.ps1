New-Alias -Name 'ShowDevice'  -Value 'Show-DeviceInfo' 
New-Alias -Name 'ShowDevices' -Value 'Show-DeviceInfo' 

#region Show-DeviceInfo
function Show-DeviceInfo {
    <#
    .SYNOPSIS
    Displays Entra and Intune device properties for combined device objects produced by Find-Device.

    .NOTES
    Version: 1.1.0
    #>
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

        # colors
        $Blue   = @{ForegroundColor = 'Blue'}
        $Red    = @{ForegroundColor = 'Red'}
        $Yellow = @{ForegroundColor = 'Yellow'}
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

                    Write-Host @Blue "`nShowing Entra device properties for: ${DeviceName}"
                    $FullEntraDevice | Show-GraphDeviceTree | Out-Host
                }
                catch {
                    Write-Host @Red "`nFailed to get Entra device object: $($_.Exception.Message)"
                }
            }
            else {
                Write-Host @Yellow "`nNo Entra record for: ${DeviceName}"
            }

            # --- Intune device ---
            if ( $IntuneId ) {
                try {
                    $FullIntuneDevice = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $IntuneId -ErrorAction Stop

                    Write-Host @Blue "`nShowing Intune device properties for: ${DeviceName}"
                    $FullIntuneDevice | Format-Tree -Depth 5 -OmitNullOrEmpty | Out-Host
                }
                catch {
                    Write-Host @Red "`nFailed to get Intune device object: $($_.Exception.Message)"
                }
            }
            else {
                Write-Host @Yellow "`nDevice is not enrolled in Intune."
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