function Get-LoginOperationSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory UserLoggedIn, UserLoggedOff, and UserLoginFailed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log,

        [switch] $Cached
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ErrorNumber
        $ErrorDescription = ConvertTo-HumanErrorDescription -ErrorCode $Log.AuditData.ErrorNumber
        $SummaryLines.Add("Error: $ErrorDescription")

        # Target
        $TargetId = $Log.AuditData.Target.ID
        if ($TargetId) {
            # ensure global variable exists
            Request-GraphServicePrincipal -Return 'none' -Cached:$Cached

            # fetch name from table
            $TargetName = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            if ($TargetName) {
                $SummaryLines.Add("TargetApp: $TargetName")
            }
        }

        # DeviceProperties
        $DispNameEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DisplayName' }
        $DisplayName   = $DispNameEntry.Value
        if (-not $DisplayName) {
            $DevNameEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceName' }
            $DisplayName  = $DevNameEntry.Value
        }
        if ($DisplayName) {$SummaryLines.Add("DeviceDisplayName: $DisplayName")}
        $OS = ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'OS' }).Value
        if ($OS) { $SummaryLines.Add("OS: $OS") }
        $DevBrowserEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DeviceBrowser' }
        $Browser         = $DevBrowserEntry.Value
        if (-not $Browser) {
            $BrwTypeEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'BrowserType' }
            $Browser      = $BrwTypeEntry.Value
        }
        if ($Browser) { $SummaryLines.Add("Browser: $Browser") }
        $TrustEntry = $Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'TrustType' }
        $TrustType  = Convert-TrustType -TrustType $TrustEntry.Value
        if ($TrustType) { $SummaryLines.Add("Trust: $TrustType") }

        # UserAgent
        $UserAgentEntry = $Log.AuditData.ExtendedProperties |
            Where-Object { $_.Name -eq 'UserAgent' }
        $UserAgent      = $UserAgentEntry.Value
        if ($UserAgent) {$SummaryLines.Add("UserAgent: $UserAgent")}

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}

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
        # $Function = $MyInvocation.MyCommand.Name
        $RawDateProperty = 'CreationDate'
        $DateColumnHeader = 'DateTime'
    }

    process {

        #region ROW LOOP
        $RowCount = ($Logs | Measure-Object).Count
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
            $ErrCode          = $Log.AuditData.ErrorNumber
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
                Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
                $Application = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            }
            if (-not $Application) { $Application = $TargetId }

            # DeviceProperties
            $DevDispEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DisplayName' }
            $DeviceName   = $DevDispEntry.Value
            if (-not $DeviceName) {
                $DevDevNameEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'DeviceName' }
                $DeviceName      = $DevDevNameEntry.Value
            }
            $OS = ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'OS'}).Value
            $DevBrwEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceBrowser' }
            $Browser     = $DevBrwEntry.Value
            if (-not $Browser) {
                $DevBrwTypeEntry = $Log.AuditData.DeviceProperties |
                    Where-Object { $_.Name -eq 'BrowserType' }
                $Browser         = $DevBrwTypeEntry.Value
            }
            $DevTrustEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'TrustType' }
            $Trust         = Convert-TrustType -TrustType $DevTrustEntry.Value
            $DevSessEntry  = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'SessionId' }
            $SessionId     = $DevSessEntry.Value

            # UserAgent
            $DevUserAgentEntry = $Log.AuditData.ExtendedProperties |
                Where-Object { $_.Name -eq 'UserAgent' }
            $UserAgent         = $DevUserAgentEntry.Value

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

        #region EXPORT
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

            $SheetStartColumn = $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableAddress     = $Worksheet.Tables.Address | Select-Object -First 1
            $TableStartColumn = $TableAddress.Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow    = $TableAddress.Start.Row

            # IP address conditional formatting
            Add-IpAddressConditionalFormatting -Worksheet $Worksheet -ColumnName 'IpAddress'

            # Application conditional formatting - highlight PowerShell/CLI tools
            $AppColEntry = $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Application' }
            $AppColumn   = $AppColEntry.Id | Convert-DecimalToExcelColumn
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

            # # Text wrapping on IpAddress and UserAgent
            # $IpCol = ($Worksheet.Tables[0].Columns |
            #     Where-Object {$_.Name -eq 'IpAddress'}).Id |
            #     Convert-DecimalToExcelColumn
            # $IpWrapParams = @{
            #     Worksheet = $Worksheet
            #     Range     = "${IpCol}${TableStartRow}:${IpCol}${EndRow}"
            #     WrapText  = $true
            # }
            # Set-ExcelRange @IpWrapParams # FIXME maybe we don't want text wrapping?

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
