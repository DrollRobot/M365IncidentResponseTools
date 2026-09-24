function Get-GlobalServicePrincipalObject {
    <#
    .SYNOPSIS
    Gets service principal objects from global variables. Designed to be used by other scripts.

    .DESCRIPTION
    Returns the de-duplicated, DisplayName-sorted list of Entra ID service principal objects
    currently stored in $Global:IRT_ServicePrincipalObjects. This is the standard way IRT
    functions resolve service principals when no -ServicePrincipalObject parameter is
    supplied directly. Mirrors Get-GlobalUserObject.

    .EXAMPLE
    $ServicePrincipals = Get-GlobalServicePrincipalObject
    Returns all service principal objects currently in the global session.

    .OUTPUTS
    System.Collections.Generic.List[PSObject]

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $ScriptSPObjects = [System.Collections.Generic.List[PsObject]]::new()
    }

    process {

        # add service principal objects
        if ( $Global:IRT_ServicePrincipalObjects ) {
            $IterationList = @( $Global:IRT_ServicePrincipalObjects )
            foreach ( $i in $IterationList ) {
                $ScriptSPObjects.Add( $i )
            }
        }

        # return service principal objects
        return $ScriptSPObjects | Sort-Object Id -Unique | Sort-Object DisplayName
    }
}
