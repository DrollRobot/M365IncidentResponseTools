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
        #FIXME logs only contain id numbers AAMkADMyZGI3OTNlLTQ2YmMtNDU0MC05ZDEzLTY2NmZlNTc3NTU3MQBGAAAAAABDiQ7dEKTwSbR9ja6I0wIGBwBZKFzgmvpXRbRzj2mWaXIlAAAAAAENAACNpRQqi6YHQrBiBW3y6IBkAAf41Lo6AAA=

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}