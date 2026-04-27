function Get-SearchQueryPerformedSummary {
    <#
	.SYNOPSIS
    Parses SearchQueryPerformed events from UAL.
	
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
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # SearchQueryText
        $SearchQueryText = $Log.AuditData.SearchQueryText
        $SummaryLines.Add( "SearchQueryText: ${SearchQueryText}" )

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}