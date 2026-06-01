function Open-IRTAllOperationsSheet {
    <#
    .SYNOPSIS
    Opens the unified audit log all-operations reference spreadsheet.

    .DESCRIPTION
    Opens the UALAllOperations.xlsx workbook for viewing or editing.
    Uses the path configured in AllOperationsSheetPath (via Set-IRTConfig) when set,
    otherwise opens the default file bundled with the module under the Data\ folder.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('Open-AllOperationsSheet', 'IRTAllOperationsSheet')]
    [CmdletBinding()]
    param ()

    process {
        $SheetPath = $Global:IRT_Config.AllOperationsSheetPath

        if (-not (Test-Path $SheetPath)) {
            throw "All-operations spreadsheet not found: ${SheetPath}"
        }

        Invoke-Item $SheetPath
    }
}
