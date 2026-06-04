function Build-UserLoginOperationsSheet {
    <#
    .SYNOPSIS
    Builds an Excel worksheet with sign-in specific columns for UserLoggedIn/Off/Failed UAL events.

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
        [string] $WorksheetName,

        [Parameter(Mandatory)]
        [string] $Title,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
    }

    process {

        #region ROW LOOP
        $RowCount = ($Logs | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Row loop starting ($RowCount rows) [$Elapsed]")
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)

        for ($i = 0; $i -lt $RowCount; $i++) {

            $Log = $Logs[$i]

            # Raw
            $Raw = $Log | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($Log.$RawDateProperty) { $DateTime = $Log.$RawDateProperty.ToLocalTime() }

            # UserIds/Actor
            if ($Log.UserIds -match '^ServicePrincipal_.*$') {
                $SpName = $Log.AuditData.Actor[0].ID
                $UserIds = "SP: ${SpName}"
            }
            else {
                $UserIds = $Log.UserIds
            }
            # FIXME If no userid, parse Id from $Log.AuditData.Actor[0].ID and resolve to name

            # Operation
            $Operation = $Log.AuditData.Operation

            # Error
            $ErrCode = $Log.AuditData.ErrorNumber
            $ErrorDescription = ConvertTo-HumanErrorDescription -ErrorCode $ErrCode

            # IpAddress
            $IpAddresses = [System.Collections.Generic.Hashset[string]]::new()
            if ($Log.AuditData.ClientIP) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIP } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            if ($Log.AuditData.ActorIpAddress) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ActorIpAddress } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            if ($Log.AuditData.ClientIPAddress) {
                try { $IpObject = [System.Net.IPAddress]$Log.AuditData.ClientIPAddress } catch {}
                if ($IpObject) { [void]$IpAddresses.Add($IpObject.ToString()) }
            }
            $IpText = if ($IpAddresses.Count -gt 0) {
                ($IpAddresses | Sort-Object) -join ', '
            } else { '' }

            # Application (Target)
            $Application = $null
            $TargetId = $Log.AuditData.Target.ID
            if ($TargetId) {
                $Application = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            }
            if (-not $Application) { $Application = $TargetId }

            # DeviceProperties
            $DevDispEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DisplayName' }
            $DeviceName = $DevDispEntry.Value
            if (-not $DeviceName) {
                $DevDevNameEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'DeviceName' }
                $DeviceName = $DevDevNameEntry.Value
            }
            $OS = ($Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'OS' }).Value
            $DevBrwEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceBrowser' }
            $Browser = $DevBrwEntry.Value
            if (-not $Browser) {
                $DevBrwTypeEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'BrowserType' }
                $Browser = $DevBrwTypeEntry.Value
            }
            $DevTrustEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'TrustType' }
            $Trust = Convert-TrustType -TrustType $DevTrustEntry.Value
            $DevSessEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'SessionId' }
            $SessionId = $DevSessEntry.Value

            # UserAgent
            $DevUserAgentEntry = $Log.AuditData.ExtendedProperties |
                Where-Object { $_.Name -eq 'UserAgent' }
            $UserAgent = $DevUserAgentEntry.Value

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw          = $Raw
                    $DateColumnHeader = $DateTime
                    UserIds      = $UserIds
                    Operation    = $Operation
                    Error        = $ErrorDescription
                    IpAddress    = $IpText
                    Application  = $Application
                    Browser      = $Browser
                    OS           = $OS
                    Trust        = $Trust
                    DeviceName   = $DeviceName
                    SessionId    = $SessionId
                    UserAgent    = $UserAgent
                })
        }

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
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Formatting [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        if ($Worksheet.Tables.Count -gt 0) {

            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableAddress = $Worksheet.Tables.Address | Select-Object -First 1
            $TableStartColumn = $TableAddress.Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = $TableAddress.Start.Row

            # IP address conditional formatting
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Add-IpInfoToSheet " +
                "[$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

            # Application conditional formatting - highlight PowerShell/CLI tools
            $AppColEntry = $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Application' }
            $AppColumn = $AppColEntry.Id | Convert-DecimalToExcelColumn
            $PsAppStrings = @(
                'Azure Active Directory PowerShell'
                'Microsoft Azure CLI'
                'Microsoft Exchange REST API Based Powershell'
                'Microsoft Graph Command Line Tools'
            )
            foreach ($String in $PsAppStrings) {
                $CFParams = @{
                    Worksheet       = $Worksheet
                    Address         = "${AppColumn}${TableStartRow}:${AppColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $String
                    BackgroundColor = 'LightPink'
                }
                Add-ConditionalFormatting @CFParams
            }

            # Column widths
            $ColumnWidths = @{
                'Raw'         = 8
                $DateColumnHeader = 26
                'UserIds'     = 30
                'Operation'   = 20
                'Error'       = 25
                'IpAddress'   = 25
                'Application' = 25
                'Browser'     = 20
                'OS'          = 12
                'Trust'       = 12
                'DeviceName'  = 20
                'SessionId'   = 20
                'UserAgent'   = 150
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # Date format
            $DateFormatParams = @{
                Worksheet    = $Worksheet
                Range        = 'B:B'
                NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
            }
            Set-ExcelRange @DateFormatParams

            # Font
            try {
                $FontParams = @{
                    Worksheet = $Worksheet
                    Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                    FontName  = $Font
                }
                Set-ExcelRange @FontParams
            } catch {}

            # Left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

        } # end if Tables.Count

        return $Workbook
    }
}
