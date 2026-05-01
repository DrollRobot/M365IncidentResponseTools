function Get-SetConditionalAccessPolicySummary {
    <#
	.SYNOPSIS
    Parses ExchangeAdmin Set-ConditionalAccessPolicy events from UAL.

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

        # DisplayName
        $DisplayName = ($Log.AuditData.Parameters | Where-Object { $_.Name -eq 'DisplayName' } ).Value
        $SummaryLines.Add("DisplayName: ${DisplayName}")

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}