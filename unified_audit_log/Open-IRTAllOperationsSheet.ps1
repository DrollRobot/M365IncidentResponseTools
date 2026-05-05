function Open-IRTAllOperationsSheet {
    <#
    .SYNOPSIS
    Opens the unified audit log all-operations reference spreadsheet.

    .DESCRIPTION
    Opens the unified_audit_log-all_operations.xlsx workbook for viewing or editing.
    Uses the path configured in AllOperationsSheetPath (via Set-IRTConfig) when set,
    otherwise opens the default file bundled with the module under the data\ folder.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('Open-AllOperationsSheet', 'IRTAllOperationsSheet')]
    [CmdletBinding()]
    param ()

    process {
        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $AllOperationsFileName = 'unified_audit_log-all_operations.xlsx'
        $AllOperationsConfig = $Global:IRT_Config.AllOperationsSheetPath
        $SheetPath = if ($AllOperationsConfig) { $AllOperationsConfig } else { Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}" }

        if (-not (Test-Path $SheetPath)) {
            throw "All-operations spreadsheet not found: ${SheetPath}"
        }

        Invoke-Item $SheetPath
    }
}
