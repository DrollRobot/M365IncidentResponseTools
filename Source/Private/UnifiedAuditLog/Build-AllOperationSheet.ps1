function Build-AllOperationSheet {
    <#
    .SYNOPSIS
    Builds the AllOperations Excel worksheet for unified audit logs.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory)]
        $ExcelPackage,

        [hashtable] $MessageTraceTable,

        [Parameter(Mandatory)]
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [string] $Title,

        [Alias('OperationsSheetData')]
        [psobject[]] $OperationSheetData,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'

        $OperationsFromSheet = [System.Collections.Generic.HashSet[string]]::new()
        if ($OperationSheetData) {
            foreach ($Row in $OperationSheetData) {
                $Op = "$($Row.Workload)|$($Row.RecordType)|$($Row.Operation)"
                [void]$OperationsFromSheet.Add($Op)
            }
        }
        $OperationsFromLog = [System.Collections.Generic.HashSet[string]]::new()
    }

    process {

        #region ROW LOOP

        $RowCount = ($Log | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Row loop starting ($RowCount rows) [$Elapsed]")
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $RowCount; $i++) {

            $LogEntry = $Log[$i]

            # save operations to create complete list
            $OpKey = "$($LogEntry.AuditData.Workload)|" +
            "$($LogEntry.AuditData.RecordType)|$($LogEntry.AuditData.Operation)"
            [void]$OperationsFromLog.Add($OpKey)

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10

            #region USERIDS
            if ( $LogEntry.UserIds -match '^ServicePrincipal_.*$' ) {
                $SpName = $LogEntry.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            else {
                $UserIds = $LogEntry.UserIds
            }

            #region IPADDRESSES
            $IpAddresses = [System.Collections.Generic.Hashset[string]]::new()
            if ( $LogEntry.AuditData.ClientIP ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIP
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                }
            }
            if ( $LogEntry.AuditData.ActorIpAddress ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ActorIpAddress
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                } }
            if ( $LogEntry.AuditData.ClientIPAddress ) {
                try {
                    $IpObject = [System.Net.IPAddress]$LogEntry.AuditData.ClientIPAddress
                }
                catch {}
                if ($IpObject) {
                    [void]$IpAddresses.Add($IpObject.ToString())
                }
            }
            $IpText = if ($IpAddresses.Count -gt 0) {
                ($IpAddresses | Sort-Object) -join ', '
            } else { '' }

            #region Summary
            $RecordType = $LogEntry.RecordType
            $Operations = $LogEntry.Operations
            $OperationString = $RecordType + ' ' + $Operations
            $EmailParams = @{
                Log = $LogEntry
            }
            if ($MessageTraceTable) { $EmailParams['MessageTraceTable'] = $MessageTraceTable }
            switch ( $OperationString ) {
                'AzureActiveDirectory Add member to role.' {
                    $EventObject = Get-AddRemoveRoleSummary -Log $LogEntry
                }
                'AzureActiveDirectory Remove member from role.' {
                    $EventObject = Get-AddRemoveRoleSummary -Log $LogEntry
                }
                'AzureActiveDirectory Update user.' {
                    $EventObject = Get-UpdateUserSummary -Log $LogEntry
                }
                'AzureActiveDirectoryStsLogon UserLoggedIn' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoggedOff' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoginFailed' {
                    $EventObject = Get-LoginOperationSummary -Log $LogEntry -Cached:$Cached
                }
                'ExchangeAdmin New-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $LogEntry
                }
                'ExchangeAdmin Set-ConditionalAccessPolicy' {
                    $EventObject = Get-SetConditionalAccessPolicySummary -Log $LogEntry
                }
                'ExchangeAdmin Set-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $LogEntry
                }
                'ExchangeItemAggregated AttachmentAccess' {
                    $EventObject = Get-AttachmentAccessSummary -Log $LogEntry
                }
                'ExchangeItemAggregated MailItemsAccessed' {
                    $EventObject = Get-MailItemsAccessedSummary @EmailParams
                }
                'ExchangeItem Create' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $LogEntry
                }
                'ExchangeItem Send' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $LogEntry
                }
                'ExchangeItem Update' {
                    $EventObject = Get-ExchangeItemUpdateSummary -Log $LogEntry
                }
                'ExchangeItemGroup HardDelete' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'ExchangeItemGroup MoveToDeletedItems' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'ExchangeItemGroup SoftDelete' {
                    $EventObject = Get-ExchangeItemDeleteSummary @EmailParams
                }
                'SharePoint PageViewed' {
                    $EventObject = Get-PageViewedSummary -Log $LogEntry
                }
                'SharePoint PIMRoleAssigned' {
                    $EventObject = Get-PIMRoleAssignedSummary -Log $LogEntry -Cached:$Cached
                }
                'SharePoint SearchQueryPerformed' {
                    $EventObject = Get-SearchQueryPerformedSummary -Log $LogEntry
                }
                'SharePointFileOperation FileAccessed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileDownloaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileModified' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileModifiedExtended' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FilePreviewed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileSyncDownloadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileSyncUploadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                'SharePointFileOperation FileUploaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $LogEntry
                }
                default {
                    $EventObject = [pscustomobject]@{
                        Summary = ''
                    }
                }
            }

            # Date/Time
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw = $Raw
                    $DateColumnHeader = $DateTime
                    UserIds = $UserIds
                    Workload = $LogEntry.AuditData.Workload
                    RecordType = $LogEntry.RecordType
                    Operation = $LogEntry.AuditData.Operation
                    IpAddress = $IpText
                    Summary = $EventObject.Summary
                })

            if ($i % 100 -eq 0) {
                $Percent = [int]( ($i / $RowCount ) * 100 )
                $ProgressParams = @{
                    Id              = 1
                    Activity        = 'Row loop'
                    Status          = "Completed ${i} of ${RowCount}"
                    PercentComplete = $Percent
                }
                Write-Progress @ProgressParams
                Write-PSFMessage -Level 9 -Message (
                    "${FunctionName}: Row loop progress: $i / $RowCount ($Percent%)")
            }
        }

        Write-Progress -Id 1 -Activity 'Row loop' -Completed
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Row loop complete - $RowCount row(s) processed [$Elapsed]")

        #region EXPORT
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Export-Excel -> '$WorksheetName' " +
            "[$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $ExcelParams = @{
            ExcelPackage  = $ExcelPackage
            WorkSheetname = $WorksheetName
            Title         = $Title
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        $Workbook = $Rows | Export-Excel @ExcelParams
        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]

        #region FORMATTING
        if ($Worksheet.Tables.Count -gt 0) {

            # get table ranges
            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableAddress = $Worksheet.Tables.Address | Select-Object -First 1
            $TableStartColumn = $TableAddress.Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = $TableAddress.Start.Row

            $SummaryColEntry = $Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Summary' }
            $SummaryColumn = $SummaryColEntry.Id | Convert-DecimalToExcelColumn
            $OperationColEntry = $Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Operation' }
            $OperationColumn = $OperationColEntry.Id | Convert-DecimalToExcelColumn

            # IP address conditional formatting
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

            # operations conditional formatting
            if ($OperationSheetData) {
                foreach ($Row in $OperationSheetData) {
                    if ($Row.Risk -eq 'High') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:" +
                            "${OperationColumn}${EndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = $Row.Operation
                            BackgroundColor = 'LightPink'
                        }
                        Add-ConditionalFormatting @CFParams
                    }
                    if ($Row.Risk -eq 'Medium') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:" +
                            "${OperationColumn}${EndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = $Row.Operation
                            BackgroundColor = 'LightGoldenrodYellow'
                        }
                        Add-ConditionalFormatting @CFParams
                    }
                }
            }

            # column widths
            $ColumnWidths = @{
                'Raw'              = 8
                $DateColumnHeader  = 26
                'UserIds'          = 30
                'Workload'         = 25
                'RecordType'       = 25
                'Operation'        = 25
                'IpAddress'        = 25
                'Summary'          = 200
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # date format
            $DateFormatParams = @{
                Worksheet    = $Worksheet
                Range        = "B:B"
                NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
            }
            Set-ExcelRange @DateFormatParams

            # font
            $FontParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            try { Set-ExcelRange @FontParams } catch {}

            # left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            # text wrapping on Summary (applied last to prevent other formatting from resetting it)
            $SummaryWrapParams = @{
                Worksheet = $Worksheet
                Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @SummaryWrapParams

        } # end if Tables.Count

        #region MISSING OPERATIONS
        # FIXME no hard coded paths! use config path
        $AllOperationsFileName = 'UALAllOperations.xlsx'
        $OperationsToAdd = [System.Collections.Generic.HashSet[PSCustomObject]]::new()
        foreach ($o in $OperationsFromLog) {
            if ($OperationsFromSheet.Add($o)) {
                $Split = $o.Split('|')
                [void]$OperationsToAdd.Add(
                    [PSCustomObject]@{
                        Workload   = $Split[0]
                        RecordType = $Split[1]
                        Operation  = $Split[2]
                    }
                )
            }
        }
        if (($OperationsToAdd | Measure-Object).Count -gt 0) {
            $OperationsSheetPath = $Global:IRT_Config.AllOperationsSheetPath
            Write-IRT "Add to ${AllOperationsFileName}:" -Level Warn
            $OperationsToAdd | Format-Table | Out-Host
            Write-IRT "Appending to: ${OperationsSheetPath}" -Level Warn
            $ExportParams = @{
                Path          = $OperationsSheetPath
                WorksheetName = 'Operations'
                Append        = $true
            }
            $OperationsToAdd | Export-Excel @ExportParams
        }

        return $Workbook
    }
}
