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

        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [boolean] $WaitOnMessageTrace = $false,
        [int] $MaxWaitMinutes = 15,
        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-Verbose "${FunctionName}: Import-CliXml $Elapsed"
                $RawLog = Import-CliXml -Path $ResolvedXmlPath
                [System.Collections.Generic.List[PSObject]] $Log = $RawLog
            }
            catch {
                $_
                Write-IRT "Error importing from ${XmlPath}." -Level Error
                return
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
    }

    process {

        #region FIRST LOOP

        foreach ($LogEntry in $Log) {
            # convert audit data to powershell objects
            $LogEntry.AuditData = $LogEntry.AuditData | ConvertFrom-Json -Depth 10
        }

        #region WAIT ON MESSAGE TRACE
        # resolve message trace table once before the row loop
        $MessageTraceTable = $null
        if ($WaitOnMessageTrace) {
            $WaitInterval = 15
            $WaitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # wait for both user and AllUsers message traces to complete via WaitFlags
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Waiting on message trace $Elapsed"
            if ($Global:IRT_WaitFlags) {
                while (-not ($Global:IRT_WaitFlags.MessageTraceUserDone -and
                    $Global:IRT_WaitFlags.MessageTraceAllUsersDone)) {
                    if ($WaitStopwatch.Elapsed.TotalMinutes -ge $MaxWaitMinutes) {
                        $Msg = "Timed out after ${MaxWaitMinutes} minutes waiting on " +
                            "message trace. Continuing without subjects."
                        Write-IRT $Msg -Level Error
                        break
                    }
                    $WaitElapsed  = $WaitStopwatch.Elapsed.ToString('mm\:ss')
                    $UserDone = $Global:IRT_WaitFlags.MessageTraceUserDone
                    $AllDone  = $Global:IRT_WaitFlags.MessageTraceAllUsersDone
                    Write-IRT "Waiting on message trace..." -Level Warn
                    $WaitMsg = "${FunctionName}: MessageTrace wait ${WaitElapsed} elapsed. " +
                        "UserDone=${UserDone}, AllUsersDone=${AllDone}"
                    Write-Verbose $WaitMsg
                    Start-Sleep -Seconds $WaitInterval
                }
            }
        }

        # load message trace table from global
        if ($Global:IRT_MessageTraceTable -is [hashtable] -and
            $Global:IRT_MessageTraceTable.Count -gt 0) {
            $MessageTraceTable = $Global:IRT_MessageTraceTable
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
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Request-GraphServicePrincipal $Elapsed"
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
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
                    WorksheetName = $SheetEntry.SheetName
                    Title         = $BuildTitle
                    TableStyle    = $TableStyle
                    Font          = $Font
                    Cached        = $Cached
                }
                # AllOperations needs extra parameters
                if ($SheetEntry.BuildFunction -eq 'Build-AllOperationSheet') {
                    if ($MessageTraceTable) {
                        $SheetParams['MessageTraceTable'] = $MessageTraceTable
                    }
                    if ($OperationsSheetData) {
                        $SheetParams['OperationsSheetData'] = $OperationsSheetData
                    }
                }
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                $BuildFn = $SheetEntry.BuildFunction
                Write-Verbose "${FunctionName}: $BuildFn $Elapsed"
                $Workbook = & $SheetEntry.BuildFunction @SheetParams
            }
        }

        # enrich IP addresses with ip_info data
        if ($IpInfo) {
            foreach ($ws in $Workbook.Workbook.Worksheets) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    $WsName = $ws.Name
                    Write-Verbose "${FunctionName}: Add-IpInfoToSheet ($WsName) $Elapsed"
                Add-IpInfoToSheet -Worksheet $ws -ColumnName 'IpAddress'
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
