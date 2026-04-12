function Resolve-SharePointPageViewed {
    <#
	.SYNOPSIS
    Parses PageViewed events from UAL.
	
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

        # ObjectId
        $ObjectId = $Log.AuditData.ObjectId
        $SummaryLines.Add( "ObjectId: ${ObjectId}" )


        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}