function New-UalGapMarker {
    <#
    .SYNOPSIS
    Builds a visible "data missing" row to stand in for records that could not be retrieved.

    .DESCRIPTION
    Internal helper. When part of a search fails, the result is a workbook that looks like
    a quiet period rather than an incomplete one, which is the worst possible outcome
    during an investigation. This produces a row that mimics a UAL record closely enough
    to flow through deduplication, sorting and the sheet builders, so the gap is obvious
    in the spreadsheet itself and not only in the console.

    Build-AllOperationSheet checks the IRTDataGap property and keeps these rows on every
    sheet regardless of any operation filtering.

    The full explanation goes into AuditData, which surfaces in the workbook's Raw column.

    .PARAMETER Reason
    What went wrong, recorded in the marker's audit data.

    .PARAMETER Label
    Which query or job failed.

    .PARAMETER Date
    Timestamp to sort the marker by. Defaults to now. Passing the end of the search window
    keeps the marker at the top of a newest-first sheet.

    .EXAMPLE
    ```powershell
    New-UalGapMarker -Reason 'Job finished as failed' -Label 'keyword jdoe@contoso.com'
    ```
    Returns a marker row for insertion into the record collection.

    .OUTPUTS
    [pscustomobject] in the UAL record shape, with IRTDataGap set.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory marker object; changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Reason,

        [string] $Label,

        [datetime] $Date = (Get-Date)
    )

    $AuditData = [ordered]@{
        Operation    = '*** DATA MISSING - query failed; results incomplete ***'
        Workload     = 'IRT'
        ResultStatus = 'Failed'
        FailedQuery  = $Label
        Error        = $Reason
    } | ConvertTo-Json -Compress

    return [pscustomobject]@{
        Identity     = "IRT-DATA-GAP-$([guid]::NewGuid())"
        IRTDataGap   = $true
        CreationDate = $Date
        RecordType   = 'IRT_QUERY_FAILURE'
        Operations   = 'DataMissing'
        UserIds      = '*** DATA MISSING - INCOMPLETE RESULTS ***'
        AuditData    = $AuditData
    }
}
