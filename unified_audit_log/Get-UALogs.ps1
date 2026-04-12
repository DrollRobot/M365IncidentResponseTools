New-Alias -Name 'UALog' -Value 'Get-UALogs' -Force
New-Alias -Name 'UALogs' -Value 'Get-UALogs' -Force
New-Alias -Name 'GetUALog' -Value 'Get-UALogs' -Force
New-Alias -Name 'GetUALogs' -Value 'Get-UALogs' -Force
New-Alias -Name 'Get-UALog' -Value 'Get-UALogs' -Force
function Get-UALogs {
    <#
	.SYNOPSIS
    Runs multiple queries to pull all unified audit logs records related to a specific user.
    
	.NOTES
	Version: 1.5.1
    1.5.1 - Added function name to all output.
    1.5.0 - Added -AllUsers option, added test timers.
    1.4.0 - Updating to add metadata object, use shorter file names.
    1.3.0 - Updated to output objects.
	#>
    [CmdletBinding(DefaultParameterSetName = 'UserObjects')]
    param (
        [Parameter(Position = 0,ParameterSetName='UserObjects')]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [Parameter(ParameterSetName='AllUsers')]
        [switch] $AllUsers,

        [Parameter(Position = 0,ParameterSetName='ServicePrincipals')]
        [Alias( 'ServicePrincipal' )]
        [psobject[]] $ServicePrincipals,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        [string[]] $Operations,
        [switch] $RiskyOperations,
        [switch] $SignInLogs,
        [string[]] $FreeText,

        [boolean] $Excel = $true,
        [switch] $Test,
        [boolean] $WaitOnMessageTrace = $false,
        [boolean] $Xml = $true
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
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        # $Yellow = @{ ForegroundColor = 'Yellow' }

        # query profiles — add new entries here to support additional modes
        $ProfileTable = [ordered]@{
            Default = [pscustomobject]@{
                FilePrefix   = 'UnifiedAuditLogs'
                SheetTitle   = 'Unified audit logs'
                DefaultDays  = 1
                Operations   = [string[]]@()
                ShowFunction = 'Show-UALogs'
            }
            RiskyOperations = [pscustomobject]@{
                FilePrefix   = 'UALRiskyOperations'
                SheetTitle   = 'UAL risky operations'
                DefaultDays  = 180
                Operations   = [string[]]@()
                ShowFunction = 'Show-UALogs'
            }
            SignInLogs = [pscustomobject]@{
                FilePrefix   = 'UALSignInLogs'
                SheetTitle   = 'UAL sign-in logs'
                DefaultDays  = 180
                Operations   = [string[]]@('UserLoggedIn')
                ShowFunction = 'Show-UALogs'
            }
        }
        $ActiveProfile = switch ($true) {
            $RiskyOperations { $ProfileTable['RiskyOperations']; break }
            $SignInLogs      { $ProfileTable['SignInLogs'];      break }
            default          { $ProfileTable['Default'] }
        }

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObjects' {
                # if users passed via script argument:
                if (($UserObjects | Measure-Object).Count -gt 0) {
                    $LoopObjects = $UserObjects
                }
                # if not, look for global objects
                else {
                    
                    # get from global variables
                    $LoopObjects = Get-IRTUserObjects
                    
                    # if none found, exit
                    if ( -not $LoopObjects -or $LoopObjects.Count -eq 0 ) {
                        Write-Host @Red "${Function}: No user objects passed or found in global variables."
                        return
                    }
                    if (($LoopObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = "No -UserObjects argument used, no `$Global:IRT_UserObjects present."
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
            'ServicePrincipals' {
                $LoopObjects = $ServicePrincipals  
            }
        }

        # verify connected to exchange
        try {
            [void](Get-AcceptedDomain)
        }
        catch {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        } 

        # get client domain name for file output
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1

        #region DATE RANGE

        # validate only relative or absolute
        if ($Days -and ($Start -or $End)) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "Choose either relative range with -Days or absolute range with -Start and -End."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams  
        }

        # validate both start and end used
        if (($Start -and -not $End) -or
            ($End -and -not $Start)
        ) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "Specify both -Start and -End"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams  
        }

        # attempt to parse user input dates into datetime objects
        if ($Start -and $End) {
            # $DateRangeType = 'Absolute'
            # start - convert user string into object
            try {
                $StartDate = Get-Date -Date $Start -ErrorAction 'Stop'
                $StartDateUtc = [DateTime]::SpecifyKind($StartDate, [DateTimeKind]::Local).ToUniversalTime()
            }
            catch {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "-Start invalid. Use format 'MM/dd/yy hh:mm(tt)"
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
            # end - convert user string into object
            try {
                $EndDate = Get-Date -Date $End -ErrorAction 'Stop'
                $EndDateUtc = [DateTime]::SpecifyKind($EndDate, [DateTimeKind]::Local).ToUniversalTime()
            }
            catch {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "-End invalid. Use format 'MM/dd/yy hh:mm(tt)"
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
            # make sure earliest date is the start date
            if ($StartDateUtc -gt $EndDateUtc) {
                $Temp = $StartDateUtc
                $StartDateUtc = $EndDateUtc
                $EndDateUtc = $Temp
            }
            # set days to match range
            $Days = [Int]([Math]::Ceiling( ($EndDate - $StartDate).TotalDays ))
        }
        # create objects based on days
        else {
            # $DateRangeType = 'Relative'
            # set default value for days ### must be done after checking for relative/absolute arguments
            if (-not $Days) {
                $Days = $ActiveProfile.DefaultDays
            }

            $StartDateUtc = (Get-Date).AddDays($Days * -1).ToUniversalTime() 
            $EndDateUtc = (Get-Date).ToUniversalTime()
        }

        # set file name date to query end date
        $FileNameDateFormat = 'yy-MM-dd_HH-mm'
        $FileNameDateString = $EndDateUtc.ToLocalTime().ToString($FileNameDateFormat)

        #region OPERATIONS

        $OperationsSet = [System.Collections.Generic.Hashset[string]]::new()
        # add user specified operations
        foreach ($o in $Operations) {[void]$OperationsSet.Add($o)}
        # populate profile operations
        if ($RiskyOperations) {
            # import alloperations csv
            $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
            $AllOperationsFileName = 'unified_audit_log-all_operations.csv' # FIXME convert to using xlsx
            $OperationsCsvPath = Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}"
            $OperationsCsvData = Import-Csv -Path $OperationsCsvPath

            # get high risk operations and store in active profile
            $ActiveProfile.Operations = ($OperationsCsvData | Where-Object {$_.Risk -eq 'High'}).Operation

            # FIXME get these properly tagged in spreadsheet.
            # app consent
            # [void]$OperationsSet.Add("Add delegated permission grant.") #FIXME
            # mfa changes
            # [void]$OperationsSet.Add("User registered security info") #FIXME
            # [void]$OperationsSet.Add("User registered all required security info") #FIXME
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
                'UserObjects' {
                    $UserId = $LoopObject.Id
                    $UserIdNoDashes = $UserId -replace '-', ''
                    $UserEmail = $LoopObject.UserPrincipalName
                    $ObjectName = $UserEmail -split '@' | Select-Object -First 1
                }
                'AllUsers' {
                    $ObjectName = 'AllUsers'
                    # don't add a user filter
                }
                'ServicePrincipals' {
                    $ServicePrincipalId = $LoopObject.Id
                    $ServicePrincipalIdNoDash = $LoopObject.Id -replace '-',''
                    $AppId = $LoopObject.AppId
                    $AppIdNoDash = $LoopObject.AppId -replace '-',''

                    $ObjectName = $LoopObject.DisplayName -replace '[^a-zA-Z0-9]',''
                }
            }
            $FileNamePrefix = $ActiveProfile.FilePrefix
            $XmlOutputPath = "${FileNamePrefix}_${Days}Days_${ObjectName}_${FileNameDateString}.xml"

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
                'UserObjects' {
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
                'ServicePrincipals' {
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

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata = $true
                    UserObject = $LoopObject
                    UserEmail = $UserEmail
                    UserName = $ObjectName
                    StartDate = $StartDateUtc.ToLocalTime()
                    EndDate = $EndDateUtc.ToLocalTime()
                    Days = $Days
                    DomainName = $DomainName
                    FileNamePrefix = $FileNamePrefix
                    SheetTitle = $ActiveProfile.SheetTitle
                }
            )

            #region OUTPUT

            # show count, export
            $LogCount = ($Logs | Measure-Object).Count
            if ($LogCount -gt 0) {
                Write-Host @Blue "${Function}: Retrieved ${LogCount} logs."

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
                        Logs = $Logs
                        WaitOnMessageTrace = $WaitOnMessageTrace
                    }
                    & $ActiveProfile.ShowFunction @Params
                }
            }
            else {
                Write-Host @Red "${Function}: Retrieved 0 logs."
            }
        }
    }
}