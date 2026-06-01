function Get-GlobalUserObject {
    <#
    .SYNOPSIS
    Gets user objects from global variables. Designed to be used by other scripts.

    .DESCRIPTION
    Returns the de-duplicated, DisplayName-sorted list of Entra ID user objects currently
    stored in $Global:IRT_UserObjects. This is the standard way IRT functions resolve users
    when no -UserObject parameter is supplied directly.

    .EXAMPLE
    $Users = Get-GlobalUserObject
    Returns all user objects currently in the global session.

    .OUTPUTS
    System.Collections.Generic.List[PSObject]

    .NOTES
    Version: 1.0.3
    #>
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
    }

    process {

        # add userobjects
        if ( $Global:IRT_UserObjects ) {
            $IterationList = @( $Global:IRT_UserObjects )
            foreach ( $i in $IterationList ) {
                $ScriptUserObjects.Add( $i )
            }
        }

        # return user objects
        return $ScriptUserObjects | Sort-Object Id -Unique | Sort-Object DisplayName
    }
}
