function Find-IRTAdDevice {
    <#
    .SYNOPSIS
    Finds a local AD computer by Name, DNSHostName, SamAccountName, Description,
    or ObjectGUID.

    .DESCRIPTION
    Searches Active Directory for computers matching one or more search strings. The search
    is applied across Name, DNSHostName, SamAccountName, Description, and ObjectGUID.

    If a single computer is found, the full AD object is retrieved and stored in
    $Global:IRT_DeviceObject. Use -VarPrefix to change the variable name
    (e.g. 'Target' > $Global:IRT_TargetDeviceObject). For multiple matches the results are
    displayed but no global is set. Use -Script to suppress global side effects and
    return objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER VarPrefix
    Optional prefix inserted after 'IRT_' in the global variable name
    (e.g. 'Target' > $Global:IRT_TargetDeviceObject). Useful when working with multiple
    devices simultaneously.

    .PARAMETER Script
    Return objects directly and suppress global variable assignment. Use when calling from
    scripts or the playbook.

    .EXAMPLE
    Find-IRTAdDevice DESKTOP-ABC123
    Finds computers matching 'DESKTOP-ABC123' and sets the global device object if exactly
    one match.

    .EXAMPLE
    Find-IRTAdDevice desktop-abc123.contoso.com
    Searches by DNS host name.

    .EXAMPLE
    $Devices = Find-IRTAdDevice -Search 'DESKTOP-ABC123','LAPTOP-XYZ789' -Script
    Returns matching computer objects for two search strings without setting globals.

    .OUTPUTS
    None by default (sets global variables).
    Microsoft.ActiveDirectory.Management.ADComputer[] when -Script is used.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Find-IRTAdDevices',
        'Find-AdDevice', 'Find-AdDevices',
        'FindIRTAdDevice', 'FindIRTAdDevices',
        'FindAdDevice', 'FindAdDevices'
    )]
    [OutputType([System.Collections.Generic.List[psobject]])]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script
    )

    begin {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $ScriptDeviceObjects = [System.Collections.Generic.List[PsObject]]::new()
        $GetProperties = @(
            'DNSHostName'
            'Enabled'
            'Name'
            'ObjectGUID'
            'OperatingSystem'
            'OperatingSystemVersion'
            'SamAccountName'
            'servicePrincipalName '
        )
        $DisplayProperties = @(
            'Enabled'
            'Name'
            'SamAccountName'
            'DNSHostName'
            'OperatingSystem'
            'ObjectGUID'
        )

        $Computers = Get-AdComputer -Filter * -Property $GetProperties
    }

    process {

        foreach ($SearchString in $Search) {

            $MatchingComputers = [System.Collections.Generic.List[PsObject]]::new()

            foreach ($Computer in $Computers) {

                if ( $Computer.Name -match $SearchString -or
                    $Computer.DNSHostName -match $SearchString -or
                    $Computer.SamAccountName -match $SearchString -or
                    $Computer.servicePrincipalName -match $SearchString -or
                    $Computer.ObjectGUID -match $SearchString
                ) {
                    $MatchingComputers.Add( $Computer )
                }
            }

            if (($MatchingComputers | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingComputers | Format-Table $DisplayProperties
                }

                $FullDeviceObject = Get-AdComputer -Identity $MatchingComputers[0] -Property *

                $ScriptDeviceObjects.Add( ( $FullDeviceObject | Select-Object -First 1 ) )
            }
            elseif (($MatchingComputers | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingComputers | Format-Table $DisplayProperties
                    Write-IRT 'Multiple computers found. Refine search.' -Level Error
                }
            }
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        if ($Script) {
            return $ScriptDeviceObjects
        }

        if (($ScriptDeviceObjects | Measure-Object).Count -eq 1) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}DeviceObject"
                Value = $ScriptDeviceObjects | Select-Object -First 1
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$Global:IRT_${VarPrefix}DeviceObject"
        }
        elseif (($ScriptDeviceObjects | Measure-Object).Count -gt 1) {

            Write-IRT 'Multiple computers found. Refine search.' -Level Error
            $ScriptDeviceObjects | Format-Table $DisplayProperties
        }
    }
}