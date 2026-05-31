function Show-GraphServicePrincipalTree {
    <#
    .SYNOPSIS
    Renders a Graph service principal object as a compact property tree.

    .DESCRIPTION
    Projects the service principal object, excluding the noisy AdditionalProperties
    collection, then passes the result to Format-Tree for console display. Intended
    to be called via pipeline from Show-IRTServicePrincipal.

    .PARAMETER ServicePrincipalObject
    The service principal object(s) to render. Accepts pipeline input.

    .PARAMETER Depth
    Maximum recursion depth for nested objects. Default: 10.

    .OUTPUTS
    None. Output is written to the console via Format-Tree.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [int] $Depth = 10
    )

    begin {
        $Exclude = @(
            'AdditionalProperties'
        )
    }

    process {
        foreach ($ServicePrincipalObjectItem in $ServicePrincipalObject) {
            if ($null -eq $ServicePrincipalObjectItem) { continue }

            $Projected = $ServicePrincipalObjectItem |
                Select-Object -Property * -ExcludeProperty $Exclude

            $Params = @{
                Depth           = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}