function Build-AllOperationsSheet {
    <#
    .SYNOPSIS
    Builds the AllOperations Excel worksheet for unified audit logs.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[PSObject]] $Logs,

        [Parameter(Mandatory)]
        $ExcelPackage,

        [Parameter(Mandatory)]
        [hashtable] $IpInfoTable,

        [hashtable] $MessageTraceTable,

        [Parameter(Mandatory)]
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [string] $Title,

        [psobject[]] $OperationsSheetData,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Cached
    )

    begin {
        $Function = $MyInvocation.MyCommand.Name
        $Yellow = @{ ForegroundColor = 'Yellow' }
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'

        if ($Script:Test) {
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $OperationsFromSheet = [System.Collections.Generic.HashSet[string]]::new()
            if ($OperationsSheetData) {
                foreach ($Row in $OperationsSheetData) {
                    [void]$OperationsFromSheet.Add("$($Row.Workload)|$($Row.RecordType)|$($Row.Operation)")
                }
            }
            $OperationsFromLog = [System.Collections.Generic.HashSet[string]]::new()
        }
    }

    process {

        #region ROW LOOP
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
            if ( $Log.UserIds -match '^ServicePrincipal_.*$' ) {
                $SpName = $Log.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            else {
                $UserIds = $Log.UserIds
            }

            #region IPADDRESSES
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
            if (($IpAddresses | Measure-Object).Count -gt 0) {
                $CellLines = [System.Collections.Generic.List[string]]::new()
                $CellLines.Add((($IpAddresses | Sort-Object) -join ', ') + (' ' * 20))
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
                    $EventObject = Get-AddRemoveRoleSummary -Log $Log
                }
                'AzureActiveDirectory Remove member from role.' {
                    $EventObject = Get-AddRemoveRoleSummary -Log $Log
                }
                'AzureActiveDirectory Update user.' {
                    $EventObject = Get-UpdateUserSummary -Log $Log
                }
                'AzureActiveDirectoryStsLogon UserLoggedIn' {
                    $EventObject = Get-LoginOperationsSummary -Log $Log -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoggedOff' {
                    $EventObject = Get-LoginOperationsSummary -Log $Log -Cached:$Cached
                }
                'AzureActiveDirectoryStsLogon UserLoginFailed' {
                    $EventObject = Get-LoginOperationsSummary -Log $Log -Cached:$Cached
                }
                'ExchangeAdmin New-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $Log
                }
                'ExchangeAdmin Set-ConditionalAccessPolicy' {
                    $EventObject = Get-SetConditionalAccessPolicySummary -Log $Log
                }
                'ExchangeAdmin Set-InboxRule' {
                    $EventObject = Get-InboxRuleSummary -Log $Log
                }
                'ExchangeItemAggregated AttachmentAccess' {
                    $EventObject = Get-AttachmentAccessSummary -Log $Log
                }
                'ExchangeItemAggregated MailItemsAccessed' {
                    $EventObject = Get-MailItemsAccessedSummary @EmailParams
                }
                'ExchangeItem Create' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $Log
                }
                'ExchangeItem Send' {
                    $EventObject = Get-ExchangeItemCreateSendSummary -Log $Log
                }
                'ExchangeItem Update' {
                    $EventObject = Get-ExchangeItemUpdateSummary -Log $Log
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
                    $EventObject = Get-PageViewedSummary -Log $Log
                }
                'SharePoint PIMRoleAssigned' {
                    $EventObject = Get-PIMRoleAssignedSummary -Log $Log -Cached:$Cached
                }
                'SharePoint SearchQueryPerformed' {
                    $EventObject = Get-SearchQueryPerformedSummary -Log $Log
                }
                'SharePointFileOperation FileAccessed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileDownloaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileModified' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileModifiedExtended' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FilePreviewed' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileSyncDownloadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileSyncUploadedFull' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
                }
                'SharePointFileOperation FileUploaded' {
                    $EventObject = Get-SharePointFileOperationSummary -Log $Log
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

        #region EXPORT
        if ($Script:Test) {
            $TestText = "Exporting to excel"
            $TimerStart = $Stopwatch.Elapsed
            Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
        }

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

        if ($Script:Test) {
            $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
            Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
        }

        #region FORMATTING
        if ($Worksheet.Tables.Count -gt 0) {

            # get table ranges
            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableStartColumn = ($Worksheet.Tables.Address | Select-Object -First 1).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ($Worksheet.Tables.Address | Select-Object -First 1).Start.Row

            $SummaryColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'Summary'}).Id | Convert-DecimalToExcelColumn
            $OperationColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'Operation'}).Id | Convert-DecimalToExcelColumn

            # IP address conditional formatting
            Add-IpAddressConditionalFormatting -Worksheet $Worksheet -ColumnName 'IpAddresses'

            # operations conditional formatting
            if ($OperationsSheetData) {
                foreach ($Row in $OperationsSheetData) {
                    if ($Row.Risk -eq 'High') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:${OperationColumn}${EndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = $Row.Operation
                            BackgroundColor = 'LightPink'
                        }
                        Add-ConditionalFormatting @CFParams
                    }
                    if ($Row.Risk -eq 'Medium') {
                        $CFParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${OperationColumn}${TableStartRow}:${OperationColumn}${EndRow}"
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
                'IpAddresses'      = 25
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
            Set-Format @DateFormatParams

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
            Set-Format @BorderParams

            # text wrapping on Summary (applied last to prevent other formatting from resetting it)
            $SummaryWrapParams = @{
                Worksheet = $Worksheet
                Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @SummaryWrapParams

        } # end if Tables.Count

        #region MISSING OPERATIONS
        if ($Script:Test) {
            $AllOperationsFileName = 'unified_audit_log-all_operations.xlsx'
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
                $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
                $AllOperationsConfig = $Global:IRT_Config.AllOperationsSheetPath
                $OperationsSheetPath = if ($AllOperationsConfig) { $AllOperationsConfig } else { Join-Path -Path $ModuleRoot -ChildPath "data\${AllOperationsFileName}" }
                Write-Host @Yellow "${Function}: Add to ${AllOperationsFileName}:" | Out-Host
                $OperationsToAdd | Format-Table | Out-Host
                Write-Host @Yellow "${Function}: Appending to: ${OperationsSheetPath}" | Out-Host
                $OperationsToAdd | Export-Excel -Path $OperationsSheetPath -WorksheetName 'Operations' -Append
            }
        }

        return $Workbook
    }
}
