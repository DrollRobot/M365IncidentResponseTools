function Test-AdAvailable {
    <#
    .SYNOPSIS
    Returns true if the ActiveDirectory module is available and a domain controller can be reached.

    .DESCRIPTION
    Internal helper. Returns $true only when the ActiveDirectory RSAT module is installed
    AND Get-ADDomain succeeds (i.e., a domain controller is reachable). Returns $false on
    any error. Used as a guard condition at the top of every onprem_ad function.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        return $false
    }

    try {
        $null = Get-ADDomain -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-RunningOnDomainController {
    <#
    .SYNOPSIS
    Returns true if the current machine is a domain controller.

    .DESCRIPTION
    Internal helper. Compares $env:ComputerName against the list of domain controllers
    returned by Get-ADDomainController -Filter *. Returns $false on any error. Used to
    gate repadmin calls that must run on a DC.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    try {
        $DomainControllerNames = (Get-ADDomainController -Filter *).Name
        return $env:ComputerName -in $DomainControllerNames
    }
    catch {
        return $false
    }
}

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
