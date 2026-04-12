function Resolve-ExchangeAdminInboxRule {
    <#
	.SYNOPSIS
    Parses ExchangeAdmin ???-InboxRule events from UAL.
	
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

        # AppPoolName
        $AppPoolName = $Log.AuditData.AppPoolName
        $SummaryLines.Add("AppPoolName: ${AppPoolName}")

        # Parameters
        foreach ($Parameter in $Log.AuditData.Parameters) {
            $Name = $Parameter.Name
            $Value = $Parameter.Value
            $SummaryLines.Add("${Name}: ${Value}")
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}