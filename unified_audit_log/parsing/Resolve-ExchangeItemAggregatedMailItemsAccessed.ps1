function Resolve-ExchangeItemAggregatedMailItemsAccessed {
    <#
	.SYNOPSIS
    Parses ExchangeItemAggregated MailItemsAccessed events from UAL.
	
	.NOTES
	Version: 2.1.0
    2.1.0 - Moved wait logic to Show-UALogs. Now receives resolved MessageTraceTable directly.
    2.0.0 - Replaced per-user variable with single IRT_MessageTraceTable. Added SharedState
            support for cross-runspace communication. Added timeout and -Test diagnostics.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [hashtable] $MessageTraceTable
    )

    begin {
        $Summary = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ClientInfoString
        $ClientInfoString = $Log.AuditData.ClientInfoString
        $Summary.Add( "ClientInfoString: ${ClientInfoString}" )

        # Folders
        foreach ($Folder in $Log.AuditData.Folders) {

            $Summary.Add( "Folder: $($Folder.Path)" )
            $Items = $Folder.FolderItems

            # Items
            foreach ($Item in $Items) {
                $Subject = $null
                $InternetMessageId = $Item.InternetMessageId
                if ($MessageTraceTable -and $InternetMessageId) {
                    $NormalizedId = ($InternetMessageId -replace '[<>]','').Trim()
                    $Trace = $MessageTraceTable[$NormalizedId]
                    if ($Trace) {
                        $Subject = $Trace.Subject
                    }
                }

                if ($Subject) {
                    $Summary.Add( "    Subject: ${Subject}" )            
                }
                else {
                    $Summary.Add( "    Item: ${InternetMessageId}" )
                }
            }
        }

        # join strings, create return object
        $AllSummary = $Summary -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $AllSummary
        }

        return $EventObject
    }
}