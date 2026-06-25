function Get-IRTAllEntraDevice {
    <#
    .SYNOPSIS
    Exports every Entra ID (Azure AD) device to a spreadsheet, newest registration first.

    .DESCRIPTION
    Queries Microsoft Graph for all registered/joined Entra devices and writes them to an
    Excel workbook sorted by registration date (newest first). Threat actors sometimes
    register their own device against a compromised identity to persist and to satisfy
    device-based Conditional Access, so surfacing the most recently registered devices at
    the top of the sheet makes new, unexpected registrations easy to spot.

    As much device detail as Graph exposes is included: join/trust type, registered owner,
    operating system, compliance and management state, ownership, enrollment type, and the
    registration and last sign-in timestamps.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export the raw device objects to a .xml file alongside the workbook.
    Defaults to IRT_Config.ExportXml.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Worksheet font. Defaults to IRT_Config.ExcelFont.

    .EXAMPLE
    Get-IRTAllEntraDevice
    Exports all Entra devices to a spreadsheet and opens it.

    .EXAMPLE
    Get-IRTAllEntraDevice -Open $false -Xml $true
    Writes the spreadsheet and a raw XML dump without opening the workbook.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Get-IRTAllEntraDevices',
        'GetAllEntraDevice', 'GetAllEntraDevices',
        'AllEntraDevices'
    )]
    [CmdletBinding()]
    param (
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $Import = @(
            'Microsoft.Graph.Identity.DirectoryManagement'
            'ImportExcel'
            'PSFramework'
        )
        Import-IRTModule -Name $Import

        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $CurrentPath = Get-Location
        $DomainName = Get-DefaultDomain

        # file names
        $FileNamePrefix = 'EntraDevices'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = (Get-Date).ToString($FileNameDateFormat)
        $WorksheetName = 'EntraDevices'
        $ExcelOutputPath = "${FileNamePrefix}_${DomainName}_${FileNameDate}.xlsx"

        # date columns
        $RegDateHeader = 'RegistrationDateTime'
        $LastSignInHeader = 'ApproximateLastSignInDateTime'
        $DateNumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
    }

    process {

        # --- query Entra devices ---
        $GetProperties = @(
            'Id'
            'DeviceId'
            'DisplayName'
            'AccountEnabled'
            'OperatingSystem'
            'OperatingSystemVersion'
            'TrustType'
            'RegistrationDateTime'
            'ApproximateLastSignInDateTime'
            'IsCompliant'
            'IsManaged'
            'IsRooted'
            'DeviceOwnership'
            'EnrollmentType'
            'ProfileType'
            'ManagementType'
            'MdmAppId'
        )
        Write-IRT "Retrieving all Entra devices."
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Get-MgDevice [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $GetParams = @{
            All            = $true
            Property       = $GetProperties
            ExpandProperty = 'RegisteredOwners'
        }
        $Devices = Get-MgDevice @GetParams

        $Count = ($Devices | Measure-Object).Count
        if ($Count -gt 0) {
            Write-IRT "Retrieved ${Count} devices."
        }
        else {
            Write-IRT "No devices found." -Level Warn
            return
        }

        # --- optional raw xml dump ---
        if ($Xml) {
            $XmlFileName = "${FileNamePrefix}_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $XmlFileName
            Write-IRT "Saving raw devices to: ${XmlFileName}"
            $Devices | Export-Clixml -Depth 8 -Path $XmlOutputPath
        }

        # --- build display rows (sorted newest-registration-first) ---
        $Rows = Build-EntraDeviceRow -Device $Devices

        # --- export to excel ---
        $TitleDate = (Get-Date).ToString('M/d/yy h:mmtt').ToLower()
        $WorksheetTitle = "Entra devices for ${DomainName} as of ${TitleDate}."

        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Export-Excel [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $WorksheetName
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            # surface the real error -- a bare `$_` is easy to miss, and the retry
            # prompt below throws under automation, masking the original cause
            Write-IRT "Error exporting to Excel: $($_.Exception.Message)" -Level Error
            if ( Get-YesNo "The file may be open in Excel. Close it and try again?" ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    Write-IRT "Error exporting to Excel: $($_.Exception.Message)" -Level Error
                    return
                }
            }
            else {
                return
            }
        }

        # post-export formatting only runs when a workbook came back from Export-Excel
        if ($Workbook) {
            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]

            # table ranges
            $SheetStartColumn =
            $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $TableStartColumn = (
                $Worksheet.Tables.Address | Select-Object -First 1
            ).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = (
                $Worksheet.Tables | Select-Object -First 1
            ).Address.Start.Row + 1
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row

            # column letters for the date columns (used by date formatting below)
            $RegDateColumn = (
                $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $RegDateHeader }
            ).Id | Convert-DecimalToExcelColumn
            $LastSignInColumn = (
                $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $LastSignInHeader }
            ).Id | Convert-DecimalToExcelColumn

            $TableRange = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"

            # --- conditional formatting (none active) ---
            # Machinery is left in place so rules are easy to add later: target the
            # table body via $TableRange (and a column letter from the lookup above),
            # then call Add-ConditionalFormatting, e.g.
            #   Add-ConditionalFormatting -WorkSheet $Worksheet -Address $TableRange
            #     -RuleType Expression -ConditionValue '=...' -BackgroundColor LightYellow

            # column widths
            $ColumnWidths = @{
                'Raw'                    = 8
                $RegDateHeader           = 27
                $LastSignInHeader        = 27
                'DisplayName'            = 28
                'JoinType'               = 16
                'TrustType'              = 12
                'AccountEnabled'         = 14
                'OperatingSystem'        = 16
                'OperatingSystemVersion' = 18
                'RegisteredOwnerUPN'     = 32
                'DeviceOwnership'        = 16
                'EnrollmentType'         = 18
                'ProfileType'            = 14
                'ManagementType'         = 16
                'MdmAppId'               = 38
                'DeviceId'               = 38
                'Id'                     = 38
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = (
                    $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }
                ).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # date number format on the two date columns
            foreach ($DateCol in @($RegDateColumn, $LastSignInColumn)) {
                $FmtParams = @{
                    Worksheet    = $Worksheet
                    Range        = "${DateCol}:${DateCol}"
                    NumberFormat = $DateNumberFormat
                }
                Set-ExcelRange @FmtParams
            }

            # font
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            Set-ExcelRange @SetParams

            # left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = $TableRange
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            # save and open
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
}
