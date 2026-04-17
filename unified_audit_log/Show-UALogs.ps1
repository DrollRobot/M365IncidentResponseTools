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

        [string] $TableStyle = 'Dark8',

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
        }
        else {
            Write-Host @Red "${Function}: No Metadata found."
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath =  "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $TitleDateFormat = "M/d/yy h:mmtt"
        $TitleEndDate = $EndDate.ToLocalTime().ToString($TitleDateFormat)
        $TitleStartDate = $StartDate.ToLocalTime().ToString($TitleDateFormat)
        $SheetTitle = $Metadata.SheetTitle
        $WorksheetTitle = "${SheetTitle} for ${Username}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

        # import alloperations csv
        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $AllOperationsFileName = 'unified_audit_log-all_operations.csv' # FIXME convert to using xlsx
        $OperationsCsvPath = Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}"
        $OperationsCsvData = Import-Csv -Path $OperationsCsvPath

        if ($Script:Test) {
            # build set of operations from csv to later output missing operations
            $OperationsFromCsv = [System.Collections.Generic.Hashset[string]]::new() 
            foreach ($Row in $OperationsCsvData) {
                [void]$OperationsFromCsv.Add("$($Row.Workload)|$($Row.RecordType)|$($Row.Operation)")
            }
            $OperationsFromLog = [System.Collections.Generic.Hashset[string]]::new()
        }

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

        #region Row Loop
        if ($Script:Test) {
            $TestText = "Row loop"
            $TimerStart = $Stopwatch.Elapsed
            Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
        }

        $RowCount = ($Logs | Measure-Object).Count
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $RowCount; $i++) { 
        
            $Log = $Logs[$i]

            # save operations to create complete list
            if ($Script:Test) {
                [void]$OperationsFromLog.Add(
                    "$($Log.AuditData.Workload)|$($Log.AuditData.RecordType)|$($Log.AuditData.Operation)"
                )
            }

            # Raw
            $Raw = $Log | ConvertTo-Json -Depth 10

            #region USERIDS
            # need to see if this works consistently across multiple log types
            if ( $Log.UserIds -match '^ServicePrincipal_.*$' ) {
                $SpName = $Log.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            # there's another userid format that needs to be added
            else {
                $UserIds = $Log.UserIds
            }

            #region IPADDRESSES
            # collect ips
            $CellLines = $null
            $IpAddresses = [System.Collections.Generic.Hashset[string]]::new()
                if ( $Log.AuditData.ClientIP ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIP
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpAddresses.Add($IpObject.ToString())
                    }
                }
                if ( $Log.AuditData.ActorIpAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ActorIpAddress
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpAddresses.Add($IpObject.ToString())
                    }                }
                if ( $Log.AuditData.ClientIPAddress ) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIPAddress
                    }
                    catch {}
                    if ($IpObject) {
                        [void]$IpAddresses.Add($IpObject.ToString())
                    }
                } 
            # loop through rows, replace with ip info
            if (($IpAddresses | Measure-Object).Count -gt 0) {

                # build cell text
                $CellLines = [System.Collections.Generic.List[string]]::new()
                $CellLines.Add((($IpAddresses | Sort-Object) -join ', ') + (' ' * 20))

                # add info from table
                foreach ($Ipaddress in $IpAddresses) {
                    $CellLines.Add($IpInfoTable[$Ipaddress]) 
                }
            }
            $IpText = $CellLines -join "`n`n"

            #region Summary
            $RecordType = $Log.RecordType
            $Operations = $Log.Operations
            $OperationString = $RecordType + ' ' + $Operations
            $EmailParams = @{
                Log = $Log
            }
            if ($MessageTraceTable) { $EmailParams['MessageTraceTable'] = $MessageTraceTable }
            switch ( $OperationString ) {
                'AzureActiveDirectory Add member to role.' {
                    $EventObject = Resolve-AzureActiveDirectoryAddRemoveRole -Log $Log
                }
                'AzureActiveDirectory Remove member from role.' {
                    $EventObject = Resolve-AzureActiveDirectoryAddRemoveRole -Log $Log
                }
                'AzureActiveDirectory Update user.' {
                    $EventObject = Resolve-AzureActiveDirectoryUpdateUser -Log $Log
                }
                'AzureActiveDirectoryStsLogon UserLoggedIn' {
                    $EventObject = Resolve-AzureActiveDirectoryLogin -Log $Log -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoggedOff' {
                    $EventObject = Resolve-AzureActiveDirectoryLogin -Log $Log -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoginFailed' {
                    $EventObject = Resolve-AzureActiveDirectoryLogin -Log $Log -Cached:$Cached
                }
                'ExchangeAdmin New-InboxRule' {
                    $EventObject = Resolve-ExchangeAdminInboxRule -Log $Log
                }
                'ExchangeAdmin Set-ConditionalAccessPolicy' {
                    $EventObject = Resolve-ExchangeAdminSetConditionalAccessPolicy -Log $Log
                }
                'ExchangeAdmin Set-InboxRule' {
                    $EventObject = Resolve-ExchangeAdminInboxRule -Log $Log
                }
                'ExchangeItemAggregated AttachmentAccess' {
                    $EventObject = Resolve-ExchangeItemAggregatedAttachmentAccess -Log $Log
                }
                'ExchangeItemAggregated MailItemsAccessed' {
                    $EventObject = Resolve-ExchangeItemAggregatedMailItemsAccessed @EmailParams
                }
                'ExchangeItem Create' {
                    $EventObject = Resolve-ExchangeItemSubject -Log $Log
                }
                'ExchangeItem Send' {
                    $EventObject = Resolve-ExchangeItemSubject -Log $Log
                }
                'ExchangeItem Update' {
                    $EventObject = Resolve-ExchangeItemUpdate -Log $Log
                }
                'ExchangeItemGroup HardDelete' {
                    $EventObject = Resolve-ExchangeItemGroupDelete @EmailParams
                }
                'ExchangeItemGroup MoveToDeletedItems' {
                    $EventObject = Resolve-ExchangeItemGroupDelete @EmailParams
                }
                'ExchangeItemGroup SoftDelete' {
                    $EventObject = Resolve-ExchangeItemGroupDelete @EmailParams
                }
                'SharePoint PageViewed' {
                    $EventObject = Resolve-SharePointPageViewed -Log $Log
                }
                'SharePoint PIMRoleAssigned' {
                    $EventObject = Resolve-SharePointPIMRoleAssigned -Log $Log -Cached:$Cached
                }
                'SharePoint SearchQueryPerformed' {
                    $EventObject = Resolve-SharePointSearchQueryPerformed -Log $Log
                }
                'SharePointFileOperation FileAccessed' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileDownloaded' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileModified' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileModifiedExtended' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FilePreviewed' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileSyncDownloadedFull' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileSyncUploadedFull' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                'SharePointFileOperation FileUploaded' {
                    $EventObject = Resolve-SharePointFileOperation -Log $Log
                }
                default {
                    $EventObject = [pscustomobject]@{
                        Summary = ''
                    }
                }
            }

            # Date/Time
            $DateTime = $null
            if ($Log.$RawDateProperty) {
                $DateTime = $Log.$RawDateProperty.ToLocalTime()
            }

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                Raw = $Raw
                # Tree = $Log | Format-Tree -Depth 10 | Out-String # need to figure out how to output to pipeline, not host
                $DateColumnHeader = $DateTime
                UserIds = $UserIds
                Workload = $Log.AuditData.Workload
                RecordType = $Log.RecordType
                Operation = $Log.AuditData.Operation
                IpAddresses = $IpText
                Summary = $EventObject.Summary
            })

            if ($Script:Test -and ($i % 100 -eq 0)) {
                $Percent = [int]( ($i / $RowCount ) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
            }
        }

        if ($Script:Test) {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed

            $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
            Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
        }

        #region EXPORT SPREADSHEET
        if ($Script:Test) {
            $TestText = "Exporting to excel"
            $TimerStart = $Stopwatch.Elapsed
            Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
        }

        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $FileNamePrefix
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            # AutoSize      = $true # apparently very slow?
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-Error "${Function}: Unable to open new Excel document."
            if ( Get-YesNo "Try closing open files." ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    throw "${Function}: Unable to open new Excel document. Exiting."
                }
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($Script:Test) {
            $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
            Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        if ($Worksheet.Tables.Count -gt 0) {

        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row

        $IpAddressColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'IpAddresses'}).Id | Convert-DecimalToExcelColumn
        $SummaryColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'Summary'}).Id | Convert-DecimalToExcelColumn
        $OperationColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'Operation'}).Id | Convert-DecimalToExcelColumn

        #region CELL COLORING

        # ip addresses
        # microsoft
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue  = 'microsoft'
            BackgroundColor = 'LightBlue'
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # vpn
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue  = 'vpn'
            BackgroundColor = 'LightPink'
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # tor
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue = 'tor'
            BackgroundColor = 'LightPink'
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # proxy
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue = 'proxy'
            BackgroundColor = 'LightPink'
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # hosting
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue  = 'hosting'
            BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#FACD90') 
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # cloud
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue  = 'cloud'
            BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#FACD90') 
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams
        # mobile
        $CFParams = @{
            Worksheet       = $WorkSheet
            Address         = "${IpAddressColumn}:${IpAddressColumn}"
            RuleType        = 'ContainsText'
            ConditionValue  = 'mobile'
            BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#F2CEEF') 
            StopIfTrue = $true
        }
        Add-ConditionalFormatting @CFParams

        # operations
        foreach ($Row in $OperationsCsvData) {

            # color high risk operations red
            if ($Row.Risk -eq 'High') {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${OperationColumn}${TableStartRow}:${OperationColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $Row.Operation
                    BackgroundColor = 'LightPink'
                }
                Add-ConditionalFormatting @CFParams
            }

            # color medium risk operations orange
            if ($Row.Risk -eq 'Medium') {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${OperationColumn}${TableStartRow}:${OperationColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $Row.Operation
                    BackgroundColor = 'LightGoldenrodYellow'
                }
                Add-ConditionalFormatting @CFParams
            }
        }        
        
        # if cell CONTAINS text anywhere, make background BLUE
        $Strings = @(
            # 'AppOwnerOrganizationId: Microsoft'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                RuleType        = 'ContainsText'
                ConditionValue  = $String
                BackgroundColor = 'LightBlue'
            }
            Add-ConditionalFormatting @CFParams
        }

        #region COLUMN WIDTH

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Raw' } ).Id 
        $Worksheet.Column($Column).Width = 8

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $DateColumnHeader } ).Id 
        $Worksheet.Column($Column).Width = 26

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'UserIds' } ).Id 
        $Worksheet.Column($Column).Width = 30

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Workload' } ).Id 
        $Worksheet.Column($Column).Width = 25

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'RecordType' } ).Id 
        $Worksheet.Column($Column).Width = 25

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Operation' } ).Id 
        $Worksheet.Column($Column).Width = 25

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'IpAddresses' } ).Id 
        $Worksheet.Column($Column).Width = 25

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Summary' } ).Id 
        $Worksheet.Column($Column).Width = 200

        #region FORMATTING

        # set date format 
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-Format @FmtParams

        # set text wrapping on specific columns
        $WrappingParams = @{
            Worksheet = $Worksheet
            Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
            WrapText  = $true
        }
        Set-ExcelRange @WrappingParams

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = 'Consolas'
        }
        try {
            Set-ExcelRange @SetParams
        } catch {}

        # add left side border
        $BorderParams = @{
            Worksheet = $Worksheet
            Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft = 'Thin'
            BorderColor = 'Black'
        }
        Set-Format @BorderParams

        } # end if ($Worksheet.Tables.Count -gt 0)

        #region OUTPUT

        # find operations from log that are missing in csv
        if ($Script:Test) {
            $OperationsToAdd = [System.Collections.Generic.HashSet[PSCustomObject]]::new() 
            foreach ($o in $OperationsFromLog) {
                if ($OperationsFromCsv.Add($o)) {
                    $Split = $o.Split('|')
                    [void]$OperationsToAdd.Add(
                        [PSCustomObject]@{
                            Workload = $Split[0]
                            RecordType = $Split[1]
                            Operation = $Split[2]
                        }
                    )
                }
            }
            # output for user
            if (($OperationsToAdd | Measure-Object).Count -gt 0) {
                Write-Host @Yellow "${Function}: Add to ${AllOperationsFileName}:" | Out-Host
                $OperationsToAdd | Format-Table | Out-Host
                Write-Host @Yellow "${Function}: Exporting to: operations_to_add.csv" | Out-Host
                $OperationsToAdd | Export-Csv -Path "operations_to_add.csv" -NoTypeInformation
            }
        }
                    
        # save and close
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