function Test-AdAvailable {
    <#
	.SYNOPSIS
	Returns true if the ActiveDirectory module is available and a domain controller can be reached.
	
	.NOTES
		Version: 2.0.0
	#>
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
	
	.NOTES
		Version: 1.0.0
	#>
    [CmdletBinding()]
    param ()

    try {
        $DomainControllerNames = ( Get-ADDomainController -Filter * ).Name
        return $env:ComputerName -in $DomainControllerNames
    }
    catch {
        return $false
    }
}

function Get-AdGlobalUserObjects {
	<#
	.SYNOPSIS
	Gets user objects from global variables. Designed to be used by other scripts.
	
	.NOTES
		Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
		$ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
	}

    process {

		# add userobject
		if ( $Global:UserObject ) {
			$ScriptUserObjects.Add( $Global:UserObject )
		}

		# add userobjects
		if ( $Global:UserObjects ) {
            $IterationList = @( $Global:UserObjects )  
			foreach ( $i in $IterationList ) {
				$ScriptUserObjects.Add( $i )
			}
		}

		# return user objects
		return $ScriptUserObjects | Sort-Object Id -Unique | Sort-Object DisplayName
    }
}
