function Get-GraphUALKnownRecordType {
    <#
    .SYNOPSIS
    Returns the record type names recorded in the operations sheet.

    .DESCRIPTION
    Internal helper. Reads the distinct RecordType values from the operations sheet
    (IRT_Config.AllOperationsSheetPath) into a case-insensitive set, cached in
    $Global:IRT_GraphUALRecordTypes for the rest of the session.

    The comparison is case-insensitive because the audit search API treats record type
    filters that way, and because the sheet itself is inconsistent about casing.

    Non-string values are skipped: the bundled sheet contains a literal 50, an integer
    record type that was written without being resolved to a name.

    Returns an empty set when the sheet is missing or unreadable. Callers treat that as
    "cannot validate" rather than as an error, since the sheet is an aid and not a
    requirement.

    .PARAMETER Cached
    Return the session cache if it is populated, without re-reading the sheet.

    .EXAMPLE
    ```powershell
    $Known = Get-GraphUALKnownRecordType
    $Known.Contains('microsoftteams')
    ```
    Reads the sheet and tests a value without regard to casing.

    .OUTPUTS
    [System.Collections.Generic.HashSet[string]] of record type names, case-insensitive.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    # Object[] is declared alongside the set because every return uses the comma
    # operator; the caller still receives the HashSet, but the statement type is an array.
    [OutputType([System.Collections.Generic.HashSet[string]], [object[]])]
    param(
        [switch] $Cached
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    # Every return uses the comma operator. A HashSet is IEnumerable, so a bare return
    # unrolls it to a plain string array, and .Contains() on an array is case-sensitive
    # regardless of the comparer the set was built with. That would quietly undo the
    # case-insensitive matching this function exists to provide.
    $IsSet = $Global:IRT_GraphUALRecordTypes -is [System.Collections.Generic.HashSet[string]]
    if ($Cached -and $IsSet -and $Global:IRT_GraphUALRecordTypes.Count -gt 0) {
        return , $Global:IRT_GraphUALRecordTypes
    }

    $Comparer = [System.StringComparer]::OrdinalIgnoreCase
    $Types = [System.Collections.Generic.HashSet[string]]::new($Comparer)

    $SheetPath = $Global:IRT_Config.AllOperationsSheetPath
    if (-not $SheetPath -or -not (Test-Path -LiteralPath $SheetPath)) {
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: operations sheet not found at '$SheetPath'.")
        $Global:IRT_GraphUALRecordTypes = $Types
        return , $Types
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
        Write-PSFMessage -Level Warning -ErrorRecord $_ -Message (
            "${FunctionName}: could not read '$SheetPath'; record type validation is off.")
        $Global:IRT_GraphUALRecordTypes = $Types
        return , $Types
    }

    foreach ($Row in $Rows) {
        $Value = $Row.RecordType
        # skip blanks and the stray integer record types the sheet has collected
        if (-not $Value) { continue }
        if ($Value -isnot [string]) { continue }
        $Trimmed = $Value.Trim()
        if ($Trimmed) { [void]$Types.Add($Trimmed) }
    }

    Write-PSFMessage -Level 8 -Message (
        "${FunctionName}: loaded $($Types.Count) record type(s) from the operations sheet.")
    $Global:IRT_GraphUALRecordTypes = $Types
    return , $Types
}
