function Resolve-ExchangeItemSubject {
    <#
	.SYNOPSIS
    Parses ExchangeItem events from UAL.
	
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

        # Items
        foreach ( $Item in $Log.AuditData.Item ) {

            $Subject = $Item.Subject
            $SummaryLines.Add( "Subject: ${Subject}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}