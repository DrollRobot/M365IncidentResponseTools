function Resolve-SharePointFileOperation {
    <#
	.SYNOPSIS
    Parses Sharepoint FileAccessed events from UAL.
	
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

        # ObjectId. the full web url for the file. it seems like this property is present on every sharepoint operation
        $ObjectId = $Log.AuditData.ObjectID
        if ($ObjectId) {
            $SummaryLines.Add( "ObjectId: ${ObjectId}" )
        }

        # ApplicationDisplayName. the application that generated the operation
        $ApplicationDisplayName = $Log.AuditData.ApplicationDisplayName
        if ($ApplicationDisplayName) {
            $SummaryLines.Add( "ApplicationDisplayName: ${ApplicationDisplayName}" )
        }

        # SourceFileName. just the name of the file
        $SourceFileName = $Log.AuditData.SourceFileName
        if ($SourceFileName) {
            $SummaryLines.Add( "SourceFileName: ${SourceFileName}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $SummaryObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $SummaryObject
    }
}