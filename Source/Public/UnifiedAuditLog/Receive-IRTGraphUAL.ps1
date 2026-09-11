function Receive-IRTGraphUAL {
    <#
    .SYNOPSIS
    Downloads the records from finished audit search jobs and exports them.

    .DESCRIPTION
    Retrieves every record from one or more finished Graph audit search jobs, merges them,
    and hands the result to Show-IRTUnifiedAuditLog so the output is the same workbook
    Get-IRTUnifiedAuditLog produces.

    Records are deduplicated by id and sorted newest first. The API returns each record
    once per job and does not sort them, and a group normally contains overlapping jobs,
    such as a keyword search on a user principal name alongside one on their object id, so
    both steps matter.

    Jobs that failed have a DATA MISSING marker inserted in their place, so an incomplete
    export is visible in the workbook rather than looking like a quiet period.

    Finished searches cannot be removed from the tenant. The API has no delete, so they
    stay listed until Purview expires them after about thirty days. To make that
    manageable, the exported file is named after the search that produced it, carrying the
    same creation stamp and group id, so a file on disk can be matched by eye to a search
    in the listing. Downloading the same group twice overwrites the same file rather than
    producing a second one.

    .PARAMETER Group
    One or more group ids to download, as returned by Start-IRTGraphUAL.

    .PARAMETER Id
    One or more individual job ids, for collecting a single job rather than a group.

    .PARAMETER Excel
    Export to an Excel workbook. Default: $true.

    .PARAMETER Xml
    Export the raw records to XML as well. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data where available when building the workbook.

    .PARAMETER PassThru
    Emit the record collection instead of only exporting it.

    .EXAMPLE
    ```powershell
    Receive-IRTGraphUAL -Group '3f9a1c2b'
    ```
    Downloads a group and exports the workbook.

    .EXAMPLE
    ```powershell
    $Records = Receive-IRTGraphUAL -Group '3f9a1c2b' -Excel $false -PassThru
    ```
    Returns the records in memory without writing files.

    .OUTPUTS
    None by default. With -PassThru, one
    [System.Collections.Generic.List[psobject]] per group.

    .NOTES
    Version: 1.1.0
    1.1.0 - Removed -ResultLimit. It only existed because of Search-UnifiedAuditLog's
    paging model; a Graph download ends on its own, and every record is kept.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Group')]
    [OutputType([System.Collections.Generic.List[psobject]])]
    param(
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Group')]
        [Alias('GroupId')]
        [string[]] $Group,

        [Parameter(Mandatory, ParameterSetName = 'Id')]
        [Alias('JobId')]
        [string[]] $Id,

        [boolean] $Excel = $true,

        [boolean] $Xml = $Global:IRT_Config.ExportXml,

        [switch] $Cached,


        [switch] $PassThru
    )

    begin {
        Import-IRTModule -Name 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # one listing serves every group: the API ignores OData filters on this
        # collection, so it is fetched whole and matched locally
        $Listing = Get-GraphUALJob
        if (-not $Listing) {
            Write-IRT 'No audit search jobs found on the tenant.' -Level Warn
            return
        }
    }

    process {
        if (-not $Listing) { return }

        # resolve the requested groups
        if ($PSCmdlet.ParameterSetName -eq 'Id') {
            $Selected = @($Listing | Where-Object { $_.Id -in $Id })
            $GroupIds = @($Selected.GroupId | Where-Object { $_ } | Sort-Object -Unique)
            # a job with an unreadable name has no group, so treat each as its own
            if ($GroupIds.Count -eq 0) { $GroupIds = @($Id) }
        }
        else {
            $GroupIds = $Group
        }

        foreach ($CurrentGroup in $GroupIds) {

            $Jobs = @($Listing | Where-Object { $_.GroupId -eq $CurrentGroup })
            if ($Jobs.Count -eq 0 -and $PSCmdlet.ParameterSetName -eq 'Id') {
                $Jobs = @($Listing | Where-Object { $_.Id -eq $CurrentGroup })
            }
            if ($Jobs.Count -eq 0) {
                Write-IRT "No jobs found for group '$CurrentGroup'." -Level Warn
                continue
            }

            $First = $Jobs[0]
            $Label = "$($First.ObjectName) $($First.ProfileTag) ($($Jobs.Count) job(s))"

            #region GATES
            $Pending = @($Jobs | Where-Object { $_.Status -in @('notStarted', 'running') })
            if ($Pending.Count -gt 0) {
                Write-IRT ("Group '$CurrentGroup' still has $($Pending.Count) job(s) " +
                    'running. Wait for it with Wait-IRTGraphUAL.') -Level Warn
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($Label, 'Download audit search results')) {
                continue
            }
            #endregion GATES

            #region DOWNLOAD
            Write-IRT "Downloading ${Label}."

            $Unique = [System.Collections.Generic.HashSet[string]]::new()
            $Records = [System.Collections.Generic.List[psobject]]::new()

            foreach ($Job in $Jobs) {

                if ($Job.Status -ne 'succeeded') {
                    Write-IRT ("  job $($Job.Index) is '$($Job.Status)'. Inserting a " +
                        'DATA MISSING marker.') -Level Error
                    $MarkerParams = @{
                        Reason = "Job $($Job.DisplayName) finished as '$($Job.Status)'."
                        Label  = $Job.Label
                        Date   = $First.EndUtc
                    }
                    $Records.Add((New-UalGapMarker @MarkerParams))
                    continue
                }

                $Page = Get-GraphUALRecord -JobId $Job.Id

                if ($Page.Error) {
                    Write-IRT ("  job $($Job.Index) failed partway through download. " +
                        'Inserting a DATA MISSING marker; partial records kept.') -Level Error
                    $MarkerParams = @{
                        Reason = "Download failed for $($Job.DisplayName): $($Page.Error)"
                        Label  = $Job.Label
                        Date   = $First.EndUtc
                    }
                    $Records.Add((New-UalGapMarker @MarkerParams))
                }

                $Added = 0
                foreach ($Raw in $Page.Records) {
                    # dedupe across jobs in the group: a keyword search on a UPN and one
                    # on the same user's object id return many of the same events
                    if (-not $Unique.Add([string]$Raw.id)) { continue }
                    $Records.Add((ConvertTo-UalRecord -Record $Raw))
                    $Added++
                }

                Write-IRT ("  job $($Job.Index) ($($Job.Label)): $($Page.Count) record(s), " +
                    "$Added new.")
            }
            #endregion DOWNLOAD

            if ($Records.Count -eq 0) {
                Write-IRT "No records returned for ${Label}." -Level Warn
                continue
            }

            #region SORT
            # the API does not order its output, and the sheet builders assume newest first
            $Comparison = [System.Comparison[psobject]] {
                param($X, $Y)
                $Left = $X.CreationDate
                $Right = $Y.CreationDate
                if ($null -eq $Left -and $null -eq $Right) { return 0 }
                if ($null -eq $Left) { return 1 }
                if ($null -eq $Right) { return -1 }
                return -1 * $Left.CompareTo($Right)
            }
            $Records.Sort($Comparison)
            #endregion SORT

            Write-IRT "Total $($Records.Count) unique record(s) for ${Label}."

            #region OUTPUT
            # The file name carries the search's own stamp and group id, not the time of
            # the download. Finished searches cannot be deleted from the tenant, so the
            # only way to tell which exported file came from which of the searches still
            # listed there is for the two names to visibly agree. A search shown as
            # 'UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b|j1' exports to a file ending
            # '_jdoe_260909-1412_g3f9a1c2b.xlsx'.
            $Domain = Get-DefaultDomain
            $FileBase = "$($First.FilePrefix)_$($First.Days)Days_${Domain}" +
            "_$($First.ObjectName)_$($First.Stamp)_g$($First.GroupId)"

            $TitleFormat = 'M/d/yy h:mmtt'
            $TitleStart = '?'
            $TitleEnd = '?'
            if ($First.StartUtc) {
                $TitleStart = $First.StartUtc.ToLocalTime().ToString($TitleFormat)
            }
            if ($First.EndUtc) {
                $TitleEnd = $First.EndUtc.ToLocalTime().ToString($TitleFormat)
            }
            $TitleSuffix = " for $($First.ObjectName). Covers $($First.Days) days, " +
            "${TitleStart} to ${TitleEnd}."

            # Show-IRTUnifiedAuditLog reads this metadata row at index 0
            $Records.Insert(0, [pscustomobject]@{
                    Metadata       = $true
                    FileNamePrefix = $First.FilePrefix
                    FileName       = $FileBase
                    SheetTitle     = $First.SheetTitle
                    Title          = "$($First.SheetTitle)${TitleSuffix}"
                    TitleSuffix    = $TitleSuffix
                    ProfileTag     = $First.ProfileTag
                })

            $OutputPath = $null
            if ($Xml) {
                $OutputPath = "${FileBase}.xml"
                Write-IRT "Saving records to: ${OutputPath}"
                $Records | Export-Clixml -Depth 10 -Path $OutputPath
            }

            if ($Excel) {
                $ShowParams = @{
                    Log    = $Records
                    Cached = $Cached
                }
                & 'Show-IRTUnifiedAuditLog' @ShowParams
                $OutputPath = "${FileBase}.xlsx"
            }
            #endregion OUTPUT

            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: group $CurrentGroup done, $($Records.Count) row(s) [$Elapsed]")

            if ($PassThru) { $Records }
        }
    }
}
