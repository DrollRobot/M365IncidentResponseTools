New-Alias -Name 'UALog' -Value 'Get-UALog' 
New-Alias -Name 'UALogs' -Value 'Get-UALog' 
New-Alias -Name 'GetUALog' -Value 'Get-UALog' 
New-Alias -Name 'GetUALogs' -Value 'Get-UALog' 
function Get-UALog {
    <#
	.SYNOPSIS
    Runs multiple queries to pull all unified audit logs records related to a specific user.

	.NOTES
	Version: 1.6.0
    1.6.0 - Added profile tags to allow generating specific sheets in Show-UALog
    1.5.1 - Added function name to all output.
    1.5.0 - Added -AllUsers option, added test timers.
    1.4.0 - Updating to add metadata object, use shorter file names.
    1.3.0 - Updated to output objects.
	#>
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
        [switch] $Test,
        [boolean] $WaitOnMessageTrace = $false,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        $ParameterSet = $PSCmdlet.ParameterSetName
        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        $Red = @{ ForegroundColor = 'Red' }

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
                        Write-Host @Red "${Function}: No user objects passed or found in global variables."
                        return
                    }
                    if (($LoopObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = "No -UserObject argument used, no `$Global:IRT_UserObjects present."
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'AllUsers' {
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
            $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
            $AllOperationsFileName = 'unified_audit_log-all_operations.xlsx'
            $AllOperationsConfig = $Global:IRT_Config.AllOperationsSheetPath
            $OperationsSheetPath = if ($AllOperationsConfig) { $AllOperationsConfig } else { Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}" }
            $OperationsSheetData = Import-Excel -Path $OperationsSheetPath -WorksheetName 'Operations'

            # get high risk operations and store in active profile
            $ActiveProfile.Operations = ($OperationsSheetData | Where-Object {$_.Risk -eq 'High'}).Operation
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
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}_${ObjectName}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleSuffix = " for ${ObjectName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

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
                            Text   = "${Function}: Running -UserIds query for ${UserEmail}, ${UserId}, ${UserIdNoDashes}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $UserEmail
                            }
                            Text   = "${Function}: Running -Freetext query for ${UserEmail}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $UserId
                            }
                            Text   = "${Function}: Running -Freetext query for ${UserId}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $UserIdNoDashes
                            }
                            Text   = "${Function}: Running -Freetext query for ${UserIdNoDashes}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 5
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                Text = "${Function}: Running -FreeText '${FreeTextString}' query."
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
                                Text = "${Function}: Running FreeText '${FreeTextString}' query for all users."
                            }
                            $Key++
                        }
                    }
                    else {
                        $QueryTable = [ordered]@{
                            '1' = @{
                                Params = @{}
                                Text   = "${Function}: Running query for all users."
                            }
                        }
                    }
                }
                'ServicePrincipal' {
                    $QueryTable = [ordered]@{
                        '1' = @{
                            Params = @{
                                UserIds = $ServicePrincipalId, $ServicePrincipalIdNoDash, $AppId, $AppIdNoDash
                            }
                            Text   = "${Function}: Running -UserIds query for ${ServicePrincipalId}, ${ServicePrincipalIdNoDash}, ${AppId}, ${AppIdNoDash}"
                        }
                        '2' = @{
                            Params = @{
                                FreeText = $ServicePrincipalId
                            }
                            Text   = "${Function}: Running -Freetext query for ${ServicePrincipalId}"
                        }
                        '3' = @{
                            Params = @{
                                FreeText = $ServicePrincipalIdNoDash
                            }
                            Text   = "${Function}: Running -Freetext query for ${ServicePrincipalIdNoDash}"
                        }
                        '4' = @{
                            Params = @{
                                FreeText = $AppId
                            }
                            Text   = "${Function}: Running -Freetext query for ${AppId}"
                        }
                        '5' = @{
                            Params = @{
                                FreeText = $AppIdNoDash
                            }
                            Text   = "${Function}: Running -Freetext query for ${AppIdNoDash}"
                        }
                    }
                    if ($FreeText) {
                        $Key = 6
                        foreach ($FreeTextString in $FreeText) {
                            $QueryTable["$Key"] = @{
                                Params = @{
                                    FreeText = $FreeTextString
                                }
                                Text = "${Function}: Running -FreeText '${FreeTextString}' query."
                            }
                            $Key++
                        }
                    }
                }
            }


            #region RUN QUERIES
            if ($Script:Test) {
                $TestText = "Running queries"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            foreach ( $QueryDict in $QueryTable.GetEnumerator() ) {

                # build final params
                $FirstPageParams = @{}
                # add params from table
                $BaseParams.GetEnumerator() | ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }
                $QueryDict.Value.Params.GetEnumerator() | ForEach-Object { $FirstPageParams[$_.Key] = $_.Value }

                $Text = $QueryDict.Value.Text

                # run query
                Write-Host @Blue $Text
                $Page = Search-UnifiedAuditLog @FirstPageParams
                $LogCount = ($Page | Measure-Object).Count

                if ($LogCount -gt 0) {

                    Write-Host @Blue "${Function}: Retrieved ${LogCount} logs."

                    # add to list
                    foreach ($i in $Page) {$AllLogs.Add($i)}

                    # extract sessionid for paging
                    $SessionId = $Page[0].SessionId
                    $PageCount = 2
                    $NextPageParams = $FirstPageParams
                    $NextPageParams['SessionId'] = $SessionId
                }
                else {
                    Write-Host @Red "${Function}: Retrieved 0 logs."
                }

                # retrieve pages
                while ($LogCount -eq 5000) {

                    Write-Host @Blue "Requesting page ${PageCount}."
                    $Page = Search-UnifiedAuditLog @NextPageParams
                    $LogCount = @($Page).Count

                    if ( $LogCount -gt 0 ) {

                        Write-Host @Blue "${Function}: Retrieved ${LogCount} logs."

                        # add to list
                        foreach ($i in $Page) {$AllLogs.Add($i)}

                        # extract sessionid for paging
                        $SessionId = $Page[0].SessionId
                    }
                    else {
                        Write-Host @Red "${Function}: Retrieved 0 logs."
                    }

                    $PageCount++
                }
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }

            # exit if no logs returned
            if (($AllLogs | Measure-Object).Count -eq 0) {
                Write-Host @Red "${Function}: 0 total logs retrieved. Exiting."
                return
            }

            #region UNIQUE, SORT
            if ($Script:Test) {
                $TestText = "Removing duplicates and sorting"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

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

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }

            #region OUTPUT

            # count actual logs before adding metadata
            if (($Logs | Measure-Object).Count -gt 0) {
                Write-Host @Blue "${Function}: Retrieved ${LogCount} logs."
            }
            else {
                Write-Host @Red "${Function}: Retrieved 0 logs."
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
                if ($Script:Test) {
                    $TestText = "Exporting to xml"
                    $TimerStart = $Stopwatch.Elapsed
                    Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
                }

                Write-Host @Blue "`n${Function}: Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath

                if ($Script:Test) {
                    $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                    Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
                }
            }

            # export excel spreadsheet
            if ($Excel) {
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