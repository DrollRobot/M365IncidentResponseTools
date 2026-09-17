function Get-GraphUALOpenUnfilteredJob {
    <#
    .SYNOPSIS
    Returns an audit search job that is running without filters, if one exists.

    .DESCRIPTION
    Internal helper. The service permits only one unfiltered audit log query to be open at
    a time. A second one is refused with TooManyRequests, and the Graph SDK spends about
    24 seconds retrying before the caller sees it, producing a generic throttling error
    that says nothing about the real cause.

    Checking the listing first turns that into an immediate message naming the job that is
    in the way.

    A job counts as unfiltered when it carries no keyword, record type, operation, user
    principal name, IP address, object id, service or administrative unit filter. Note
    that the singular serviceFilter key documented for the create call is not persisted,
    so only the plural serviceFilters is worth inspecting.

    Returns $null when nothing is blocking, including when the listing itself fails: a
    check that cannot run should not stop a search from being attempted.

    .EXAMPLE
    ```powershell
    $Blocking = Get-GraphUALOpenUnfilteredJob
    if ($Blocking) { Write-IRT "Blocked by $($Blocking.displayName)" -Level Error }
    ```
    Reports the job occupying the single unfiltered slot.

    .OUTPUTS
    The blocking query object, or $null.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    $Response = Invoke-GraphUALRequest -Path 'queries'
    if (-not $Response.Ok) {
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: could not list queries; skipping the unfiltered check.")
        return $null
    }

    $FilterKeys = @(
        'keywordFilter'
        'recordTypeFilters'
        'operationFilters'
        'userPrincipalNameFilters'
        'ipAddressFilters'
        'objectIdFilters'
        'serviceFilters'
        'administrativeUnitIdFilters'
    )

    foreach ($Query in @($Response.Result.value)) {
        if ($Query.status -notin @('notStarted', 'running')) { continue }

        $HasFilter = $false
        foreach ($Key in $FilterKeys) {
            $Value = $Query.$Key
            # an empty array is the API's way of saying "no filter", so test for content
            if ($Value -and @($Value).Count -gt 0) { $HasFilter = $true; break }
        }
        if (-not $HasFilter) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: unfiltered job '$($Query.displayName)' is $($Query.status).")
            return $Query
        }
    }

    return $null
}
