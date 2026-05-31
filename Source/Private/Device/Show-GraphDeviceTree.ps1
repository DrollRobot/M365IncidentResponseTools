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