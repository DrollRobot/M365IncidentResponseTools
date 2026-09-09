function Get-GraphUALRiskyOperation {
    <#
    .SYNOPSIS
    Returns the operation names marked high risk in the operations sheet.

    .DESCRIPTION
    Internal helper for the -RiskyOperation switch. Reads the operations sheet
    (IRT_Config.AllOperationsSheetPath) and returns the Operation values whose Risk column
    reads 'High'.

    Only operation names are returned, not the workload or record type they came from.
    That matches how the audit search API filters, and it means a High marking on any one
    row is enough to include the operation regardless of which workload row carries the
    mark. The corollary is that risk cannot be expressed per workload: an operation is
    either included for every workload or none.

    Duplicate names are collapsed. The sheet holds several operations on more than one
    row, one per workload, and the API takes a plain list.

    Returns an empty array when the sheet is missing or unreadable, and warns, because a
    risky-operations search that silently becomes an unfiltered one would be a surprise.

    .EXAMPLE
    ```powershell
    $Operations = Get-GraphUALRiskyOperation
    ```
    Returns the distinct high risk operation names.

    .OUTPUTS
    [string[]] distinct operation names marked high risk.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    $SheetPath = $Global:IRT_Config.AllOperationsSheetPath
    if (-not $SheetPath -or -not (Test-Path -LiteralPath $SheetPath)) {
        Write-IRT ("Operations sheet not found at '$SheetPath'. " +
            'Cannot determine high risk operations.') -Level Warn
        return [string[]]@()
    }

    Import-IRTModule -Name 'ImportExcel'
    try {
        $ExcelParams = @{
            Path          = $SheetPath
            WorksheetName = 'Operations'
            ErrorAction   = 'Stop'
        }
        $Rows = Import-Excel @ExcelParams
    }
    catch {
        Write-IRT "Could not read the operations sheet at '$SheetPath'." -Level Warn
        Write-PSFMessage -Level Warning -ErrorRecord $_ -Message (
            "${FunctionName}: failed to read '$SheetPath'.")
        return [string[]]@()
    }

    $Operations = @($Rows |
            Where-Object { $_.Risk -eq 'High' -and $_.Operation } |
            ForEach-Object { [string]$_.Operation } |
            Sort-Object -Unique)

    Write-PSFMessage -Level 8 -Message (
        "${FunctionName}: $($Operations.Count) distinct high risk operation(s).")

    if ($Operations.Count -eq 0) {
        Write-IRT ('No operations are marked High in the operations sheet. ' +
            'The search would cover everything; narrow it or mark some rows.') -Level Warn
    }

    return [string[]]$Operations
}
