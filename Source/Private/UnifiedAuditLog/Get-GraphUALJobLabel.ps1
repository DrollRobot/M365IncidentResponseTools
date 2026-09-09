function Get-GraphUALJobLabel {
    <#
    .SYNOPSIS
    Summarises an audit search job's filters in one short line.

    .DESCRIPTION
    Internal helper. Jobs in a group differ only by their filters, and the display name
    does not record which filter a job carries, only its index. This reads the filters
    back off the query object so a listing can show what each job actually covers.

    Values are truncated because a keyword filter is often a full user principal name or a
    GUID, and several of those on one line make a table unreadable.

    Returns 'unfiltered' when the job carries no filters at all, which is worth seeing
    plainly since only one such job may run at a time.

    .PARAMETER Query
    The query object from the audit log query listing.

    .EXAMPLE
    ```powershell
    Get-GraphUALJobLabel -Query $Query
    ```
    Returns something like 'keyword jdoe@contoso.com' or 'recordType MicrosoftTeams'.

    .OUTPUTS
    [string] a short description of the job's filters.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [object] $Query
    )

    $MaxLength = 40
    $Parts = [System.Collections.Generic.List[string]]::new()

    if ($Query.keywordFilter) {
        $Parts.Add("keyword $($Query.keywordFilter)")
    }
    if ($Query.userPrincipalNameFilters -and @($Query.userPrincipalNameFilters).Count -gt 0) {
        $Parts.Add("actor $(@($Query.userPrincipalNameFilters) -join ',')")
    }
    if ($Query.recordTypeFilters -and @($Query.recordTypeFilters).Count -gt 0) {
        $Parts.Add("recordType $(@($Query.recordTypeFilters) -join ',')")
    }
    if ($Query.ipAddressFilters -and @($Query.ipAddressFilters).Count -gt 0) {
        $Parts.Add("ip $(@($Query.ipAddressFilters) -join ',')")
    }
    if ($Query.operationFilters -and @($Query.operationFilters).Count -gt 0) {
        # the risky-operations profile passes dozens; a count reads better than a list
        $Parts.Add("$(@($Query.operationFilters).Count) operation(s)")
    }

    if ($Parts.Count -eq 0) { return 'unfiltered' }

    $Label = $Parts -join ' '
    if ($Label.Length -gt $MaxLength) { $Label = $Label.Substring(0, $MaxLength - 3) + '...' }
    return $Label
}
