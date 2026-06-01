function Get-AdGlobalUserObject {
    <#
    .SYNOPSIS
    Gets user objects from global variables. Designed to be used by other scripts.

    .DESCRIPTION
    Internal helper. Returns $Global:IRT_UserObject as a list. Used by onprem_ad functions
    as the fallback user-resolution mechanism when no -UserObject parameter is supplied
    directly.

    .NOTES
    Version: 1.0.0
    #>
    #>
    [OutputType([System.Collections.Generic.List[System.Management.Automation.PSObject]])]
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
    }

    process {

        if ($Global:IRT_UserObject) {
            $ScriptUserObjects.Add($Global:IRT_UserObject)
        }

        return $ScriptUserObjects
    }
}
