function Get-IRTUnifiedAuditLog {
    <#
    .SYNOPSIS
    Runs multiple queries to pull all Unified Audit Log records related to a specific user.

    .DESCRIPTION
    Queries the Microsoft 365 Unified Audit Log via Exchange Online for activity related
    to one or more users, a service principal, or all users in the tenant. Runs several
    categorised queries in parallel (e.g. SharePoint, Exchange, Teams, Azure AD) and
    exports each category to a separate sheet in an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.
    Requires an active Exchange Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Mutually exclusive with -AllUsers and
    -ServicePrincipal. Falls back to global session objects if omitted.

    .PARAMETER AllUsers
    Query the UAL for all users in the tenant. Mutually exclusive with -UserObject and
    -ServicePrincipal.

    .PARAMETER ServicePrincipal
    One or more service principal objects to query. Mutually exclusive with -UserObject
    and -AllUsers.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER ChunkDays
    Splits the requested date range into sub-queries of this many days each, querying
    newest to oldest and merging the results. Default: 182. Search-UnifiedAuditLog
    degrades and times out on wide ranges, so large pulls (e.g. -AllUsers over a long
    range) are broken into windows small enough to return reliably. Pass a smaller
    value to further reduce the chance of failed queries due to timeouts.

    .PARAMETER ChunkDelaySeconds
    Seconds to pause between chunk queries. A small pause reduces the chance of
    tripping Exchange throttling limits on large multi-chunk pulls. Default: 2.
    Set to 0 to disable. Only applies when the range spans more than one chunk.

    .PARAMETER ThrottleDelaySeconds
    Base backoff (seconds) used when a Search-UnifiedAuditLog query fails (timeout,
    throttling, or a dropped session). Backoff grows exponentially per retry
    (base, base*2, base*4...) and the token is refreshed between attempts. The full
    exception is written to the PSFramework debug log for troubleshooting. Default: 60.

    .PARAMETER ResultLimit
    Maximum total records to retrieve across all queries and date chunks. Stops at the
    next 5000-record page boundary after the limit is reached. Since queries run from
    the most recent chunk backward, the most recent events are retained. Default: 50000.

    .PARAMETER Operation
    Filter results to specific UAL operation names.

    .PARAMETER RiskyOperation
    Filter to a predefined list of high-risk operations.

    .PARAMETER SignInLog
    Filter to only UAL sign-in operations.

    .PARAMETER FreeText
    One or more free-text search strings passed to Search-UnifiedAuditLog.

    .PARAMETER RecordType
    Filter results to one or more UAL record types (e.g. MicrosoftTeams,
    ExchangeItem, AzureActiveDirectoryStsLogon). Search-UnifiedAuditLog accepts a
    single record type per call, so every query is run once per record type given.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER WaitOnMessageTrace
    Wait for any pending message trace jobs before querying. Intended for use when running
    playbook. (running functions in parallel) Default: $false.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data where available.

    .EXAMPLE
    ```powershell
    Get-IRTUnifiedAuditLog
    ```
    Queries the UAL for the last 30 days for the user in the global session.

    .EXAMPLE
    ```powershell
    Get-IRTUnifiedAuditLog -UserObject $User -Days 90
    ```
    Queries 90 days of UAL activity for a specific user.

    .EXAMPLE
    ```powershell
    Get-IRTUnifiedAuditLog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'
    ```
    Finds all FileDeleted events for any user during April 2026.

    .EXAMPLE
    ```powershell
    Get-IRTUnifiedAuditLog -UserObject $User -Days 30 -RecordType 'MicrosoftTeams'
    ```
    Pulls only Microsoft Teams records for the user over the last 30 days.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.11.0
    1.10.0 - Added -RecordType to filter queries by UAL record type.
    1.9.0 - Exposed -ChunkDays to control date-chunk size, added per-chunk token
    refresh so long multi-chunk runs don't outlive the token's refresh window, an
    inter-chunk delay (-ChunkDelaySeconds), and retry-with-backoff
    (-ThrottleDelaySeconds) on failed queries, with full exceptions logged to debug.
    A query that still fails after all retries now raises an error and inserts a
    visible "DATA MISSING" marker row into the results so incomplete pulls are
    obvious in the exported workbook, rather than silently returning partial data.
    1.8.0 - Added date chunking for ranges over 182 days; ResultLimit now caps total
    records across all queries rather than per-query.
    1.7.0 - Added -ResultLimit to cap records pulled per query before paging stops.
    1.6.0 - Added profile tags to allow generating specific sheets in Show-IRTUnifiedAuditLog.
    1.5.1 - Added function name to all output.
    1.5.0 - Added -AllUsers option, added test timers.
    1.4.0 - Updating to add metadata object, use shorter file names.
    1.3.0 - Updated to output objects.
    #>
    [Alias('GetUALog', 'GetUALogs', 'UALog', 'UALogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'UserObject')]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [Parameter(Position = 0, ParameterSetName = 'ServicePrincipal')]
        [Alias( 'ServicePrincipals' )]
        [psobject[]] $ServicePrincipal,

        [int] $Days, # default value set at #DEFAULTDAYS
        [string] $Start,
        [string] $End,

        # split the date range into sub-queries of this many days each
        [ValidateRange(1, 3650)]
        [int] $ChunkDays = 182,

        # seconds to pause between chunk queries to avoid tripping throttle limits
        [ValidateRange(0, 3600)]
        [int] $ChunkDelaySeconds = 2,

        # base seconds for retry backoff when a query fails (timeout/throttle/session)
        [ValidateRange(1, 3600)]
        [int] $ThrottleDelaySeconds = 60,

        [int] $ResultLimit = 50000,

        [Alias('Operations')]
        [string[]] $Operation,
        [Alias('RiskyOperations')]
        [switch] $RiskyOperation,
        [Alias('SignInLogs')]
        [switch] $SignInLog,

        [string[]] $FreeText,

        [Alias('RecordTypes')]
        [string[]] $RecordType,

        [boolean] $Excel = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        Import-IRTModule -Name 'ExchangeOnlineManagement', 'ImportExcel', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # max attempts per Search-UnifiedAuditLog call before giving up on it
        $MaxRetry = 3

        # Warnings that mean the query was refused or dropped rather than genuinely
        # empty. EXO returns 401s from the sync-search path, and some transport
        # faults, as a WARNING plus an empty result set instead of a terminating
        # error. Left alone those are indistinguishable from a tenant with no
        # matching audit activity, so a refused query would be reported to the
        # analyst as 'no activity' - the worst way for an IR tool to fail.
        $UalFailureWarning = 'Unauthorized|Failed to process request via|HttpRequestException'

        # helper: run a Search-UnifiedAuditLog call with retry. Exchange/UAL surfaces
        # transient failures (throttling, timeouts, dropped sessions) with varied and
        # unstable error text, so rather than match specific messages we retry on ANY
        # terminal error, refreshing the token between attempts, and record the full
        # exception to the debug log for future troubleshooting. Returns the cmdlet's
        # output, or rethrows the last error if every attempt failed so the caller
        # can surface it and insert a visible data-gap marker.
        function Invoke-IRTUalSearchWithRetry {
            param(
                [hashtable] $SearchParams,
                [string]    $Label,
                [int]       $MaxRetry,
                [int]       $ThrottleDelaySeconds
            )
            $Attempt = 0
            while ($true) {
                $Attempt++
                try {
                    # These warnings come from inside the EXO REST plumbing and do
                    # NOT honour -WarningVariable (verified against a live tenant),
                    # so merge the warning stream into the output and split it back
                    # apart by record type.
                    $CallParams = @{}
                    $SearchParams.GetEnumerator() |
                        ForEach-Object { $CallParams[$_.Key] = $_.Value }
                    $CallParams['ErrorAction'] = 'Stop'

                    $Merged = Search-UnifiedAuditLog @CallParams 3>&1

                    $WarningType = [System.Management.Automation.WarningRecord]
                    $Warnings = @($Merged | Where-Object { $_ -is $WarningType })
                    $Result = @($Merged | Where-Object { $_ -isnot $WarningType })

                    $Blocked = @($Warnings |
                            Where-Object { $_ -match $UalFailureWarning })
                    # pass through anything that was not a refusal
                    foreach ($Warning in @($Warnings |
                                Where-Object { $_ -notmatch $UalFailureWarning })) {
                        Write-IRT "$Warning" -Level Warn
                    }
                    if ($Blocked.Count -gt 0 -and $Result.Count -eq 0) {
                        throw ('Search returned no records and warned: ' +
                            "$($Blocked[0])")
                    }
                    return $Result
                }
                catch {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    # record full exception details for future troubleshooting
                    Write-PSFMessage -Level Warning -ErrorRecord $_ -Message (
                        "${FunctionName}: ${Label} failed on attempt " +
                        "${Attempt}/${MaxRetry}: $($_.Exception.GetType().FullName): " +
                        "$($_.Exception.Message) [$Elapsed]")

                    if ($Attempt -ge $MaxRetry) {
                        Write-PSFMessage -Level Warning -ErrorRecord $_ -Message (
                            "${FunctionName}: ${Label} gave up after ${MaxRetry} " +
                            "attempts; rethrowing. [$Elapsed]")
                        # rethrow so the caller surfaces the error and drops a
                        # visible data-gap marker into the results
                        throw
                    }

                    # exponential backoff, then refresh the token in case the
                    # failure was an expired or dropped Exchange session
                    $Wait = [int]($ThrottleDelaySeconds * [Math]::Pow(2, $Attempt - 1))
                    Write-IRT ("${Label} error. Backing off ${Wait}s then retrying " +
                        "(${Attempt}/${MaxRetry})...") -Level Warn
                    Start-Sleep -Seconds $Wait
                    Update-IRTToken -Service 'Exchange'
                }
            }
        }

        # helper: build a visible "data missing" marker row to insert when a query
        # fails after all retries. It mimics a UAL record closely enough to flow
        # through dedup, sort, and the sheet builders, so an incomplete dataset is
        # obvious in the spreadsheet itself - not just in the console/debug error.
        # The full failure detail (window, query, exception) lands in the Raw column
        # via AuditData.
        function New-IRTUalGapMarker {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Builds an in-memory marker object; changes no state.')]
            param(
                [hashtable] $DateChunk,
                [string]    $Label,
                [System.Management.Automation.ErrorRecord] $ErrorRecord
            )
            $GapAuditData = [ordered]@{
                Operation      = '*** DATA MISSING - query failed; results incomplete ***'
                Workload       = 'IRT'
                ResultStatus   = 'Failed'
                FailedQuery    = $Label
                WindowStartUtc = $DateChunk.Start.ToString('yyyy-MM-dd HH:mm:ssZ')
                WindowEndUtc   = $DateChunk.End.ToString('yyyy-MM-dd HH:mm:ssZ')
                Error          = $ErrorRecord.Exception.Message
            } | ConvertTo-Json -Compress
            return [pscustomobject]@{
                Identity     = "IRT-DATA-GAP-$([guid]::NewGuid())"
                IRTDataGap   = $true
                CreationDate = $DateChunk.End
                RecordType   = 'IRT_QUERY_FAILURE'
                Operations   = 'DataMissing'
                UserIds      = '*** DATA MISSING - INCOMPLETE RESULTS ***'
                AuditData    = $GapAuditData
            }
        }

        # query profiles - add new entries here to support additional modes
        $ProfileTable = [ordered]@{
            Default = [pscustomobject]@{
                FilePrefix   = 'UnifiedAuditLogs'
                SheetTitle   = 'Unified audit logs'
                DefaultDays  = 1
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = $null
            }
            RiskyOperations = [pscustomobject]@{
                FilePrefix   = 'UALRiskyOperations'
                SheetTitle   = 'UAL risky operations'
                DefaultDays  = 180
                Operations   = [string[]]@()
                ShowFunction = 'Show-IRTUnifiedAuditLog'
                ProfileTag   = $null
            }
            SignInLogs = [pscustomobject]@{
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

        # get/create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $LoopObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $LoopObjects = Get-GlobalUserObject

                    # if none found, exit
                    if ( -not $LoopObjects -or $LoopObjects.Count -eq 0 ) {
                        $Msg = "No user objects passed or found in global variables."
                        Write-IRT $Msg -Level Error
                        return
                    }
                    if (($LoopObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used, ' +
                            'no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'AllUsers' {
                $null = $AllUsers  # switch controls parameter set; value not needed
                # build user object with null principal name
                $LoopObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = 'AllUsers'
                    }
                )
            }
            'ServicePrincipal' {
                $LoopObjects = $ServicePrincipal
            }
        }

        # get client domain name for file output
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Get-AcceptedDomain [$Elapsed]"
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1

        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $ActiveProfile.DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc

        # build date chunks, most recent first
        $DateChunks = [System.Collections.Generic.List[hashtable]]::new()
        $ChunkEnd = $EndDateUtc
        while ($ChunkEnd -gt $StartDateUtc) {
            $ProposedStart = $ChunkEnd.AddDays(-$ChunkDays)
            $ChunkStart = $ProposedStart -gt $StartDateUtc ? $ProposedStart : $StartDateUtc
            $DateChunks.Add(@{ Start = $ChunkStart; End = $ChunkEnd })
            $ChunkEnd = $ChunkStart
        }
        $ChunkCount = $DateChunks.Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        if ($ChunkCount -gt 1) {
            $ChunkMsg = "Date range is $Days days, split into $ChunkCount ${ChunkDays}-day chunks."
            Write-IRT $ChunkMsg
            Write-PSFMessage -Level 8 -Message "${FunctionName}: $ChunkMsg [$Elapsed]"
        }
        else {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Date range is $Days days (single chunk). [$Elapsed]")
        }

        # set file name date to query end date
        $FileNameDateString = $EndDateUtc.ToLocalTime().ToString('yy-MM-dd_HH-mm')

        $OperationsSet = [System.Collections.Generic.Hashset[string]]::new()
        # add user specified operations
        foreach ($o in $Operation) { [void]$OperationsSet.Add($o) }
        # populate profile operations
        if ($RiskyOperation) {
            # import alloperations sheet
            $OperationsSheetPath = $Global:IRT_Config.AllOperationsSheetPath
            $ExcelParams = @{
                Path          = $OperationsSheetPath
                WorksheetName = 'Operations'
            }
            $OperationsSheetData = Import-Excel @ExcelParams

            # get high risk operations and store in active profile
            $HighRisk = $OperationsSheetData | Where-Object { $_.Risk -eq 'High' }
            $ActiveProfile.Operations = $HighRisk.Operation
        }
        # add profile operations to set
        foreach ($o in $ActiveProfile.Operations) { [void]$OperationsSet.Add($o) }
    }

    process {

        #region USER LOOP

        foreach ($LoopObject in $LoopObjects) {

            $AllLogs = [System.Collections.Generic.List[psobject]]::new()

            # users
            switch ( $ParameterSet ) {
                'UserObject' {
                    $UserId = $LoopObject.Id
                    $UserIdNoDashes = $UserId -replace '-', ''
                    $UserEmail = $LoopObject.UserPrincipalName
                    $ObjectName = $UserEmail -split '@' | Select-Object -First 1
                }
                'AllUsers' {
                    $ObjectName = $DomainName
                    # don't add a user filter
                }
                'ServicePrincipal' {
                    $ServicePrincipalId = $LoopObject.Id
                    $ServicePrincipalIdNoDash = $LoopObject.Id -replace '-', ''
                    $AppId = $LoopObject.AppId
                    $AppIdNoDash = $LoopObject.AppId -replace '-', ''
                    $ObjectName = $LoopObject.DisplayName -replace '[^a-zA-Z0-9]', ''
                }
            }
            $FileNamePrefix = $ActiveProfile.FilePrefix
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}" +
            "_${ObjectName}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleSuffix = " for ${ObjectName}. Covers ${Days} days, " +
            "${TitleStartDate} to ${TitleEndDate}."

            # build query params
            $BaseParams = @{
                ResultSize     = 5000
                SessionCommand = 'ReturnLargeSet'
                Formatted      = $true
            }

            # add operations, if specified
            if (($OperationsSet | Measure-Object).Count -gt 0) {
                $BaseParams['Operations'] = $OperationsSet
            }

            #region QUERY TABLE
            switch ( $ParameterSet ) {
                'UserObject' {
                    $QueryTable = [ordered]@{
                        '1' = @{
                            Params = @{
                                UserIds = $UserEmail, $UserId, $UserIdNoDashes
                            }
                            ConsoleOutput = "Running UserIds query for ${UserEmail}, " +
                            "${UserId}, ${UserIdNoDashes}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $UserEmail
                            }
                            ConsoleOutput = "Running Freetext query for ${UserEmail}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $UserId
                            }
                            ConsoleOutput = "Running Freetext query for ${UserId}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $UserIdNoDashes
                            }
                            ConsoleOutput = "Running Freetext query for ${UserIdNoDashes}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 5
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running FreeText '${FreeTextString}' query."
                            }
                            $Key++
                        }
                    }
                }
                'AllUsers' {
                    if ($FreeText) {
                        $QueryTable = [ordered]@{}
                        $Key = 1
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running FreeText '${FreeTextString}' " +
                                "query for all users."
                            }
                            $Key++
                        }
                    }
                    else {
                        $QueryTable = [ordered]@{
                            '1' = @{
                                Params = @{}
                                ConsoleOutput   = "Running query for all users."
                            }
                        }
                    }
                }
                'ServicePrincipal' {
                    $QueryTable = [ordered]@{
                        '1' = @{
                            Params = @{
                                UserIds = @(
                                    $ServicePrincipalId
                                    $ServicePrincipalIdNoDash
                                    $AppId
                                    $AppIdNoDash
                                )
                            }
                            ConsoleOutput = "Running UserIds query for " +
                            "${ServicePrincipalId}, ${ServicePrincipalIdNoDash}, " +
                            "${AppId}, ${AppIdNoDash}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $ServicePrincipalId
                            }
                            ConsoleOutput = "Running Freetext query for ${ServicePrincipalId}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $ServicePrincipalIdNoDash
                            }
                            ConsoleOutput = "Running Freetext query for ${ServicePrincipalIdNoDash}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $AppId
                            }
                            ConsoleOutput = "Running Freetext query for ${AppId}"
                        }
                        '5' = @{
                            Params = @{
                                FreeText = $AppIdNoDash
                            }
                            ConsoleOutput = "Running Freetext query for ${AppIdNoDash}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 6
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                ConsoleOutput = "Running Freetext query for '${FreeTextString}'"
                            }
                            $Key++
                        }
                    }
                }
            }

            # Search-UnifiedAuditLog takes a single -RecordType per call, so when
            # record types are requested, expand the query table to run every
            # query once per record type.
            if (($RecordType | Measure-Object).Count -gt 0) {
                $ExpandedTable = [ordered]@{}
                $Key = 1
                foreach ($Entry in $QueryTable.GetEnumerator()) {
                    foreach ($Type in $RecordType) {
                        $TypedParams = @{}
                        $Entry.Value.Params.GetEnumerator() |
                            ForEach-Object { $TypedParams[$_.Key] = $_.Value }
                        $TypedParams['RecordType'] = $Type
                        $ExpandedTable["$Key"] = @{
                            Params        = $TypedParams
                            ConsoleOutput = "RecordType ${Type}: " +
                            $Entry.Value.ConsoleOutput
                        }
                        $Key++
                    }
                }
                $QueryTable = $ExpandedTable
            }

            #region RUN QUERIES
            $LimitReached = $false
            $ChunkIndex = 0
            foreach ($DateChunk in $DateChunks) {
                if ($LimitReached) { break }
                $ChunkIndex++

                # refresh token each chunk; a long multi-chunk run can outlive the
                # token's 5-minute refresh window and start failing with auth errors
                Update-IRTToken -Service 'Exchange'

                $BaseParams['StartDate'] = $DateChunk.Start
                $BaseParams['EndDate'] = $DateChunk.End

                if ($ChunkCount -gt 1) {
                    $ChunkStartStr = $DateChunk.Start.ToString('yyyy-MM-dd')
                    $ChunkEndStr = $DateChunk.End.ToString('yyyy-MM-dd')
                    Write-IRT "Chunk $ChunkIndex of $ChunkCount ($ChunkStartStr to $ChunkEndStr)."
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Chunk $ChunkIndex of $($ChunkCount): " +
                        "$ChunkStartStr to $ChunkEndStr [$Elapsed]")
                }

                foreach ( $QueryDict in $QueryTable.GetEnumerator() ) {

                    if ($AllLogs.Count -ge $ResultLimit) { $LimitReached = $true; break }

                    # Multi-chunk/multi-query searches can outlive the ~1h access token.
                    # Cheap no-op while the bound token is healthy.
                    $null = Update-IRTToken -Service 'Exchange'

                    # build final params
                    $FirstPageParams = @{}
                    $BaseParams.GetEnumerator() |
                        ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }
                    $QueryDict.Value.Params.GetEnumerator() |
                        ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }

                    $ConsoleOutput = $QueryDict.Value.ConsoleOutput

                    # run query
                    Write-IRT $ConsoleOutput
                    $QueryKey = $QueryDict.Key
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Search-UnifiedAuditLog query $QueryKey [$Elapsed]")
                    $RetryParams = @{
                        SearchParams         = $FirstPageParams
                        Label                = "Query $QueryKey"
                        MaxRetry             = $MaxRetry
                        ThrottleDelaySeconds = $ThrottleDelaySeconds
                    }
                    try {
                        $Page = Invoke-IRTUalSearchWithRetry @RetryParams
                    }
                    catch {
                        # surface the failure loudly and leave a visible breadcrumb
                        # in the data, then move on so other queries still run
                        Write-IRT ("Query $QueryKey failed after retries. Inserting " +
                            "DATA MISSING marker and continuing.") -Level Error
                        Write-Error -ErrorRecord $_
                        $MarkerParams = @{
                            DateChunk   = $DateChunk
                            Label       = "Query $QueryKey"
                            ErrorRecord = $_
                        }
                        $AllLogs.Add( (New-IRTUalGapMarker @MarkerParams) )
                        continue
                    }
                    $LogCount = ($Page | Measure-Object).Count

                    if ($LogCount -gt 0) {

                        Write-IRT "Retrieved ${LogCount} logs."

                        # add to list
                        foreach ($i in $Page) { $AllLogs.Add($i) }

                        # extract sessionid for paging
                        $SessionId = $Page[0].SessionId
                        $PageCount = 2
                        $NextPageParams = $FirstPageParams
                        $NextPageParams['SessionId'] = $SessionId
                    }
                    else {
                        Write-IRT "Retrieved 0 logs." -Level Warn
                    }

                    # retrieve pages until exhausted or ResultLimit reached
                    while ($LogCount -eq 5000 -and $AllLogs.Count -lt $ResultLimit) {

                        # Large searches can outlive the ~1h access token. Cheap no-op
                        # while the bound token is healthy; silent re-bind when not.
                        $null = Update-IRTToken -Service 'Exchange'

                        Write-IRT "Requesting page ${PageCount}."
                        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                        Write-PSFMessage -Level 9 -Message (
                            "${FunctionName}: Search-UnifiedAuditLog page $PageCount " +
                            "(total so far: $($AllLogs.Count)) [$Elapsed]")
                        $RetryParams = @{
                            SearchParams         = $NextPageParams
                            Label                = "Query $QueryKey page $PageCount"
                            MaxRetry             = $MaxRetry
                            ThrottleDelaySeconds = $ThrottleDelaySeconds
                        }
                        try {
                            $Page = Invoke-IRTUalSearchWithRetry @RetryParams
                        }
                        catch {
                            # paging failed partway: surface it, mark the gap, and
                            # stop paging this query while keeping the pages we got
                            Write-IRT ("Query $QueryKey page $PageCount failed after " +
                                "retries. Inserting DATA MISSING marker; partial " +
                                "pages kept.") -Level Error
                            Write-Error -ErrorRecord $_
                            $MarkerParams = @{
                                DateChunk   = $DateChunk
                                Label       = "Query $QueryKey page $PageCount"
                                ErrorRecord = $_
                            }
                            $AllLogs.Add( (New-IRTUalGapMarker @MarkerParams) )
                            break
                        }
                        $LogCount = @($Page).Count

                        if ( $LogCount -gt 0 ) {

                            Write-IRT "Retrieved ${LogCount} logs."

                            # add to list
                            foreach ($i in $Page) { $AllLogs.Add($i) }

                            # extract sessionid for paging
                            $SessionId = $Page[0].SessionId
                        }
                        else {
                            Write-IRT "Retrieved 0 logs." -Level Warn
                        }

                        $PageCount++
                    }

                    if ($AllLogs.Count -ge $ResultLimit) { $LimitReached = $true; break }
                }

                if ($ChunkCount -gt 1) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Chunk $ChunkIndex complete. " +
                        "Total logs accumulated: $($AllLogs.Count) [$Elapsed]")
                }

                # brief pause between chunks to avoid tripping throttle limits
                if ($ChunkDelaySeconds -gt 0 -and $ChunkIndex -lt $ChunkCount -and
                    -not $LimitReached) {
                    Start-Sleep -Seconds $ChunkDelaySeconds
                }
            }

            # note when queries stopped early due to ResultLimit
            if ($LimitReached) {
                Write-IRT ("Reached ResultLimit of ${ResultLimit} records. " +
                    "Keeping the most recent $($AllLogs.Count) events.") -Level Warn
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: ResultLimit $ResultLimit reached at chunk " +
                    "$ChunkIndex of $ChunkCount [$Elapsed]")
            }

            # exit if no logs returned
            if (($AllLogs | Measure-Object).Count -eq 0) {
                Write-IRT "0 total logs retrieved." -Level Warn
                return
            }

            #region UNIQUE, SORT
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message "${FunctionName}: Dedupliacation, sorting [$Elapsed]"
            # remove duplicates
            $UniqueLogIds = [System.Collections.Generic.HashSet[string]]::new()
            $Logs = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Log in $AllLogs) {
                if ($UniqueLogIds.Add([string]$Log.Identity)) {
                    $null = $Logs.Add($Log)
                }
            }
            # build comparison script
            $PropertyName = 'CreationDate'
            $Descending = $true
            $Comparison = [System.Comparison[PSObject]] {
                param($X, $Y)
                $Result = $X.$PropertyName.CompareTo($Y.$PropertyName)
                if ( $Descending ) {
                    return -1 * $Result
                }
                return $Result
            }
            $Logs.Sort($Comparison)

            #region OUTPUT

            # count actual logs before adding metadata
            $TotalLogCount = ($Logs | Measure-Object).Count
            if ($TotalLogCount -gt 0) {
                Write-IRT "Total retrieved ${TotalLogCount} logs."
            }
            else {
                Write-IRT "Total retrieved 0 logs." -Level Warn
                return
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata = $true
                    FileNamePrefix = $FileNamePrefix
                    FileName = $FileNameBase
                    SheetTitle = $ActiveProfile.SheetTitle
                    Title = "$($ActiveProfile.SheetTitle)${TitleSuffix}"
                    TitleSuffix = $TitleSuffix
                    ProfileTag = $ActiveProfile.ProfileTag
                }
            )

            # export to xml
            if ($Xml) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-PSFMessage -Level 8 -Message "${FunctionName}: Starting XML export [$Elapsed]"
                Write-IRT "Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }

            # export excel spreadsheet
            if ($Excel) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Starting Excel export [$Elapsed]")
                $Params = @{
                    Log = $Logs
                    WaitOnMessageTrace = $WaitOnMessageTrace
                    Cached = $Cached
                }
                & $ActiveProfile.ShowFunction @Params
            }
        }
    }
}
