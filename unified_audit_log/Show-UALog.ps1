function Show-UALog {
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
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Position=0, Mandatory, ParameterSetName='Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = $true,
        [boolean] $Open = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [int] $MaxWaitMinutes = 15,
        [switch] $Test,
        [switch] $Cached
    )

    begin {
        $ParameterSet = $PSCmdlet.ParameterSetName
        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            if ($Script:Test) {
                $TestText = "Importing from Xml"
                $TimerStart = $Stopwatch.Elapsed
            }

            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                [System.Collections.Generic.List[PSObject]]$Log = Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                Write-IRT "Error importing from ${XmlPath}." -Level Error
                return
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
            }
        }

        #region METADATA
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # sheet registry - maps operation types to their dedicated sheet builders
        $SheetRegistry = [ordered]@{
            'AllOperations' = @{
                Operations    = @()   # empty = matches all logs
                BuildFunction = 'Build-AllOperationSheet'
                SheetName     = $Metadata.FileNamePrefix
                SheetTitle    = $Metadata.SheetTitle
            }
            'SignInLogs' = @{
                Operations    = @('UserLoggedIn', 'UserLoginFailed', 'UserLoggedOff')
                BuildFunction = 'Build-UserLoginOperationsSheet'
                SheetName     = 'SignInLogs'
                SheetTitle    = 'UAL sign-in logs'
            }
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + ".xlsx"

        # import alloperations sheet
        $OperationsSheetData = $Global:IRT_UalOperationsData

        # ipinfo
        if ($IpInfo) {
            $IpInfoAddresses = [System.Collections.Generic.HashSet[string]]::new()

            # check for presence of ip_info package
            $IpInfoPackage = Test-PythonPackage -Name 'ip_info'
        }

        # resolve ip info table
        $IpInfoTable = $Global:IRT_IpInfo
    }

    process {

        #region FIRST LOOP

        foreach ($LogEntry in $Log) {
            # convert audit data to powershell objects
            $LogEntry.AuditData = $LogEntry.AuditData | ConvertFrom-Json -Depth 10

            # collect ip addresses
            if ($IpInfo) {
                if ( $LogEntry.AuditData.ClientIP ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIP
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpInfoAddresses.Add($IpObject.ToString())
                    }
                }
                if ( $LogEntry.AuditData.ActorIpAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ActorIpAddress
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpInfoAddresses.Add($IpObject.ToString())
                    }                }
                if ( $LogEntry.AuditData.ClientIPAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIPAddress
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

            if ($Script:Test) {
                $TestText = "Querying ip info"
                $TimerStart = $Stopwatch.Elapsed
            }

            $UnseenIps = @($IpInfoAddresses | Where-Object { -not $IpInfoTable.ContainsKey($_) })
            if ($UnseenIps.Count -gt 0) {
                $env:PYTHONUTF8 = '1'
                $RawOutput = @(& ip_info --apis bulk --output_format jsontable --ip_addresses $UnseenIps)
                if ($LASTEXITCODE -ne 0) {
                    Write-IRT "ip_info query failed." -Level Warn
                }
                $JsonStart = -1
                for ($i = 0; $i -lt $RawOutput.Length; $i++) {
                    if ($RawOutput[$i] -match '^\{') { $JsonStart = $i; break }
                }
                if ($JsonStart -ge 0) {
                    $JsonText = ($RawOutput[$JsonStart..($RawOutput.Length - 1)]) -join "`n"
                    $JsonData = $JsonText | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($JsonData) {
                        foreach ($Prop in $JsonData.PSObject.Properties) {
                            $IpInfoTable[$Prop.Name] = $Prop.Value
                        }
                    }
                }
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
            }
        }

        #region WAIT ON MESSAGE TRACE
        # resolve message trace table once before the row loop
        $MessageTraceTable = $null
        if ($WaitOnMessageTrace) {
            $WaitInterval = 15
            $WaitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # wait for both user and AllUsers message traces to complete via WaitFlags
            if ($Global:IRT_WaitFlags) {
                while (-not ($Global:IRT_WaitFlags.MessageTraceUserDone -and $Global:IRT_WaitFlags.MessageTraceAllUsersDone)) {
                    if ($WaitStopwatch.Elapsed.TotalMinutes -ge $MaxWaitMinutes) {
                        Write-IRT "Timed out after ${MaxWaitMinutes} minutes waiting on message trace. Continuing without subjects." -Level Error
                        if ($Script:Test) {
                            Write-IRT "WaitFlags.MessageTraceUserDone = $($Global:IRT_WaitFlags.MessageTraceUserDone), WaitFlags.MessageTraceAllUsersDone = $($Global:IRT_WaitFlags.MessageTraceAllUsersDone)" -Level Warn
                        }
                        break
                    }
                    if ($Script:Test) {
                        $Elapsed = $WaitStopwatch.Elapsed.ToString('mm\:ss')
                        Write-IRT "Waiting on message trace (${Elapsed} elapsed). UserDone=$($Global:IRT_WaitFlags.MessageTraceUserDone), AllUsersDone=$($Global:IRT_WaitFlags.MessageTraceAllUsersDone)" -Level Warn
                    }
                    else {
                        Write-IRT "Waiting on message trace..." -Level Warn
                    }
                    Start-Sleep -Seconds $WaitInterval
                }
            }
        }

        # load message trace table from global
        if ($Global:IRT_MessageTraceTable -is [hashtable] -and $Global:IRT_MessageTraceTable.Count -gt 0) {
            $MessageTraceTable = $Global:IRT_MessageTraceTable
            if ($Script:Test) {
                Write-IRT "Using `$Global:IRT_MessageTraceTable ($($MessageTraceTable.Count) entries)" -Level Warn
            }
        }

        if ($Script:Test) {
            if ($MessageTraceTable) {
                Write-IRT "MessageTraceTable resolved with $($MessageTraceTable.Count) entries" -Level Warn
            }
            else {
                Write-IRT "No MessageTraceTable available - subjects will not be resolved" -Level Warn
            }
        }

        #region AUTO-DETECT SHEETS
        # build set of operations present in the logs
        $LogEntryOperations = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($LogEntry in $Log) {
            if ($LogEntry.AuditData.Operation) {
                [void]$LogEntryOperations.Add($LogEntry.AuditData.Operation)
            }
        }

        $MatchedSheets = [System.Collections.Generic.List[hashtable]]::new()

        if ($Metadata.ProfileTag -and $SheetRegistry.Contains($Metadata.ProfileTag)) {
            # profile-driven: only the tagged sheet
            $MatchedSheets.Add($SheetRegistry[$Metadata.ProfileTag])
        }
        else {
            # default: always include AllOperations, then add any specialized
            # sheets whose operations are present in the logs
            $MatchedSheets.Add($SheetRegistry['AllOperations'])
            foreach ($Key in $SheetRegistry.Keys) {
                if ($Key -eq 'AllOperations') { continue }
                $SheetEntry = $SheetRegistry[$Key]
                foreach ($Op in $SheetEntry.Operations) {
                    if ($LogEntryOperations.Contains($Op)) {
                        $MatchedSheets.Add($SheetEntry)
                        break
                    }
                }
            }
        }

        #region build workbook
        $Workbook = Open-ExcelPackage -Path $ExcelOutputPath -Create

        foreach ($SheetEntry in $MatchedSheets) {
            # filter logs - empty Operations array means all logs
            if ($SheetEntry.Operations.Count -gt 0) {
                $FilteredLogs = [System.Collections.Generic.List[PSObject]]::new()
                foreach ($LogEntry in $Log) {
                    if ($LogEntry.AuditData.Operation -in $SheetEntry.Operations) {
                        $FilteredLogs.Add($LogEntry)
                    }
                }
            }
            else {
                $FilteredLogs = $Log
            }

            if (($FilteredLogs | Measure-Object).Count -gt 0) {
                $BuildTitle = $SheetEntry.SheetTitle + $Metadata.TitleSuffix
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
                if ($SheetEntry.BuildFunction -eq 'Build-AllOperationSheet') {
                    if ($MessageTraceTable) { $SheetParams['MessageTraceTable'] = $MessageTraceTable }
                    if ($OperationsSheetData)  { $SheetParams['OperationsSheetData'] = $OperationsSheetData }
                }
                $Workbook = & $SheetEntry.BuildFunction @SheetParams
            }
        }

        #region output
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-IRT "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
