function Show-IRTMessageTrace {
    <#
	.SYNOPSIS
	Processes message trace data and creates spreadsheet.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding( DefaultParameterSetName = 'Objects' )]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ParameterSetName = 'Objects')]
        [Alias('Messages')]
        [System.Collections.Generic.List[PSObject]] $Message,

        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $IpInfo = $Global:IRT_Config.IpInfoAvailable
    )

    begin {
        $ParameterSet = $PSCmdlet.ParameterSetName
        $TitleDateFormat = "M/d/yy h:mmtt"
        $RawDateProperty = 'Received'
        $DateColumnHeader = 'DateTime'

        # import from xml
        if ($ParameterSet -eq 'Xml') {
            if ($Script:Test) {
                $TestText = "Importing from Xml"
                $TimerStart = $Stopwatch.Elapsed
            }

            try {
                $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
                [System.Collections.Generic.List[PSObject]]$Message = Import-CliXml -Path $ResolvedXmlPath
            }
            catch {
                $_
                Write-IRT "Error importing from ${XmlPath}." -Level Error
                return
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
            }
        }

        # import metadata
        if ($Message[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Message[0]
            $Message.RemoveAt(0)

            $UserEmails = $Metadata.UserEmails
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
            $FileNamePrefix = $Metadata.FileNamePrefix
        }
        else {
            Write-IRT "No Metadata found." -Level Error
        }

        # exit if no messages found
        if (($Message | Measure-Object).Count -eq 0) {
            Write-IRT "No messages found. Exiting" -Level Error
            return
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $StartString = $StartDate.ToString($TitleDateFormat).ToLower()
        $EndString = $EndDate.ToString($TitleDateFormat).ToLower()
        if ($null -eq $Username) {
            $WorksheetTitle = "Message Trace for ${DomainName}. Covers ${Days} days, from ${StartString} to ${EndString}."
        }
        else {
            $WorksheetTitle = "Message Trace for ${Username}. Covers ${Days} days, from ${StartString} to ${EndString}."
        }
    }

    process {
        # exit if no messages
        if (($Message | Measure-Object).Count -eq 0) {
            Write-IRT "No messages. Exiting." -Level Error
        }

        #region ROW LOOP

        if ($Script:Test) {
            $TestText = "Row loop"
            $TimerStart = $Stopwatch.Elapsed
        }

        $RowCount = $Message.Count
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $m = $Message[$i]

            # Raw
            $Raw = $m | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($m.$RawDateProperty) {
                $DateTime = $m.$RawDateProperty.ToLocalTime()
            }

            $Rows.Add([pscustomobject]@{
                Raw               = $Raw
                $DateColumnHeader = $DateTime
                Status            = $m.Status
                SenderAddress     = $m.SenderAddress
                RecipientAddress  = $m.RecipientAddress
                Subject           = $m.Subject
                FromIP            = $m.FromIP
                ToIP              = $m.ToIP
                MessageTraceId    = $m.MessageTraceId
                MessageId         = $m.MessageId
            })

            if ($Script:Test -and ($i % 1000 -eq 0)) {
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
            Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
        }

        #region EXPORT EXCEL
        if ($Script:Test) {
            $TestText = "Exporting to excel"
            $TimerStart = $Stopwatch.Elapsed
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
            $_
            Write-IRT "Error while opening Excel document." -Level Error
            if ( Get-YesNo "Try again?" ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    $_
                    Write-IRT "Error while opening Excel document. Exiting." -Level Error
                    return
                }
            }
            else {
                return
            }
        }
        $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

        if ($IpInfo) { Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'FromIP', 'ToIP' }

        if ($Script:Test) {
            $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
            Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
        }

        # get table ranges
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $TableStartColumn = ($Worksheet.Tables.Address | Select-Object -First 1).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ($Worksheet.Tables | Select-Object -First 1).Address.Start.Row + 1
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        $SenderColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'SenderAddress'}).Id | Convert-DecimalToExcelColumn
        $RecipientColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq 'RecipientAddress'}).Id | Convert-DecimalToExcelColumn

        #region BOLD OTHER EMAIL

        if ($UserEmails) {
            # # helper: make "=AND(LEN($A2)>0, $A2<>\"me1\", $A2<>\"me2\", ...)" for a column's anchor cell
            # function New-CfNotMeFormula {
            #     param([Parameter(Mandatory)][string]$ColumnLetter,
            #         [Parameter(Mandatory)][int]$StartRow)

            #     # anchor column absolute, row relative: $A2
            #     $anchor = "`$${ColumnLetter}$StartRow"

            #     # comparisons: $A2<> "alias"
            #     $comparisons = $UserEmails.ForEach({
            #         '{0}<>""{1}""' -f $anchor, ($_ -replace '"','""')
            #     })

            #     # skip blanks, and only bold when value is not any of my addresses
            #     return '=AND(LEN({0})>0,{1})' -f $anchor, ($comparisons -join ',')
            # }

            # # sender column rule
            # $FormulaSender = New-CfNotMeFormula -ColumnLetter $SenderColumn -StartRow $TableStartRow
            # $CfParamsSender = @{
            #     WorkSheet      = $Worksheet
            #     Address        = "${SenderColumn}${TableStartRow}:${SenderColumn}${EndRow}"
            #     RuleType       = 'Expression'
            #     ConditionValue = $FormulaSender
            #     Bold           = $true
            # }
            # Add-ConditionalFormatting @CfParamsSender

            # # recipient column rule
            # $FormulaRecipient = New-CfNotMeFormula -ColumnLetter $RecipientColumn -StartRow $TableStartRow
            # $CfParamsRecipient = @{
            #     WorkSheet      = $Worksheet
            #     Address        = "${RecipientColumn}${TableStartRow}:${RecipientColumn}${EndRow}"
            #     RuleType       = 'Expression'
            #     ConditionValue = $FormulaRecipient
            #     Bold           = $true
            # }
            # Add-ConditionalFormatting @CfParamsRecipient
        }

        #region SAME TO/FROM

        $CfParams = @{
            WorkSheet        = $Worksheet
            Address          = "${SenderColumn}${TableStartRow}:${RecipientColumn}${EndRow}"
            RuleType         = 'Expression'
            ConditionValue   = "=`$${SenderColumn}${TableStartRow}=`$${RecipientColumn}${TableStartRow}"
            BackgroundColor  = 'LightYellow'
        }
        Add-ConditionalFormatting @CfParams

        #region COLUMN WIDTH

        $ColumnWidths = @{
            'Raw'              = 8
            $DateColumnHeader  = 26
            'Status'           = 15
            'SenderAddress'    = 30
            'RecipientAddress' = 30
            'Subject'          = 100
            'FromIp'           = 20
            'ToIp'             = 20
            'MessageTraceId'   = 200
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

        # set font and size
        $SetParams = @{
            Worksheet = $Worksheet
            Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
            FontName  = $Font
        }
        Set-ExcelRange @SetParams

        # add left side border
        $BorderParams = @{
            Worksheet = $Worksheet
            Range = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            BorderLeft = 'Thin'
            BorderColor = 'Black'
        }
        Set-ExcelRange @BorderParams

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}"
        $Workbook | Close-ExcelPackage -Show
    }
}
