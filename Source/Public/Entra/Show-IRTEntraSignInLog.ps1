function Show-IRTEntraSignInLog {
    <#
	.SYNOPSIS
	Processes Sign in log .XML file into Excel spreadsheet.

	.NOTES
	Version: 1.1.3
    1.1.3 - Added timers/progress for testing.
	#>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true
    )

    begin {
        Import-IRTModule -Name 'ImportExcel', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'CreatedDateTime'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                Write-PSFMessage -Level 8 -Message "${FunctionName}: Import-CliXml [$Elapsed]"
                [System.Collections.Generic.List[PSObject]]$Log =
                Import-CliXml -Path $ResolvedXmlPath
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
        }

        #region Metadata
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # build file name
        $ExcelOutputPath = $Metadata.FileName + ".xlsx"

        # get worksheet title from metadata
        $WorksheetTitle = $Metadata.Title
    }

    process {

        #region ROW LOOP

        $RowCount = ($Log | Measure-Object).Count
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Row loop starting ($RowCount rows) [$Elapsed]")
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
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
            $IpText = $LogEntry.IpAddress

            # application display name / resource id
            if ( $LogEntry.AppDisplayName ) {
                $AppDisplayName = $LogEntry.AppDisplayName
            }
            else {
                $AppDisplayName = $LogEntry.ResourceId
            }

            # compress trust
            $Trust = Convert-TrustType -TrustType $LogEntry.DeviceDetail.TrustType

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                    Raw = $Raw
                    $DateColumnHeader = $DateTime
                    UserPrincipalName = $LogEntry.UserPrincipalName
                    Error = ConvertTo-HumanErrorDescription -ErrorCode $LogEntry.Status.ErrorCode
                    IpAddress = $IpText
                    City = $LogEntry.Location.City
                    State = $LogEntry.Location.State
                    Co = $LogEntry.Location.CountryOrRegion
                    Application = $AppDisplayName
                    Browser = $LogEntry.DeviceDetail.Browser
                    OS = $LogEntry.DeviceDetail.OperatingSystem
                    Trust = $Trust
                    UserAgent = $LogEntry.UserAgent
                    Session = $LogEntry.CorrelationId
                    Token = $LogEntry.UniqueTokenIdentifier
                })

            if ($VerbosePreference -ne 'SilentlyContinue' -and ($i % 100 -eq 0)) {
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

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Progress -Id 1 -Activity 'Row loop' -Completed
        }

        #region EXPORT SPREADSHEET
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Export-Excel [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $Metadata.FileNamePrefix
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

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column |
            Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $IpAddressColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'IpAddress' }).Id |
                Convert-DecimalToExcelColumn
        $ApplicationColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'Application' }).Id |
                Convert-DecimalToExcelColumn
        $UserAgentColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'UserAgent' }).Id |
                Convert-DecimalToExcelColumn

        #region CELL COLORING

        # ip address enrichment and conditional formatting
        if ($IpInfo) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message "${FunctionName}: Add-IpInfoToSheet [$Elapsed]"
            Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'
        }

        # applications
        $Strings = @(
            'Azure Active Directory PowerShell'
            'Microsoft Azure CLI'
            'Microsoft Exchange REST API Based Powershell'
            'Microsoft Graph Command Line Tools'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${ApplicationColumn}:${ApplicationColumn}"
                RuleType        = 'Equal'
                ConditionValue  = $String
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }

        # user agents
        $Strings = @(
            'axios'
            'BAV2ROPC'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${UserAgentColumn}:${UserAgentColumn}"
                RuleType        = 'ContainsText'
                ConditionValue  = $String
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'               = 8
            $DateColumnHeader   = 26
            'UserPrincipalName' = 30
            'Error'             = 25
            'IpAddress'         = 20
            'City'              = 10
            'State'             = 10
            'Co'                = 6
            'Application'       = 25
            'Browser'           = 20
            'OS'                = 12
            'Trust'             = 12
            'UserAgent'         = 150
            'Session'           = 10
            'Token'             = 10
        }
        foreach ($ColName in $ColumnWidths.Keys) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
            if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
        }

        #region FORMATTING

        # set date format
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-ExcelRange @FmtParams

        # set text wrapping on ip address column
        $WrapParams = @{
            Worksheet = $Worksheet
            Range = "${IpAddressColumn}:${IpAddressColumn}"
            WrapText = $true
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
            Worksheet = $Worksheet
            Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        # set row height
        # $HeightParams = @{
        #     Worksheet = $Worksheet
        #     Row = ($TableStartRow..$EndRow)
        #     Height = 15
        # }
        # Set-ExcelRow @HeightParams
        for ( $i = $TableStartRow; $i -le $EndRow; $i++ ) {
            $Row = $Worksheet.Row($i)
            $Row.Height = 15
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
