function Get-ExchangeItemDeleteSummary {
    <#
	.SYNOPSIS
    Parses ExchangeItemGroup HardDelete events from UAL.

	.NOTES
	Version: 2.1.0
    2.1.0 - Moved wait logic to Show-IRTUnifiedAuditLog. Now receives resolved
            MessageTraceTable directly.
    2.0.0 - Replaced per-user variable with single IRT_MessageTraceTable. Added SharedState
            support for cross-runspace communication. Added timeout and -Test diagnostics.
    1.1.0 - Removed Auditdata param, added parsing for email subjects.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [hashtable] $MessageTraceTable
    )

    begin {
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # AffectedItems

        # build table by folder
        $FolderTable = @{}

        foreach ( $AffectedItem in $Log.AuditData.AffectedItems ) {

            $FolderPath = $AffectedItem.ParentFolder.Path

            # if table key doesn't exist, create it.
            if (-not $FolderTable.ContainsKey($FolderPath)) {
                $FolderTable[$FolderPath] = [System.Collections.Generic.List[psobject]]::new()
            }

            # add object to table
            $FolderTable[$FolderPath].Add($AffectedItem)
        }

        # loop through folders
        foreach ($Folder in $FolderTable.GetEnumerator()) {

            $SummaryLines.Add( "Folder: $($Folder.Name)" )

            # loop through items
            foreach ($Item in $Folder.Value) {

                $Subject = $null

                # if item has subject property, use it
                if ($Item.Subject) {
                    $Subject = $Item.Subject
                }
                elseif ($Item.InternetMessageId -and $MessageTraceTable) {
                    # if not, try to retrieve from message trace table.
                    $NormalizedId = ($Item.InternetMessageId -replace '[<>]', '').Trim()
                    if ($MessageTraceTable.ContainsKey($NormalizedId)) {
                        $Subject = $MessageTraceTable[$NormalizedId].Subject
                    }
                }

                # add best option to summary
                if ($Subject) {
                    $SummaryLines.Add( "    Subject: ${Subject}" )
                }
                elseif ($Item.InternetMessageId) {
                    $SummaryLines.Add( "    Item: $($Item.InternetMessageId)" )
                }
                else {
                    $SummaryLines.Add( "    Item: $($Item.Id)" )
                }
            }
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
