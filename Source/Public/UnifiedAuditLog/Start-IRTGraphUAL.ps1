function Start-IRTGraphUAL {
    <#
    .SYNOPSIS
    Starts a Unified Audit Log search through the Microsoft Graph audit search API.

    .DESCRIPTION
    Submits one or more server-side audit log query jobs and, by default, waits for them
    and downloads the results.

    This is the duplicate-free alternative to Get-IRTUnifiedAuditLog. That function runs
    several overlapping Search-UnifiedAuditLog queries per user and pages each with
    ReturnLargeSet, which returns the same event more than once, sometimes under a
    different Identity so deduplication misses it. The Graph API runs one server-side job
    per filter set and returns each record once with a stable id, and it is not capped at
    50,000 records.

    The trade is speed. The service schedules these jobs in batches: expect roughly
    35 minutes before results are ready, whatever the size of the search. A one hour
    window costs the same as ninety days. Use Get-IRTUnifiedAuditLog when time matters and
    this when completeness does.

    Jobs run server-side, so Ctrl+C during the wait is safe. The jobs keep running and can
    be collected later with Wait-IRTGraphUAL or Receive-IRTGraphUAL. They cannot be
    cancelled or deleted; the API offers neither, and they expire on their own after about
    thirty days.

    Each search submits a group of jobs, one per identifier. For a user that means three
    keyword jobs: their address, their object id, and their object id with the dashes
    stripped, because workloads differ in which form they record. Keyword matching also
    finds records where the user was the target of someone else's action, not only ones
    they performed themselves.

    Requires a Microsoft Graph connection with AuditLogsQuery.Read.All.

    .PARAMETER UserObject
    One or more user objects to search for. Mutually exclusive with -AllUsers and
    -ServicePrincipal. Falls back to the global session objects if omitted.

    .PARAMETER AllUsers
    Search the whole tenant. Mutually exclusive with -UserObject and -ServicePrincipal.
    The service allows only one unfiltered job to be open at a time, so this is refused
    while another is still running.

    .PARAMETER ServicePrincipal
    One or more service principal objects to search for. Mutually exclusive with
    -UserObject and -AllUsers.

    .PARAMETER Days
    Number of days back to search. Cannot be combined with -Start or -End.

    .PARAMETER Start
    Start of an absolute date range, as any parseable date string. Used with -End.

    .PARAMETER End
    End of an absolute date range, as any parseable date string. Used with -Start.

    .PARAMETER Operation
    Restrict the search to specific UAL operation names.

    .PARAMETER RecordType
    Restrict the search to one or more UAL record types, for example MicrosoftTeams.
    Unlike Search-UnifiedAuditLog, the Graph API accepts several in a single job.

    .PARAMETER RiskyOperation
    Search only the high risk operations listed in the operations sheet.

    .PARAMETER SignInLog
    Search only UAL sign-in operations.

    .PARAMETER FreeText
    One or more free text strings. The API takes a single keyword per job, so each string
    adds a job to the group.

    .PARAMETER IpAddress
    Restrict the search to one or more client IP addresses.

    .PARAMETER ResultLimit
    Maximum records to retrieve when the results are downloaded. Default: 50000.

    .PARAMETER NoWait
    Submit the jobs and return immediately instead of waiting for them.

    .PARAMETER Audio
    Play a sound when the search finishes. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook when they are downloaded. Default: $true.

    .PARAMETER Xml
    Export the raw records alongside the workbook. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data where available when building the workbook.

    .PARAMETER NamePrefix
    Prefix for the job display names. Defaults to IRT_Config.JobNamePrefix, the
    same marker used for email compliance searches.

    .EXAMPLE
    ```powershell
    Start-IRTGraphUAL -UserObject $User -Days 90
    ```
    Searches 90 days for a user, waits, and exports the results.

    .EXAMPLE
    ```powershell
    Start-IRTGraphUAL -UserObject $User -Days 30 -NoWait
    ```
    Submits the jobs and returns. Collect them later with Wait-IRTGraphUAL.

    .EXAMPLE
    ```powershell
    Start-IRTGraphUAL -AllUsers -RecordType 'MicrosoftTeams' -Days 7
    ```
    Searches the whole tenant for Teams records over the last week.

    .EXAMPLE
    ```powershell
    Start-IRTGraphUAL -ServicePrincipal $Sp -Days 180
    ```
    Searches 180 days for a service principal by object id and app id.

    .OUTPUTS
    [pscustomobject] describing the submitted group: GroupId, Stamp, ObjectName,
    ProfileTag, Days, StartUtc, EndUtc and a Jobs collection. Also appended to
    $Global:IRT_GraphUAL.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('GraphUAL', 'StartGraphUAL')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'UserObject')]
    [OutputType([System.Collections.Generic.List[psobject]])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'UserObject')]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [Parameter(Position = 0, ParameterSetName = 'ServicePrincipal')]
        [Alias('ServicePrincipals')]
        [psobject[]] $ServicePrincipal,

        [int] $Days,
        [string] $Start,
        [string] $End,

        [Alias('Operations')]
        [string[]] $Operation,

        [Alias('RecordTypes')]
        [string[]] $RecordType,

        [Alias('RiskyOperations')]
        [switch] $RiskyOperation,

        [Alias('SignInLogs')]
        [switch] $SignInLog,

        [string[]] $FreeText,

        [string[]] $IpAddress,

        [int] $ResultLimit = 50000,

        [switch] $NoWait,

        [boolean] $Audio = $true,

        [boolean] $Excel = $true,

        [boolean] $Xml = $Global:IRT_Config.ExportXml,

        [switch] $Cached,

        [string] $NamePrefix = (Get-IRTJobNamePrefix)
    )

    begin {
        Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        Update-IRTToken -Service 'Graph'

        # profiles mirror Get-IRTUnifiedAuditLog so both paths produce the same
        # workbook titles, file names and sheet selection
        $ProfileTable = [ordered]@{
            Default         = [pscustomobject]@{
                FilePrefix   = 'UnifiedAuditLogs'
                SheetTitle   = 'Unified audit logs'
                DefaultDays  = 30
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = 'Default'
            }
            RiskyOperations = [pscustomobject]@{
                FilePrefix   = 'UALRiskyOperations'
                SheetTitle   = 'UAL risky operations'
                DefaultDays  = 180
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = 'RiskyOperations'
            }
            SignInLogs      = [pscustomobject]@{
                FilePrefix   = 'UALSignInLogs'
                SheetTitle   = 'UAL sign-in logs'
                DefaultDays  = 180
                Operations   = [string[]]@('UserLoggedIn', 'UserLoggedOff', 'UserLoginFailed')
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = 'SignInLogs'
            }
        }
        $ActiveProfile = switch ($true) {
            $RiskyOperation { $ProfileTable['RiskyOperations']; break }
            $SignInLog { $ProfileTable['SignInLogs']; break }
            default { $ProfileTable['Default'] }
        }

        # warn early on record types this tenant has never logged. Never blocks: the
        # operations sheet only knows what has been witnessed, so absence is not proof
        # of an invalid value.
        if ($RecordType) {
            $null = Test-GraphUALRecordType -RecordType $RecordType -Cached:$Cached
        }

        # resolve the targets
        switch ($ParameterSet) {
            'UserObject' {
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $LoopObjects = $UserObject
                }
                else {
                    $LoopObjects = Get-GlobalUserObject
                    if (($LoopObjects | Measure-Object).Count -eq 0) {
                        Write-IRT ('No user objects passed or found in global ' +
                            'variables.') -Level Error
                        return
                    }
                }
            }
            'AllUsers' {
                $null = $AllUsers
                $LoopObjects = @([pscustomobject]@{ UserPrincipalName = 'AllUsers' })
            }
            'ServicePrincipal' {
                $LoopObjects = $ServicePrincipal
            }
        }

        # date range
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $ActiveProfile.DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $Days = $DateRange.Days

        # operations: explicit values plus whatever the profile contributes
        $OperationsSet = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($o in $Operation) { [void]$OperationsSet.Add($o) }
        if ($RiskyOperation) {
            $ActiveProfile.Operations = Get-GraphUALRiskyOperation
        }
        foreach ($o in $ActiveProfile.Operations) { [void]$OperationsSet.Add($o) }

        $Results = [System.Collections.Generic.List[psobject]]::new()
    }

    process {

        foreach ($LoopObject in $LoopObjects) {

            #region TARGET
            switch ($ParameterSet) {
                'UserObject' {
                    $UserId = $LoopObject.Id
                    $UserEmail = $LoopObject.UserPrincipalName
                    $ObjectName = $UserEmail -split '@' | Select-Object -First 1
                }
                'AllUsers' {
                    $ObjectName = Get-DefaultDomain
                }
                'ServicePrincipal' {
                    $ObjectName = $LoopObject.DisplayName -replace '[^a-zA-Z0-9]', ''
                }
            }
            #endregion TARGET

            #region FILTER SETS
            # one entry per job. Filters common to the whole group are added afterwards,
            # so this only describes what makes each job different.
            $FilterSets = [System.Collections.Generic.List[hashtable]]::new()

            switch ($ParameterSet) {
                'UserObject' {
                    # Keyword matching does the real work. It returns a superset of the
                    # actor filter (measured: 85 records against 82, with none unique to
                    # the actor filter) because it also catches records where this user
                    # was the target of someone else's action. The actor filter adds
                    # nothing, and cannot match a GUID at all, so it is not used.
                    #
                    # The identifier is searched in all three forms the audit log stores
                    # it in, matching the query set Get-IRTUnifiedAuditLog uses: the
                    # address, the object id, and the object id with dashes stripped.
                    # Workloads are inconsistent about which GUID format they record.
                    $Identifiers = [ordered]@{}
                    if ($UserEmail) { $Identifiers['address'] = [string]$UserEmail }
                    if ($UserId) {
                        $Identifiers['object id'] = [string]$UserId
                        $NoDashes = [string]$UserId -replace '-', ''
                        if ($NoDashes -ne [string]$UserId) {
                            $Identifiers['object id (no dashes)'] = $NoDashes
                        }
                    }
                    foreach ($Key in $Identifiers.Keys) {
                        $FilterSets.Add(@{
                                Label   = "keyword $Key $($Identifiers[$Key])"
                                Filters = @{ keywordFilter = $Identifiers[$Key] }
                            })
                    }
                }
                'ServicePrincipal' {
                    # a service principal has no address to search, so both of its
                    # identifiers go through keyword matching, each in dashed and
                    # dashless form for the same reason as a user's object id
                    $Identifiers = [ordered]@{}
                    foreach ($Pair in @(
                            @{ Name = 'object id'; Value = [string]$LoopObject.Id },
                            @{ Name = 'app id'; Value = [string]$LoopObject.AppId })) {
                        if (-not $Pair.Value) { continue }
                        $Identifiers[$Pair.Name] = $Pair.Value
                        $NoDashes = $Pair.Value -replace '-', ''
                        if ($NoDashes -ne $Pair.Value) {
                            $Identifiers["$($Pair.Name) (no dashes)"] = $NoDashes
                        }
                    }
                    foreach ($Key in $Identifiers.Keys) {
                        $FilterSets.Add(@{
                                Label   = "keyword $Key $($Identifiers[$Key])"
                                Filters = @{ keywordFilter = $Identifiers[$Key] }
                            })
                    }
                }
                'AllUsers' {
                    $FilterSets.Add(@{ Label = 'all users'; Filters = @{} })
                }
            }

            # each free text string needs its own job: keywordFilter takes one value
            foreach ($Text in $FreeText) {
                if (-not $Text) { continue }
                $FilterSets.Add(@{
                        Label   = "keyword $Text"
                        Filters = @{ keywordFilter = $Text }
                    })
            }

            if ($FilterSets.Count -eq 0) {
                Write-IRT "No filters could be built for ${ObjectName}. Skipping." -Level Warn
                continue
            }
            #endregion FILTER SETS

            #region UNFILTERED PRE-CHECK
            # The service permits only one open unfiltered job at a time and refuses the
            # second with TooManyRequests, after the SDK has spent about 24 seconds
            # retrying. Check first so the user gets a clear message instead.
            $HasUnfiltered = $FilterSets | Where-Object {
                ($_.Filters.Keys.Count -eq 0) -and -not $OperationsSet.Count -and
                -not $RecordType -and -not $IpAddress
            }
            if ($HasUnfiltered) {
                $Blocking = Get-GraphUALOpenUnfilteredJob
                if ($Blocking) {
                    Write-IRT ('An unfiltered audit search is already running and the ' +
                        'service allows only one at a time:') -Level Error
                    Write-IRT "  $($Blocking.displayName) [$($Blocking.status)]" -Level Error
                    Write-IRT ('Wait for it to finish, or narrow this search with ' +
                        '-Operation, -RecordType or -IpAddress.') -Level Error
                    continue
                }
            }
            #endregion UNFILTERED PRE-CHECK

            #region SUBMIT
            $GroupId = ([guid]::NewGuid().ToString('N')).Substring(0, 8)
            $Stamp = (Get-Date).ToString('yyMMdd-HHmm')
            $Target = "${ObjectName} (${Days} days, $($FilterSets.Count) job(s))"

            if (-not $PSCmdlet.ShouldProcess($Target, 'Start audit search')) { continue }

            Write-IRT "Submitting $($FilterSets.Count) audit search job(s) for ${ObjectName}."

            $Jobs = [System.Collections.Generic.List[psobject]]::new()
            $Index = 0
            foreach ($Set in $FilterSets) {
                $Index++

                $NameParams = @{
                    ObjectName = $ObjectName
                    ProfileTag = $ActiveProfile.ProfileTag
                    Days       = $Days
                    GroupId    = $GroupId
                    Index      = $Index
                    Stamp      = $Stamp
                    Prefix     = $NamePrefix
                }
                $DisplayName = New-GraphUALName @NameParams

                $Body = @{
                    displayName         = $DisplayName
                    filterStartDateTime = $DateRange.StartString
                    filterEndDateTime   = $DateRange.EndString
                }
                foreach ($Key in $Set.Filters.Keys) { $Body[$Key] = $Set.Filters[$Key] }
                if ($OperationsSet.Count -gt 0) {
                    $Body['operationFilters'] = [string[]]$OperationsSet
                }
                if ($RecordType) { $Body['recordTypeFilters'] = [string[]]$RecordType }
                if ($IpAddress) { $Body['ipAddressFilters'] = [string[]]$IpAddress }

                $Response = Invoke-GraphUALRequest -Method 'POST' -Path 'queries' -Body $Body

                if ($Response.Ok) {
                    Write-IRT "  [$Index] $($Set.Label) -> $($Response.Result.id)"
                    $Jobs.Add([pscustomobject]@{
                            Id          = [string]$Response.Result.id
                            Index       = $Index
                            Label       = $Set.Label
                            DisplayName = $DisplayName
                            Status      = [string]$Response.Result.status
                            Body        = $Body
                        })
                }
                else {
                    Write-IRT ("  [$Index] $($Set.Label) failed: " +
                        "$($Response.Status)") -Level Error
                    Write-PSFMessage -Level Warning -Message (
                        "${FunctionName}: create failed for '$DisplayName': $($Response.Error)")
                }
            }

            if ($Jobs.Count -eq 0) {
                Write-IRT "No audit search jobs were created for ${ObjectName}." -Level Error
                continue
            }
            #endregion SUBMIT

            $Group = [pscustomobject]@{
                GroupId     = $GroupId
                Stamp       = $Stamp
                ObjectName  = $ObjectName
                ProfileTag  = $ActiveProfile.ProfileTag
                FilePrefix  = $ActiveProfile.FilePrefix
                SheetTitle  = $ActiveProfile.SheetTitle
                Days        = $Days
                StartUtc    = $DateRange.StartUtc
                EndUtc      = $DateRange.EndUtc
                Jobs        = $Jobs
                Created     = Get-Date
                ResultLimit = $ResultLimit
            }

            if ($Global:IRT_GraphUAL -isnot [System.Collections.Generic.List[psobject]]) {
                $Global:IRT_GraphUAL = [System.Collections.Generic.List[psobject]]::new()
            }
            $Global:IRT_GraphUAL.Add($Group)
            $Results.Add($Group)

            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: submitted group $GroupId with $($Jobs.Count) job(s) [$Elapsed]")
        }
    }

    end {
        if ($Results.Count -eq 0) { return }

        if ($NoWait) {
            Write-IRT ("Submitted. Results take about 35 minutes. Collect them with " +
                "Wait-IRTGraphUAL.")
            return $Results
        }

        Write-IRT ('Waiting for results. This usually takes about 35 minutes. ' +
            'Ctrl+C is safe, the jobs keep running.')

        $WaitParams = @{
            Group  = @($Results.GroupId)
            Audio  = $Audio
            Excel  = $Excel
            Xml    = $Xml
            Cached = $Cached
        }
        Wait-IRTGraphUAL @WaitParams
    }
}
