function Show-AdDeviceInfo {
    <#
    .SYNOPSIS
    Displays AD computer properties.

    .DESCRIPTION
    Retrieves all properties of an on-premises AD computer object, converts every DateTime
    value to local time, and displays the result with Format-Tree. Falls back to
    $Global:IRT_DeviceObject if no -DeviceObject is passed.

    .PARAMETER DeviceObject
    One or more AD computer objects to display. Falls back to $Global:IRT_DeviceObject
    if omitted.

    .EXAMPLE
    Show-AdDeviceInfo
    Displays info for the device in $Global:IRT_DeviceObject.

    .EXAMPLE
    Show-AdDeviceInfo -DeviceObject $AdComputer
    Displays info for a specific AD computer object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ShowAdDevice', 'ShowAdDevices', 'AdDeviceInfo')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [psobject[]] $DeviceObject
    )

    begin {

        if (-not $DeviceObject -or $DeviceObject.Count -eq 0) {

            if ($Global:IRT_DeviceObject) {
                $ScriptDeviceObjects = @($Global:IRT_DeviceObject)
            }
            else {
                throw 'No device object passed and $Global:IRT_DeviceObject is not set. Run Find-AdDevice first.'
            }
        }
        else {
            $ScriptDeviceObjects = $DeviceObject
        }
    }

    process {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        $ExcludeProperty = @(
            'codePage'
            'createTimeStamp'
            'dSCorePropagationData'
            'DoesNotRequirePreAuth'
            'HomedirRequired'
            'instanceType'
            'lastLogon'
            'lastLogonTimestamp'
            'localPolicyFlags'
            'MNSLogonAccount'
            'modifyTimeStamp'
            'msDS-SupportedEncryptionTypes'
            'msDS-User-Account-Control-Computed'
            'nTSecurityDescriptor'
            'objectSid'
            'primaryGroupID'
            'PropertyCount'
            'PropertyNames'
            'sDRightsEffective'
            'SID'
            'TrustedForDelegation'
            'TrustedToAuthForDelegation'
            'uSNChanged'
            'uSNCreated'
        )

        foreach ($Device in $ScriptDeviceObjects) {

            $FullObject = $Device | Get-AdComputer -Property *

            # replace partial object in global with full object
            if ($Global:IRT_DeviceObject -and
                $Global:IRT_DeviceObject.ObjectGUID -eq $FullObject.ObjectGUID
            ) {
                $Global:IRT_DeviceObject = $FullObject
            }

            $FileTimeProperties = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@(
                    'accountExpires'
                    'badPasswordTime'
                    'lastLogon'
                    'lastLogonTimestamp'
                    'lockoutTime'
                    'pwdLastSet'
                ),
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $Props = [ordered]@{}
            foreach ($Prop in ($FullObject.PSObject.Properties | Sort-Object Name)) {
                # convert DateTime objects to local time
                if ($Prop.Value -is [DateTime]) {
                    $Props[$Prop.Name] = $Prop.Value.ToLocalTime()
                }
                # convert Int64 objects to human readable time
                elseif ($Prop.Value -is [long] -and $FileTimeProperties.Contains($Prop.Name)) {
                    if ($Prop.Value -eq 0 -or $Prop.Value -eq [Int64]::MaxValue) {
                        $Props[$Prop.Name] = 'Never'
                    }
                    else {
                        $Props[$Prop.Name] = [DateTime]::FromFileTime($Prop.Value).ToLocalTime()
                    }
                }
                else {
                    $Props[$Prop.Name] = $Prop.Value
                }
            }

            $FormatParams = @{
                Depth           = 5
                OmitNullOrEmpty = $true
                ExcludeProperty = $ExcludeProperty
            }
            [PSCustomObject]$Props | Format-Tree @FormatParams
            Write-IRT 'Note: all dates are displayed in local time.'
        }
    }
}
