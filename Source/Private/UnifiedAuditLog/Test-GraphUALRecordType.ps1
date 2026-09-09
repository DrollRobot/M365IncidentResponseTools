function Test-GraphUALRecordType {
    <#
    .SYNOPSIS
    Warns when a -RecordType value has never been seen in the operations sheet.

    .DESCRIPTION
    Internal helper. The Graph audit search API answers an unrecognised record type with
    HTTP 500, which is indistinguishable from the service being unwell, and the failure
    only surfaces after the job has been submitted. A client-side check turns that into
    an immediate, readable warning naming the likely typo.

    The known values come from the RecordType column of the operations sheet
    (IRT_Config.AllOperationsSheetPath), which records what this tenant's logs have
    actually contained. That is deliberately preferred over Microsoft's published enum:
    the v1.0 enum page runs hundreds of members behind beta, and both lag what the service
    really emits, so validating against documentation would reject legitimate searches.

    Because the sheet only knows what has been witnessed, an unknown value is a warning
    and never a hard stop. A sheet that has not yet seen MicrosoftTodoAudit is not
    evidence that MicrosoftTodoAudit is invalid. The search runs either way.

    Non-string RecordType values in the sheet are skipped. The bundled sheet contains a
    literal 50, an integer record type that reached it without being resolved to a name.

    .PARAMETER RecordType
    One or more record type names to check.

    .PARAMETER Cached
    Reuse the record types already loaded this session instead of re-reading the sheet.

    .EXAMPLE
    ```powershell
    Test-GraphUALRecordType -RecordType 'MicrosoftTeams', 'MicrosoftTeems'
    ```
    Returns 'MicrosoftTeems' and warns that it looks like a typo for 'MicrosoftTeams'.

    .OUTPUTS
    [string[]] the values that were not recognised. Empty when everything is known, or
    when the sheet could not be read.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string[]] $RecordType,

        [switch] $Cached
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    if (($RecordType | Measure-Object).Count -eq 0) { return [string[]]@() }

    $Known = Get-GraphUALKnownRecordType -Cached:$Cached
    if (($Known | Measure-Object).Count -eq 0) {
        # no sheet, or an unreadable one. Skip the check rather than warn on everything.
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: no record types available from the operations sheet; " +
            'skipping validation.')
        return [string[]]@()
    }

    $Unknown = [System.Collections.Generic.List[string]]::new()
    foreach ($Type in $RecordType) {
        if (-not $Type) { continue }
        if ($Known.Contains($Type)) { continue }
        $Unknown.Add($Type)

        # suggest by prefix first, then by substring either way round, which covers
        # truncations and the usual transpositions
        $Suggestions = @($Known | Where-Object {
                $_ -like "$Type*" -or $_ -like "*$Type*" -or $Type -like "*$_*"
            } | Sort-Object | Select-Object -First 3)

        $Msg = "Record type '$Type' has not been seen in the operations sheet."
        if ($Suggestions.Count -gt 0) {
            $Msg += " Did you mean: $($Suggestions -join ', ')?"
        }
        $Msg += ' Searching anyway.'
        Write-IRT $Msg -Level Warn
        Write-PSFMessage -Level 8 -Message "${FunctionName}: unknown record type '$Type'."
    }

    return [string[]]$Unknown
}
