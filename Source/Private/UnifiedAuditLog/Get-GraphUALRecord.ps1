function Get-GraphUALRecord {
    <#
    .SYNOPSIS
    Retrieves every record from one finished audit search job, following paging.

    .DESCRIPTION
    Internal helper. Pages the records endpoint until it runs out of nextLinks or hits the
    caller's remaining budget.

    The page size is fixed at 999. The endpoint rejects anything larger, and this is the
    largest page the service will return.

    A failure partway through is reported rather than thrown, and the pages already
    retrieved are returned with it. A partial download plus a visible gap marker is more
    useful during an investigation than losing thousands of records to one failed request.

    .PARAMETER JobId
    Id of the job to read.

    .PARAMETER Remaining
    Maximum records still wanted. Paging stops once this many have been collected. Zero or
    less means no limit.

    .EXAMPLE
    ```powershell
    $Page = Get-GraphUALRecord -JobId $Id -Remaining 50000
    ```
    Retrieves up to 50,000 records from a job.

    .OUTPUTS
    [pscustomobject] with properties:
        Records - the raw Graph records
        Count   - how many were retrieved
        Pages   - how many requests were made
        Error   - the failure message if paging stopped early, else $null

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $JobId,

        [int] $Remaining = 0
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    # 999 is the ceiling; the endpoint refuses larger values
    $PageSize = 999
    $Records = [System.Collections.Generic.List[object]]::new()
    $Pages = 0
    $PageError = $null

    $Response = Invoke-GraphUALRequest -Path "queries/${JobId}/records?`$top=${PageSize}"

    while ($true) {
        if (-not $Response.Ok) {
            $PageError = $Response.Error
            break
        }

        $Pages++
        foreach ($Item in @($Response.Result.value)) { $Records.Add($Item) }

        if ($Remaining -gt 0 -and $Records.Count -ge $Remaining) { break }

        $NextLink = $Response.Result.'@odata.nextLink'
        if (-not $NextLink) { break }

        Write-PSFMessage -Level 9 -Message (
            "${FunctionName}: job $JobId page $($Pages + 1), $($Records.Count) so far.")
        $Response = Invoke-GraphUALRequest -Uri $NextLink
    }

    return [pscustomobject]@{
        Records = $Records
        Count   = $Records.Count
        Pages   = $Pages
        Error   = $PageError
    }
}
