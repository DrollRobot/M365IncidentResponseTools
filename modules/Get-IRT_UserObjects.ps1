function Get-IRTUserObjects {
	<#
	.SYNOPSIS
	Gets user objects from global variables. Designed to be used by other scripts.
	
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