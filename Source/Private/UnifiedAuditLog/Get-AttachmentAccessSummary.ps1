function Get-AttachmentAccessSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItemAggregated AttachmentAccess events from UAL.

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

        $null = $Log  # TODO: implement attachment log parsing (see FIXME below)
        # need to lookup email by ID.
        #FIXME logs only contain id numbers. need to find way to translate id to attachment name

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
