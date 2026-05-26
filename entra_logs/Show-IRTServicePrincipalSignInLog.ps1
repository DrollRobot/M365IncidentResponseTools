function Show-IRTServicePrincipalSignInLog {
    <#
    .SYNOPSIS
    Processes service principal sign-in log objects into an Excel spreadsheet.

    .DESCRIPTION
    Takes service principal sign-in log objects produced by Get-IRTServicePrincipalSignInLog
    (or imported from a raw XML export) and renders them into a formatted Excel workbook.
    Enriches IP addresses with geolocation data when -IpInfo is enabled.

    .PARAMETER Log
    A list of service principal sign-in log objects with a metadata entry at index 0.
    Produced by Get-IRTServicePrincipalSignInLog. Mutually exclusive with -XmlPath.

    .PARAMETER XmlPath
    Path to a raw XML file exported by Get-IRTServicePrincipalSignInLog. Mutually
    exclusive with -Log.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER IpInfo
    Enrich IP addresses with geolocation data. Default: $true.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Test
    Enable stopwatch timing output.

    .OUTPUTS
    None. Results are written to an Excel workbook.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string]  $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string]  $Font       = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = $true,
        [boolean] $Open   = $true,
        [switch]  $Test
    )

    begin {
        $ParameterSet = $PSCmdlet.ParameterSetName
        if ($Test -or $Script:Test) {
            $Script:Test = $true
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }
        $RawDateProperty  = 'CreatedDateTime'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            if ($Script:Test) {
                $TestText   = 'Importing from Xml'
                $TimerStart = $Stopwatch.Elapsed
            }

            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                [System.Collections.Generic.List[PSObject]]$Log = Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                $ErrorParams = @{
                    Category    = 'ReadError'
                    Message     = "Error importing from ${XmlPath}."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
            }
        }

        #region Metadata
        if ($Log[0].Metadata) {
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + '.xlsx'

        # get worksheet title from metadata
        $WorksheetTitle = $Metadata.Title

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
            if ($IpInfo) {
                if ($LogEntry.IpAddress) {
                    try {
                        $IpObject = [System.Net.IPAddress]$LogEntry.IpAddress
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
                $TestText   = 'Querying ip info'
                $TimerStart = $Stopwatch.Elapsed
            }

            $UnseenIps = @($IpInfoAddresses | Where-Object { -not $IpInfoTable.ContainsKey($_) })
            if ($UnseenIps.Count -gt 0) {
                $env:PYTHONUTF8 = '1'
                $RawOutput = @(& ip_info --apis bulk --output_format jsontable --ip_addresses $UnseenIps)
                if ($LASTEXITCODE -ne 0) {
                    Write-IRT "ip_info query failed." -Level Error
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

        #region ROW LOOP

        if ($Script:Test) {
            $TestText   = 'Row loop'
            $TimerStart = $Stopwatch.Elapsed
        }

        $RowCount = ($Log | Measure-Object).Count
        $Rows     = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $LogEntry = $Log[$i]

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
            }

            # IpAddress
            $IpText = if ($IpInfoTable -and $IpInfoTable.ContainsKey($LogEntry.IpAddress)) {
                $LogEntry.IpAddress + (' ' * 20) + "`n`n" + $IpInfoTable[$LogEntry.IpAddress]
            }
            else {
                $LogEntry.IpAddress
            }

            [void]$Rows.Add([PSCustomObject]@{
                Raw                  = $Raw
                $DateColumnHeader    = $DateTime
                ServicePrincipalName = $LogEntry.ServicePrincipalName
                AppDisplayName       = $LogEntry.AppDisplayName
                ResourceDisplayName  = $LogEntry.ResourceDisplayName
                Error                = ConvertTo-HumanErrorDescription -ErrorCode $LogEntry.Status.ErrorCode
                IpAddress            = $IpText
                City                 = $LogEntry.Location.City
                State                = $LogEntry.Location.State
                Co                   = $LogEntry.Location.CountryOrRegion
                Session              = $LogEntry.CorrelationId
                Token                = $LogEntry.UniqueTokenIdentifier
            })

            if ($Script:Test -and ($i % 100 -eq 0)) {
                $Percent = [int]( ($i / $RowCount) * 100 )
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
            Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
        }

        #region EXPORT SPREADSHEET

        if ($Script:Test) {
            $TestText   = 'Exporting to excel'
            $TimerStart = $Stopwatch.Elapsed
        }

        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $Metadata.FileNamePrefix
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-Error "Unable to open new Excel document."
            if ( Get-YesNo "Try closing open files." ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    throw "Unable to open new Excel document. Exiting."
                }
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($Script:Test) {
            $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
            Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow    = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ($workSheet.Tables.Address | Select-Object -First 1).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow    = ($workSheet.Tables.Address | Select-Object -First 1).Start.Row
        $EndColumn        = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow           = $WorkSheet.Dimension.End.Row

        $IpAddressColumn = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'IpAddress' }).Id | Convert-DecimalToExcelColumn

        #region CELL COLORING

        # ip addresses
        Add-IpAddressConditionalFormatting -Worksheet $WorkSheet -ColumnName 'IpAddress'

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'                 = 8
            $DateColumnHeader     = 26
            'ServicePrincipalName'= 30
            'AppDisplayName'      = 25
            'ResourceDisplayName' = 30
            'Error'               = 25
            'IpAddress'           = 20
            'City'                = 10
            'State'               = 10
            'Co'                  = 6
            'Session'             = 10
            'Token'               = 10
        }
        foreach ($ColName in $ColumnWidths.Keys) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
            if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
        }

        #region FORMATTING

        # set date format
        $FmtParams = @{
            Worksheet    = $Worksheet
            Range        = 'B:B'
            NumberFormat = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-ExcelRange @FmtParams

        # set text wrapping on ip address column
        $WrapParams = @{
            Worksheet = $Worksheet
            Range     = "${IpAddressColumn}:${IpAddressColumn}"
            WrapText  = $true
        }
        Set-ExcelRange @WrapParams

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = $Font
        }
        try {
            Set-ExcelRange @SetParams
        } catch {}

        # add left side border
        $BorderParams = @{
            Worksheet   = $Worksheet
            Range       = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft  = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        # set row height
        for ($i = $TableStartRow; $i -le $EndRow; $i++) {
            $Row = $Worksheet.Row($i)
            $Row.Height       = 15
            $Row.CustomHeight = $true
        }

        #region OUTPUT

        # save and close
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
