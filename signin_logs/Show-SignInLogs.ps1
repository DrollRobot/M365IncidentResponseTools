function Show-SignInLogs {
	<#
	.SYNOPSIS
	Processes Sign in log .XML file into Excel spreadsheet.
	
	.NOTES
	Version: 1.1.3
    1.1.3 - Added timers/progress for testing.
	#>
    [CmdletBinding(DefaultParameterSetName='Objects')]
    param (
	    [Parameter(Position=0, Mandatory, ParameterSetName='Objects')]
        [System.Collections.Generic.List[PSObject]] $Logs,

        [Parameter(Mandatory, ParameterSetName='Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [boolean] $IpInfo = $true,
        [boolean] $Open = $true,
        [switch] $Test
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
        $RawDateProperty = 'CreatedDateTime'
        $DateColumnHeader = 'DateTime'

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        # $Red = @{ ForegroundColor = 'Red' }
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
                $ErrorParams = @{
                    Category    = 'ReadError'
                    Message     = "Error importing from ${XmlPath}."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }
        }

        #region Metadata
        if ($Logs[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Logs[0]
            $Logs.RemoveAt(0)

            # $UserEmail = $Metadata.UserEmail
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
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
        # if allusers, use domain as username
        if ( $UserName -eq 'AllUsers' ) {
            $UserName = $DomainName
        }
        # build title
        if ( $FileNamePrefix -eq 'SignInLogs' ) {
            $WorksheetTitle = "Interactive sign-in logs for ${UserName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."
        }
        elseif ( $FileNamePrefix -eq 'NonInteractiveLogs' ) {
            $WorksheetTitle = "Non-Interactive sign-in logs for ${UserName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."
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
            # collect ip addresses
            if ($IpInfo) {
                if ($Log.IpAddress) {
                    try {
                        $IpObject = [System.Net.IPAddress]$Log.IpAddress
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

            # start timer for ip query
            if ($Script:Test) {
                $TestText = "Querying ip info"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            # query information for all IP addresses
            $env:PYTHONUTF8 = '1'
            & ip_info --apis bulk --output_format none --ip_addresses $IpInfoAddresses
            if ($LASTEXITCODE -ne 0) {
                Write-Host @Red "${Function}: ip_info query failed." | Out-Host
            }

            # end timer for ip query
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

        #region ROW LOOP

        if ($Script:Test) {
            $TestText = "Row loop"
            $TimerStart = $Stopwatch.Elapsed
            Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
        }
    
        $RowCount = ($Logs | Measure-Object).Count
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {  
        
            $Log = $Logs[$i]

            # Raw
            $Raw = $Log | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($Log.$RawDateProperty) {
                $DateTime = $Log.$RawDateProperty.ToLocalTime()
            }

            # IpAddress
            $IpText = if ($IpInfoTable -and $IpInfoTable.ContainsKey($Log.IpAddress)) {
                $IpInfoTable[$Log.IpAddress]
            }
            else {
                $Log.IpAddress
            }
            
            # application display name / resource id
            if ( $Log.AppDisplayName ) {
                $AppDisplayName = $Log.AppDisplayName
            }
            else {
                $AppDisplayName = $Log.ResourceId
            }

            # compress trust
            $Trust = Convert-TrustType -TrustType $Log.DeviceDetail.TrustType

            # add to list
            [void]$Rows.Add([PSCustomObject]@{
                Raw = $Raw
                $DateColumnHeader = $DateTime
                UserPrincipalName = $Log.UserPrincipalName
                Error = ConvertTo-HumanErrorDescription -ErrorCode $Log.Status.ErrorCode
                IpAddress = $IpText
                City = $Log.Location.City
                State = $Log.Location.State
                Co = $Log.Location.CountryOrRegion
                Application = $AppDisplayName
                Browser = $Log.DeviceDetail.Browser
                OS = $Log.DeviceDetail.OperatingSystem
                Trust = $Trust
                UserAgent = $Log.UserAgent
                Session = $Log.CorrelationId
                Token = $Log.UniqueTokenIdentifier
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
            Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $ApplicationColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'Application'}).Id | Convert-DecimalToExcelColumn
        $UserAgentColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'UserAgent'}).Id | Convert-DecimalToExcelColumn

        #region CELL COLORING

        # ip addresses
        Add-IpAddressConditionalFormatting -Worksheet $WorkSheet -ColumnName 'IpAddress'

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

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Raw' } ).Id 
        $Worksheet.Column($Column).Width = 8

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $DateColumnHeader } ).Id
        $Worksheet.Column($Column).Width = 26

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'UserPrincipalName' } ).Id 
        $Worksheet.Column($Column).Width = 30

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Error' } ).Id 
        $Worksheet.Column($Column).Width = 25
        
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'IpAddress' } ).Id
        $Worksheet.Column($Column).Width = 20

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'City' } ).Id
        $Worksheet.Column($Column).Width = 10

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'State' } ).Id
        $Worksheet.Column($Column).Width = 10

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Co' } ).Id
        $Worksheet.Column($Column).Width = 6

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Application' } ).Id
        $Worksheet.Column($Column).Width = 25

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Browser' } ).Id
        $Worksheet.Column($Column).Width = 20

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'OS' } ).Id
        $Worksheet.Column($Column).Width = 12

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Trust' } ).Id
        $Worksheet.Column($Column).Width = 12

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'UserAgent' } ).Id
        $Worksheet.Column($Column).Width = 150

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Session' } ).Id
        $Worksheet.Column($Column).Width = 10

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Token' } ).Id
        $Worksheet.Column($Column).Width = 10

        #region FORMATTING

        # set date format 
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-Format @FmtParams

        # set text wrapping on ip address column
        $WrapParams = @{
            Worksheet = $Worksheet
            Range = "${IpAddressColumn}:${IpAddressColumn}"
            WrapText = $true
        }
        Set-Format @WrapParams

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
        Set-Format @BorderParams

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
        Write-Host @Blue "Exporting to: ${ExcelOutputPath}"
        if ($Open) {
            Write-Host @Blue "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}