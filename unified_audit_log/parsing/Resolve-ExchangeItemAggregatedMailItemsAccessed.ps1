function Resolve-ExchangeItemAggregatedMailItemsAccessed {
    <#
	.SYNOPSIS
    Parses ExchangeItemAggregated MailItemsAccessed events from UAL.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [Parameter( Mandatory )]
        [boolean] $WaitOnMessageTrace,

        [Parameter( Mandatory )]
        [string] $UserName
    )

    begin {
        $Function = $MyInvocation.MyCommand.Name
        $VariableName = "IRT_MessageTraceTable_${UserName}"

        # colors
        # $Blue = @{ ForegroundColor = 'Blue' }
        # $Red = @{ ForegroundColor = 'Red' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        $Yellow = @{ ForegroundColor = 'Yellow' }

        $Summary = [System.Collections.Generic.List[string]]::new()

        # check for message trace table

        if ($WaitOnMessageTrace) {
            while (-not (Test-Path "variable:global:${VariableName}")) {
                Write-Host @Yellow "${Function}: Waiting on `$Global:${VariableName}..."
                Start-Sleep -Seconds 15
            }
        }

        if (Test-Path "variable:global:${VariableName}") {
            $Params = @{
                Name = $VariableName
                Scope = 'Global'
            }
            $MessageTraceTable = Get-Variable @Params
        }
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
                $InternetMessageId = $Item.InternetMessageId
                if ($MessageTraceTable.Value) {
                    $Trace = $MessageTraceTable.Value[$InternetMessageId]
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