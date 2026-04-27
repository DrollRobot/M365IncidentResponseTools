function Get-ExchangeItemUpdateSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItem Update events from UAL.
	
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

        # ModifiedProperties
        foreach ( $Item in $Log.AuditData.ModifiedProperties ) {
            $SummaryLines.Add( "Modified: ${Item}" )
        }

        # Items
        foreach ( $Item in $Log.AuditData.Item ) {
            $Subject = $Item.Subject
            $SummaryLines.Add( "Item: ${Subject}" )
        }

        # join strings, create return object
        $Summary = $SummaryLines -join ', '
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}