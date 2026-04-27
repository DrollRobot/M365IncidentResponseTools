function Show-UALogs {
    <#
	.SYNOPSIS
	Parse and show unified audit logs.
	
	.NOTES
	Version: 1.0.1
    1.0.1 - Added option pass raw log objects, not just import from file.
	#>
    [CmdletBinding(DefaultParameterSetName='Objects')]
    param (
	    [Parameter(Position=0, Mandatory, ParameterSetName='Objects')]
        [System.Collections.Generic.List[PSObject]] $Logs,

        [Parameter(Position=0, Mandatory, ParameterSetName='Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = $true,
        [boolean] $Open = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [switch] $Test,
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
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        $Red = @{ ForegroundColor = 'Red' }
        $Yellow = @{ ForegroundColor = 'Yellow' }
        
        # import from xml
        if ($ParameterSet -eq 'Xml') {
            if ($Script:Test) {
                $TestText = "Importing from Xml"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                [System.Collections.Generic.List[PSObject]]$Logs = Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                Write-Host @Red "${Function}: Error importing from ${XmlPath}."
                return
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }    
        }

        # $Groups = Request-GraphGroups
        # $Roles = Request-DirectoryRoles
        # $RoleTemplates = Request-DirectoryRoleTemplates
        # $ServicePrincipals = Request-GraphServicePrincipals
        # $Users = Request-GraphUsers

        #region METADATA
        if ($Logs[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Logs[0]
            $Logs.RemoveAt(0)

            # $UserEmail = $Metadata.UserEmail
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            # $Domain = $Metadata.Domain
            $FileNamePrefix = $Metadata.FileNamePrefix
            $SheetTitle = $Metadata.SheetTitle
            $ProfileTag = $Metadata.ProfileTag
        }
        else {
            Write-Host @Red "${Function}: No Metadata found."
        }

        # sheet registry — maps operation types to their dedicated sheet builders
        $SheetRegistry = [ordered]@{
            'AllOperations' = @{
                Operations    = @()   # empty = matches all logs
                BuildFunction = 'Build-AllOperationsSheet'
                SheetName     = $FileNamePrefix
                SheetTitle    = $SheetTitle
            }
            'SignInLogs' = @{
                Operations    = @('UserLoggedIn', 'UserLoginFailed', 'UserLoggedOff')
                BuildFunction = 'Build-UserLoginOperationsSheet'
                SheetName     = 'SignInLogs'
                SheetTitle    = 'UAL sign-in logs'
            }
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $TitleDateFormat = "M/d/yy h:mmtt"
        $TitleEndDate = $EndDate.ToLocalTime().ToString($TitleDateFormat)
        $TitleStartDate = $StartDate.ToLocalTime().ToString($TitleDateFormat)
        $WorksheetTitle = "${SheetTitle} for ${UserName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

        # import alloperations sheet
        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $AllOperationsFileName = 'unified_audit_log-all_operations.xlsx'
        $AllOperationsConfig = $Global:IRT_Config.AllOperationsSheetPath
        $OperationsSheetPath = if ($AllOperationsConfig) { $AllOperationsConfig } else { Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}" }
        $OperationsSheetData = Import-Excel -Path $OperationsSheetPath -WorksheetName 'Operations'

        # ipinfo
        if ($IpInfo) {
            $IpInfoAddresses = [System.Collections.Generic.HashSet[string]]::new()

            # check for presence of ip_info package
            $IpInfoPackage = Test-PythonPackage -Name 'ip_info'
        }

        # resolve ip info table
        if ($Global:IRT_IpInfo -isnot [hashtable]) {
            $Global:IRT_IpInfo = [hashtable]::Synchronized(@{})
        }
        $IpInfoTable = $Global:IRT_IpInfo
    }

    process {

        #region FIRST LOOP

        foreach ($Log in $Logs) {
            # convert audit data to powershell objects
            $Log.AuditData = $Log.AuditData | ConvertFrom-Json -Depth 10

            # collect ip addresses
            if ($IpInfo) {
                if ( $Log.AuditData.ClientIP ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIP
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpInfoAddresses.Add($IpObject.ToString())
                    }
                }
                if ( $Log.AuditData.ActorIpAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ActorIpAddress
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpInfoAddresses.Add($IpObject.ToString())
                    }                }
                if ( $Log.AuditData.ClientIPAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIPAddress
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpInfoAddresses.Add($IpObject.ToString())
                    }
                } 
            }
        }

        #region QUERY IPS
        if ($IpInfo -and 
            $IpInfoPackage.Present -and
            ($IpInfoAddresses | Measure-Object).Count -gt 0
        ) {

            # query information for all IP addresses
            if ($Script:Test) {
                $TestText = "Querying ip info"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            $env:PYTHONUTF8 = '1'
            & ip_info --apis bulk --output_format none --ip_addresses $IpInfoAddresses
            if ($LASTEXITCODE -ne 0) {
                Write-Host @Red "${Function}: ip_info query failed." | Out-Host
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }

            # add ip info to global colection
            if ($Script:Test) {
                $TestText = "Creating ip info collection in global scope"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            foreach ($Ip in $IpInfoAddresses) {
                # if ip doesn't exist in table, add it.
                if (-not $IpInfoTable.ContainsKey($Ip)) {
                    $Params = @(
                        '--apis','none',
                        '--output_format','table',
                        '--ip_addresses', $Ip.ToString()
                    )
                    $NewLine = [Environment]::NewLine
                    $Output = ((& ip_info @Params) -join $NewLine).Trim()
                    $IpInfoTable[$Ip] = $Output
                }
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }
        }

        #region WAIT ON MESSAGE TRACE
        # resolve message trace table once before the row loop
        $MessageTraceTable = $null
        if ($WaitOnMessageTrace) {
            $MaxWaitMinutes = 10
            $WaitInterval = 15
            $WaitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # wait for both user and AllUsers message traces to complete via WaitFlags
            if ($Global:IRT_WaitFlags) {
                while (-not ($Global:IRT_WaitFlags.MessageTraceUserDone -and $Global:IRT_WaitFlags.MessageTraceAllUsersDone)) {
                    if ($WaitStopwatch.Elapsed.TotalMinutes -ge $MaxWaitMinutes) {
                        Write-Host @Red "${Function}: Timed out after ${MaxWaitMinutes} minutes waiting on message trace. Continuing without subjects."
                        if ($Script:Test) {
                            Write-Host @Yellow "${Function}: WaitFlags.MessageTraceUserDone = $($Global:IRT_WaitFlags.MessageTraceUserDone), WaitFlags.MessageTraceAllUsersDone = $($Global:IRT_WaitFlags.MessageTraceAllUsersDone)"
                        }
                        break
                    }
                    if ($Script:Test) {
                        $Elapsed = $WaitStopwatch.Elapsed.ToString('mm\:ss')
                        Write-Host @Yellow "${Function}: Waiting on message trace (${Elapsed} elapsed). UserDone=$($Global:IRT_WaitFlags.MessageTraceUserDone), AllUsersDone=$($Global:IRT_WaitFlags.MessageTraceAllUsersDone)"
                    }
                    else {
                        Write-Host @Yellow "${Function}: Waiting on message trace..."
                    }
                    Start-Sleep -Seconds $WaitInterval
                }
            }
        }

        # load message trace table from global
        if ($Global:IRT_MessageTraceTable -is [hashtable] -and $Global:IRT_MessageTraceTable.Count -gt 0) {
            $MessageTraceTable = $Global:IRT_MessageTraceTable
            if ($Script:Test) {
                Write-Host @Yellow "${Function}: Using `$Global:IRT_MessageTraceTable ($($MessageTraceTable.Count) entries)"
            }
        }

        if ($Script:Test) {
            if ($MessageTraceTable) {
                Write-Host @Yellow "${Function}: MessageTraceTable resolved with $($MessageTraceTable.Count) entries"
            }
            else {
                Write-Host @Yellow "${Function}: No MessageTraceTable available — subjects will not be resolved"
            }
        }

        #region AUTO-DETECT SHEETS
        # build set of operations present in the logs
        $LogOperations = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Log in $Logs) {
            if ($Log.AuditData.Operation) {
                [void]$LogOperations.Add($Log.AuditData.Operation)
            }
        }

        $MatchedSheets = [System.Collections.Generic.List[hashtable]]::new()

        if ($ProfileTag -and $SheetRegistry.Contains($ProfileTag)) {
            # profile-driven: only the tagged sheet
            $MatchedSheets.Add($SheetRegistry[$ProfileTag])
        }
        else {
            # default: always include AllOperations, then add any specialized
            # sheets whose operations are present in the logs
            $MatchedSheets.Add($SheetRegistry['AllOperations'])
            foreach ($Key in $SheetRegistry.Keys) {
                if ($Key -eq 'AllOperations') { continue }
                $SheetEntry = $SheetRegistry[$Key]
                foreach ($Op in $SheetEntry.Operations) {
                    if ($LogOperations.Contains($Op)) {
                        $MatchedSheets.Add($SheetEntry)
                        break
                    }
                }
            }
        }

        #region BUILD WORKBOOK
        $Workbook = Open-ExcelPackage -Path $ExcelOutputPath -Create

        foreach ($SheetEntry in $MatchedSheets) {
            # filter logs — empty Operations array means all logs
            if ($SheetEntry.Operations.Count -gt 0) {
                $FilteredLogs = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($Log in $Logs) {
                    if ($Log.AuditData.Operation -in $SheetEntry.Operations) {
                        $FilteredLogs.Add($Log)
                    }
                }
            }
            else {
                $FilteredLogs = $Logs
            }

            if (($FilteredLogs | Measure-Object).Count -gt 0) {
                $BuildTitle = "$($SheetEntry.SheetTitle) for ${UserName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."
                $SheetParams = @{
                    Logs          = $FilteredLogs
                    ExcelPackage  = $Workbook
                    IpInfoTable   = $IpInfoTable
                    WorksheetName = $SheetEntry.SheetName
                    Title         = $BuildTitle
                    TableStyle    = $TableStyle
                    Font          = $Font
                    Cached        = $Cached
                }
                # AllOperations needs extra parameters
                if ($SheetEntry.BuildFunction -eq 'Build-AllOperationsSheet') {
                    if ($MessageTraceTable) { $SheetParams['MessageTraceTable'] = $MessageTraceTable }
                    if ($OperationsSheetData)  { $SheetParams['OperationsSheetData'] = $OperationsSheetData }
                }
                $Workbook = & $SheetEntry.BuildFunction @SheetParams
            }
        }

        #region OUTPUT
        Write-Host @Blue "${Function}: Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-Host @Blue "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}