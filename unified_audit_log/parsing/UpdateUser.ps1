function Get-UpdateUserSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory "Update user." events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryStrings = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ModifiedProperties
        $Properties = ( $Log.AuditData.ModifiedProperties |
            Where-Object { $_.Name -eq "Included Updated Properties" } ).NewValue
        foreach ( $Property in $Properties ) {
            $SummaryStrings.Add( "Property: ${Property}" )
        }

        # join strings, create return object
        $SummaryString = $SummaryStrings -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $SummaryString
        }

        return $EventObject
    }
}
