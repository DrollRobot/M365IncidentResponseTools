function Get-UALog {
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

    .PARAMETER Operation
    Filter results to specific UAL operation names.

    .PARAMETER RiskyOperation
    Filter to a predefined list of high-risk operations.

    .PARAMETER SignInLog
    Filter to only UAL sign-in operations.

    .PARAMETER FreeText
    One or more free-text search strings passed to Search-UnifiedAuditLog.

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
    Get-UALog
    Queries the UAL for the last 30 days for the user in the global session.

    .EXAMPLE
    Get-UALog -UserObject $User -Days 90
    Queries 90 days of UAL activity for a specific user.

    .EXAMPLE
    Get-UALog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'
    Finds all FileDeleted events for any user during April 2026.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.6.0
    1.6.0 - Added profile tags to allow generating specific sheets in Show-UALog.
    1.5.1 - Added function name to all output.
    1.5.0 - Added -AllUsers option, added test timers.
    1.4.0 - Updating to add metadata object, use shorter file names.
    1.3.0 - Updated to output objects.
    #>
    [Alias('GetUALog', 'GetUALogs', 'UALog', 'UALogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0,ParameterSetName='UserObject')]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName='AllUsers')]
        [switch] $AllUsers,

        [Parameter(Position = 0,ParameterSetName='ServicePrincipal')]
        [Alias( 'ServicePrincipals' )]
        [psobject[]] $ServicePrincipal,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        [Alias('Operations')]
        [string[]] $Operation,
        [Alias('RiskyOperations')]
        [switch] $RiskyOperation,
        [Alias('SignInLogs')]
        [switch] $SignInLog,
        [string[]] $FreeText,

        [boolean] $Excel = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # query profiles - add new entries here to support additional modes
        $ProfileTable = [ordered]@{
            Default = [pscustomobject]@{
                FilePrefix   = 'UnifiedAuditLogs'
                SheetTitle   = 'Unified audit logs'
                DefaultDays  = 1
                Operations   = [string[]]@()
                ShowFunction = 'Show-UALog'
                ProfileTag   = $null
            }
            RiskyOperations = [pscustomobject]@{
                FilePrefix   = 'UALRiskyOperations'
                SheetTitle   = 'UAL risky operations'
                DefaultDays  = 180
                Operations   = [string[]]@()
                ShowFunction = 'Show-UALog'
                ProfileTag   = $null
            }
            SignInLogs = [pscustomobject]@{
                FilePrefix   = 'UALSignInLogs'
                SheetTitle   = 'UAL sign-in logs'
                DefaultDays  = 180
                Operations   = [string[]]@('UserLoggedIn','UserLoggedOff','UserLoginFailed')
                ShowFunction = 'Show-UALog'
                ProfileTag   = 'SignInLogs'
            }
        }
        $ActiveProfile = switch ($true) {
            $RiskyOperation { $ProfileTable['RiskyOperations']; break }
            $SignInLog      { $ProfileTable['SignInLogs'];      break }
            default          { $ProfileTable['Default'] }
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
                    $LoopObjects = Get-IRTUserObject

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
        Write-Verbose "${FunctionName}: Get-AcceptedDomain $Elapsed"
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1

        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $ActiveProfile.DefaultDays
        }
        $DateRange = Resolve-IRTDateRange @DateRangeParams
        $Days         = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc   = $DateRange.EndUtc

        # set file name date to query end date
        $FileNameDateString = $EndDateUtc.ToLocalTime().ToString('yy-MM-dd_HH-mm')

        $OperationsSet = [System.Collections.Generic.Hashset[string]]::new()
        # add user specified operations
        foreach ($o in $Operation) {[void]$OperationsSet.Add($o)}
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
        foreach ($o in $ActiveProfile.Operations) {[void]$OperationsSet.Add($o)}
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
                    $ServicePrincipalIdNoDash = $LoopObject.Id -replace '-',''
                    $AppId = $LoopObject.AppId
                    $AppIdNoDash = $LoopObject.AppId -replace '-',''
                    $ObjectName = $LoopObject.DisplayName -replace '[^a-zA-Z0-9]',''
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
                StartDate      = $StartDateUtc
                EndDate        = $EndDateUtc
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


            #region RUN QUERIES
            foreach ( $QueryDict in $QueryTable.GetEnumerator() ) {

                # build final params
                $FirstPageParams = @{}
                # add params from table
                $BaseParams.GetEnumerator() | ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }
                $QueryDict.Value.Params.GetEnumerator() |
                    ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }

                $ConsoleOutput = $QueryDict.Value.ConsoleOutput

                # run query
                Write-IRT $ConsoleOutput
                $QueryKey = $QueryDict.Key
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Search-UnifiedAuditLog query $QueryKey $Elapsed"
                $Page = Search-UnifiedAuditLog @FirstPageParams
                $LogCount = ($Page | Measure-Object).Count

                if ($LogCount -gt 0) {

                    Write-IRT "Retrieved ${LogCount} logs."

                    # add to list
                    foreach ($i in $Page) {$AllLogs.Add($i)}

                    # extract sessionid for paging
                    $SessionId = $Page[0].SessionId
                    $PageCount = 2
                    $NextPageParams = $FirstPageParams
                    $NextPageParams['SessionId'] = $SessionId
                }
                else {
                    Write-IRT "Retrieved 0 logs." -Level Warn
                }

                # retrieve pages
                while ($LogCount -eq 5000) {

                    Write-IRT "Requesting page ${PageCount}."
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-Verbose "${FunctionName}: Search-UnifiedAuditLog page $PageCount $Elapsed"
                    $Page = Search-UnifiedAuditLog @NextPageParams
                    $LogCount = @($Page).Count

                    if ( $LogCount -gt 0 ) {

                        Write-IRT "Retrieved ${LogCount} logs."

                        # add to list
                        foreach ($i in $Page) {$AllLogs.Add($i)}

                        # extract sessionid for paging
                        $SessionId = $Page[0].SessionId
                    }
                    else {
                        Write-IRT "Retrieved 0 logs." -Level Warn
                    }

                    $PageCount++
                }
            }

            # exit if no logs returned
            if (($AllLogs | Measure-Object).Count -eq 0) {
                Write-IRT "0 total logs retrieved." -Level Warn
                return
            }

            #region UNIQUE, SORT
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Dedupliacation, sorting $Elapsed"
            # remove duplicates
            $UniqueLogIds = [System.Collections.Generic.HashSet[string]]::new()
            $Logs = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Log in $AllLogs) {
                if ($UniqueLogIds.Add([string]$Log.Identity)) {
                    $Logs.Add($Log) | Out-Null
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
                Write-Verbose "${FunctionName}: Starting XML export $Elapsed"
                Write-IRT "Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }

            # export excel spreadsheet
            if ($Excel) {
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Starting Excel export $Elapsed"
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
