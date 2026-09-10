function Get-IRTTeamsExternalDomain {
    <#
    .SYNOPSIS
    Pulls the Unified Audit Log records that reveal which external domains and
    tenants the organisation communicates with over Microsoft Teams.

    .DESCRIPTION
    Queries the Unified Audit Log for the Teams operations whose audit records
    carry the identity of the remote party in a chat, channel post, meeting, or
    call. Collating these records shows which outside organisations tenant users
    actually talk to, which is the starting point for scoping a compromise that
    spread through Teams federation or guest access.

    The requested date range is split into calendar weeks running Sunday through
    Saturday, and each week is queried and exported separately as a CLIXML file
    named for the Sunday that begins the week. Splitting the pull this way keeps
    each Search-UnifiedAuditLog window small enough to return reliably, and lets
    an interrupted run resume: weeks that already have a file on disk are skipped
    unless -Force is passed. To retry particular weeks, such as ones that reported
    DATA MISSING markers, pass their numbers to -Week.

    A file is written for every week that is queried, including weeks with no
    matching activity. An empty file therefore means "queried, nothing found",
    which is a different and much more useful statement than a missing file.

    Weeks are queried newest first, so the most recent activity lands on disk
    soonest.

    Operations queried:

        MessageSent              - chat and channel messages
        MessageCreatedHasLink    - messages containing a link
        MessageUpdated           - message edits
        MessageEditedHasLink     - edits to messages containing a link
        ChatCreated              - new chat threads
        MemberAdded              - members joining a chat or team
        MeetingParticipantDetail - meeting attendees, including guests
        CallParticipantDetail    - call participants
        ReactedToMessage         - message reactions (remote tenant ID only)
        UserAccepted             - external user accepted (remote tenant ID only)
        UserBlocked              - external user blocked (remote tenant ID only)

    The last three record the remote party's tenant GUID but not its domain name,
    so they still identify the external organisation - just not by a name a human
    can read without resolving the GUID.

    Guest accounts appear under this tenant's ID, with the guest's home domain
    encoded in the UPN before #EXT# (jane_contoso.com#EXT#@tenant.onmicrosoft.com).

    Requires an active Exchange Online connection, and a Microsoft Graph
    connection for the tenant domain used in file names.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.
    Default: 180.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute
    range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute
    range.

    .PARAMETER Week
    One or more week numbers to query, as shown in the "Week N of M" console
    label. Weeks are numbered newest first, so week 1 is the most recent. Only the
    named weeks are queried, and each is re-queried even if its file already
    exists, since a failed query still writes a file holding DATA MISSING markers.

    The numbers only point at the same weeks if the range resolves the same way as
    the original run, so retry with the same -Start / -End. With -Days (or the
    default), every week's number goes up by one each time a Sunday passes; check
    the dates in the console label before trusting a retry.

    .PARAMETER Path
    Directory to write the weekly CLIXML files into. Default: current directory.

    .PARAMETER ResultLimit
    Maximum records to retrieve per weekly chunk. Stops at the next 5000-record
    page boundary after the limit is reached. Default: 50000.

    .PARAMETER ChunkDelaySeconds
    Seconds to pause between queries to reduce the chance of tripping Exchange
    throttling limits. Default: 2. Set to 0 to disable.

    .PARAMETER ThrottleDelaySeconds
    Base backoff (seconds) used when a query fails. Passed through to
    Get-IRTUnifiedAuditLog, which grows the backoff exponentially per retry.
    Default: 60.

    .PARAMETER Force
    Re-query and overwrite weeks that already have a file in -Path. Without it,
    existing weekly files are left alone so an interrupted run can be resumed
    without repeating completed work.

    .EXAMPLE
    ```powershell
    Get-IRTTeamsExternalDomain
    ```
    Pulls the last 180 days, writing one CLIXML file per Sunday-Saturday week
    into the current directory.

    .EXAMPLE
    ```powershell
    Get-IRTTeamsExternalDomain -Days 30 -Path 'C:\Cases\Contoso'
    ```
    Pulls the last 30 days into a specific folder.

    .EXAMPLE
    ```powershell
    Get-IRTTeamsExternalDomain -Start '2026-01-01' -End '2026-03-31' -Force
    ```
    Pulls an absolute range, re-querying weeks that already have files.

    .EXAMPLE
    ```powershell
    Get-IRTTeamsExternalDomain -Start '2026-01-01' -End '2026-03-31' -Week 4, 9
    ```
    Re-queries only weeks 4 and 9 of that range, for example after they reported
    DATA MISSING markers. Their existing files are overwritten.

    .OUTPUTS
    None. Writes one CLIXML file per queried week into -Path.

    .NOTES
    Version: 1.2.0
    1.2.0 - Added MeetingParticipantDetail, UserAccepted, and UserBlocked.
    CallParticipantDetail moved to the domain group.
    1.1.0 - Added -Week to re-query specific weeks. No longer emits a FileInfo
    object for each file written.
    #>
    [Alias('GetTeamsExtDomain', 'GetTeamsExtDomains')]
    [CmdletBinding()]
    param (
        [int]    $Days, # default value set at #DEFAULTDAYS
        [string] $Start,
        [string] $End,

        # retry specific weeks by the number shown in the console label
        [ValidateRange(1, [int]::MaxValue)]
        [int[]] $Week,

        [string] $Path = (Get-Location).Path,

        [int] $ResultLimit = 50000,

        # seconds to pause between queries to avoid tripping throttle limits
        [ValidateRange(0, 3600)]
        [int] $ChunkDelaySeconds = 2,

        # base seconds for retry backoff, passed through to Get-IRTUnifiedAuditLog
        [ValidateRange(1, 3600)]
        [int] $ThrottleDelaySeconds = 60,

        [switch] $Force
    )

    begin {
        Import-IRTModule -Name 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        #DEFAULTDAYS
        $DefaultDays = 180

        $FileNamePrefix = 'TeamsExternalDomains'
        $SheetTitle = 'Teams external domains'

        # Operations whose audit records name the remote party's domain.
        $DomainOperations = @(
            'MessageSent'
            'MessageCreatedHasLink'
            'MessageUpdated'
            'MessageEditedHasLink'
            'ChatCreated'
            'MemberAdded'
            'MeetingParticipantDetail'
            'CallParticipantDetail'
        )
        # Operations that record only the remote tenant's GUID. Still identifies
        # the external organisation, but the GUID has to be resolved separately
        # before it means anything to an analyst.
        $TenantIdOperations = @(
            # names the domain only when the external party is the one reacting
            'ReactedToMessage'
            'UserAccepted'
            'UserBlocked'
        )
        $Operations = $DomainOperations + $TenantIdOperations

        # No -RecordType filter is applied. Several of these operation names also
        # appear outside the Teams workload, and dropping those records to tidy
        # the result set would hide external contact from the analyst - the one
        # failure mode this function exists to prevent.

        # validate output directory
        if (-not (Test-Path -Path $Path -PathType 'Container')) {
            $ErrorParams = @{
                Category    = 'ObjectNotFound'
                Message     = "-Path '${Path}' is not an existing directory."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
        $Path = (Resolve-Path -Path $Path).Path

        # parse date range
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $LocalStart = $DateRange.StartUtc.ToLocalTime()
        $LocalEnd = $DateRange.EndUtc.ToLocalTime()

        # Align chunk boundaries to the Sunday on or before the range start.
        # DayOfWeek is 0 for Sunday, so subtracting it from the date lands on
        # that week's Sunday midnight in local time.
        $FirstSunday = $LocalStart.Date.AddDays( - [int]$LocalStart.DayOfWeek)

        # Build one chunk per calendar week. The queried window is clamped to
        # the range the caller actually asked for, so the first and last weeks
        # can be partial; that is recorded in each file's metadata rather than
        # silently widening the pull.
        $WeekChunks = [System.Collections.Generic.List[hashtable]]::new()
        $WeekStart = $FirstSunday
        while ($WeekStart -lt $LocalEnd) {
            $WeekEnd = $WeekStart.AddDays(7)
            $QueryStart = $WeekStart -gt $LocalStart ? $WeekStart : $LocalStart
            $QueryEnd = $WeekEnd -lt $LocalEnd ? $WeekEnd : $LocalEnd
            $WeekChunks.Add(@{
                    WeekStart = $WeekStart
                    Start     = $QueryStart
                    End       = $QueryEnd
                    Partial   = ($QueryStart -gt $WeekStart) -or ($QueryEnd -lt $WeekEnd)
                })
            $WeekStart = $WeekEnd
        }
        # query newest first so the most recent activity lands on disk soonest
        $WeekChunks.Reverse()
        $WeekCount = $WeekChunks.Count

        # -Week numbers follow the same newest-first order as the console labels,
        # so they can only be checked once the range has been split into weeks
        if ($Week) {
            $OutOfRange = @($Week | Where-Object { $_ -gt $WeekCount })
            if ($OutOfRange.Count -gt 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "-Week $($OutOfRange -join ', ') out of range. The " +
                    "requested date range has ${WeekCount} weeks."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: -Week limits the run to week(s) $($Week -join ', ')")
        }

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Range $($LocalStart.ToString('yyyy-MM-dd HH:mm')) to " +
            "$($LocalEnd.ToString('yyyy-MM-dd HH:mm')) split into ${WeekCount} " +
            "weekly chunks [$Elapsed]")
    }

    process {

        # tenant label for file names
        $DomainName = Get-DefaultDomain

        if ($Week) {
            $WeekList = ($Week | Sort-Object -Unique) -join ', '
            Write-IRT ("Querying week(s) ${WeekList} of ${WeekCount} of Teams " +
                "external contact records for ${DomainName}.")
        }
        else {
            Write-IRT ("Querying ${WeekCount} weeks of Teams external contact " +
                "records for ${DomainName}.")
        }

        $ChunkIndex = 0
        foreach ($Chunk in $WeekChunks) {
            $ChunkIndex++

            # -Week runs only the named weeks. Every week still counts toward the
            # index so each label matches the run being retried.
            if ($Week -and $ChunkIndex -notin $Week) { continue }

            $WeekStartString = $Chunk.WeekStart.ToString('yy-MM-dd')
            $FileNameBase = "${FileNamePrefix}_${DomainName}_${WeekStartString}"
            $XmlOutputPath = Join-Path -Path $Path -ChildPath "${FileNameBase}.xml"

            $WindowFormat = 'M/d/yy h:mmtt'
            $WindowStart = $Chunk.Start.ToString($WindowFormat)
            $WindowEnd = $Chunk.End.ToString($WindowFormat)
            $Label = "Week ${ChunkIndex} of ${WeekCount} (${WindowStart} to ${WindowEnd})"

            # resume support: a week that already has a file was already queried.
            # Weeks named in -Week are re-queried anyway, because a failed query
            # still writes a file holding DATA MISSING markers.
            $FileExists = Test-Path -Path $XmlOutputPath -PathType 'Leaf'
            if ($FileExists -and -not ($Force -or $Week)) {
                Write-IRT "${Label}: file exists, skipping. Use -Force to re-query."
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Skipping existing file ${XmlOutputPath}")
                continue
            }

            Write-IRT "${Label}: querying."
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: ${Label} to ${XmlOutputPath} [$Elapsed]")

            # Reuse the shared UAL query function so this pull inherits its
            # paging, token refresh, retry/backoff, and data-gap marking.
            $UalParams = @{
                AllUsers             = $true
                Operation            = $Operations
                Start                = $Chunk.Start.ToString('yyyy-MM-dd HH:mm:ss')
                End                  = $Chunk.End.ToString('yyyy-MM-dd HH:mm:ss')
                ChunkDays            = 7
                ChunkDelaySeconds    = $ChunkDelaySeconds
                ThrottleDelaySeconds = $ThrottleDelaySeconds
                ResultLimit          = $ResultLimit
                Excel                = $false
                Xml                  = $false
                PassThru             = $true
            }
            $Returned = Get-IRTUnifiedAuditLog @UalParams

            # strip the child function's metadata row; this function writes its
            # own, describing the week rather than the whole requested range
            $Records = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Record in $Returned) {
                if ($null -eq $Record) { continue }
                if ($Record.Metadata) { continue }
                $Records.Add($Record)
            }

            $RecordCount = $Records.Count
            $GapCount = @($Records | Where-Object { $_.IRTDataGap }).Count
            if ($GapCount -gt 0) {
                Write-IRT ("${Label}: ${GapCount} DATA MISSING marker(s) present; " +
                    "this week is incomplete.") -Level Warn
            }

            # build metadata for this week
            $WeekLabel = $Chunk.WeekStart.ToString('M/d/yy')
            $TitleSuffix = " for ${DomainName}. Week of ${WeekLabel}, " +
            "${WindowStart} to ${WindowEnd}."
            $Metadata = [pscustomobject]@{
                Metadata        = $true
                FileNamePrefix  = $FileNamePrefix
                FileName        = $FileNameBase
                SheetTitle      = $SheetTitle
                Title           = "${SheetTitle}${TitleSuffix}"
                TitleSuffix     = $TitleSuffix
                ProfileTag      = $null
                WeekStart       = $Chunk.WeekStart
                CoveredStartUtc = $Chunk.Start.ToUniversalTime()
                CoveredEndUtc   = $Chunk.End.ToUniversalTime()
                PartialWeek     = $Chunk.Partial
                RecordCount     = $RecordCount
                DataGapCount    = $GapCount
                Operations      = $Operations
                TenantIdOnlyOps = $TenantIdOperations
            }
            $Records.Insert(0, $Metadata)

            # A file is written even when the week is empty, so that a missing
            # file means "not queried" rather than "nothing found".
            $OutputPathString = Split-Path -Path $XmlOutputPath -Parent
            Write-IRT "${Label}: ${RecordCount} records. Saving to ${OutputPathString}"
            $Records | Export-Clixml -Depth 10 -Path $XmlOutputPath
        }

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Complete [$Elapsed]"
    }
}
