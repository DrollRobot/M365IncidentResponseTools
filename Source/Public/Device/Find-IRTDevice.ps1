function Find-IRTDevice {
    <#
    .SYNOPSIS
    Finds devices by display name, device ID, operating system, registered owner, serial number,
    or other Entra/Intune identifiers. Creates $IRT_DeviceObjects from combined Entra + Intune
    device records.

    .DESCRIPTION
    Searches the cached combined Entra + Intune device records for one or more search strings.
    Each string is matched against DisplayName, DeviceId, OperatingSystem, OwnerUPN, the Entra
    object id, the Entra registered-owner display names, and the Intune object id, device name,
    serial number, email address, and IMEI.

    Matching devices are stored in $Global:IRT_DeviceObjects. Use -VarPrefix to change the
    variable name (e.g. 'Admin' > $Global:IRT_AdminDeviceObjects). A search that returns more
    than one device is reported but contributes nothing unless -AllMatches is used. Use -Script
    to suppress global side effects and return the objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER FromClipboard
    Read one search query per line from the clipboard instead of supplying -Search. Each
    non-empty line is treated as a separate search string. Mutually exclusive with -Search.

    .PARAMETER VarPrefix
    Optional prefix inserted after 'IRT_' in the global variable name
    (e.g. 'Admin' > $Global:IRT_AdminDeviceObjects). Useful when working with multiple sets of
    devices simultaneously.

    .PARAMETER Script
    Return objects directly and suppress console output and global variable assignment. Use when
    calling from scripts or the playbook.

    .PARAMETER AllMatches
    Keep every device returned by a search instead of only searches that match exactly one
    device. Results are deduplicated by Entra object id.

    .EXAMPLE
    ```powershell
    Find-IRTDevice DESKTOP-ABC123
    ```
    Finds devices matching 'DESKTOP-ABC123' and creates $IRT_DeviceObjects.

    .EXAMPLE
    ```powershell
    Find-IRTDevice -Search DESKTOP-ABC123,LAPTOP-XYZ789
    ```
    Searches for two devices, one query per string.

    .EXAMPLE
    ```powershell
    Find-IRTDevice -Search SN1234567890
    ```
    Searches by Intune serial number. Partial device, Entra, and Intune ids also match.

    .EXAMPLE
    ```powershell
    $Devices = Find-IRTDevice -Search 'DESKTOP-ABC123' -AllMatches -Script
    ```
    Returns every matching device object without setting globals or writing to the console.

    .EXAMPLE
    ```powershell
    Find-IRTDevice -FromClipboard
    ```
    Reads the clipboard and searches for each line as a separate query.

    .OUTPUTS
    System.Management.Automation.PSObject[]

    .NOTES
    Version: 1.3.1
    1.3.1 - Added missing help sections so PlatyPS can generate the command page.
    1.3.0 - Added -FromClipboard to read one search query per clipboard line.
    1.2.0 - Added -AllMatches to collect all matching devices and deduplicate results.
    #>
    [Alias('FindDevice', 'FindDevices')]
    [OutputType([psobject[]])]
    [CmdletBinding( DefaultParameterSetName = 'Search' )]
    param (
        [Parameter( ParameterSetName = 'Search', Position = 0, Mandatory )]
        [string[]] $Search,
        [Parameter( ParameterSetName = 'Clipboard', Mandatory )]
        [switch] $FromClipboard,
        [string] $VarPrefix,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        if ( $FromClipboard ) {
            $Search = Get-IRTClipboardSearch
        }
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
