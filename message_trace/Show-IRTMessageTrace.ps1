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
        [Alias( 'Message' )]
        [System.Collections.Generic.List[PSObject]] $Messages,

        [Parameter(Position = 0, Mandatory, ParameterSetName = 'Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,

        [switch] $Test
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        $ParameterSet = $PSCmdlet.ParameterSetName
        $TitleDateFormat = "M/d/yy h:mmtt"
        $RawDateProperty = 'Received'
        $DateColumnHeader = 'DateTime'

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Green = @{ ForegroundColor = 'Green' }
        $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
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
                [System.Collections.Generic.List[PSObject]]$Messages = Import-CliXml -Path $ResolvedXmlPath
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

        # import metadata
        if ($Messages[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Messages[0]
            $Messages.RemoveAt(0)

            $UserEmails = $Metadata.UserEmails
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
            $FileNamePrefix = $Metadata.FileNamePrefix
        }
        else {
            Write-Error "${Function}: No Metadata found."
        }

        # exit if no messages found
        if (($Messages | Measure-Object).Count -eq 0) {
            Write-Host @Red "${Function}: No messages found. Exiting"
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
        if (($Messages | Measure-Object).Count -eq 0) {
            Write-Host @Red "${Function}: No messages. Exiting."
        }

        #region ROW LOOP

        if ($Script:Test) {
            $TestText = "Row loop"
            $TimerStart = $Stopwatch.Elapsed
            Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
        }

        $RowCount = $Messages.Count
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new($RowCount)
        for ($i = 0; $i -lt $RowCount; $i++) {

            $Message = $Messages[$i]

            # Raw
            $Raw = $Message | ConvertTo-Json -Depth 10

            # Date/Time
            $DateTime = $null
            if ($Message.$RawDateProperty) {
                $DateTime = $Message.$RawDateProperty.ToLocalTime()
            }

            $Rows.Add([pscustomobject]@{
                Raw               = $Raw
                $DateColumnHeader = $DateTime
                Status            = $Message.Status
                SenderAddress     = $Message.SenderAddress
                RecipientAddress  = $Message.RecipientAddress
                Subject           = $Message.Subject
                FromIP            = $Message.FromIP
                ToIP              = $Message.ToIP
                MessageTraceId    = $Message.MessageTraceId
                MessageId         = $Message.MessageId
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
            Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
        }

        #region EXPORT EXCEL
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
            $_
            Write-Host @Red "Error while opening Excel document."
            if ( Get-YesNo "Try again?" ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    $_
                    Write-Host @Red "Error while opening Excel document. Exiting."
                    return
                }
            }
            else {
                return
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

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Raw' } ).Id 
        $Worksheet.Column($Column).Width = 8

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $DateColumnHeader } ).Id 
        $Worksheet.Column($Column).Width = 26

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Status' } ).Id 
        $Worksheet.Column($Column).Width = 15

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'SenderAddress' } ).Id 
        $Worksheet.Column($Column).Width = 30

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'RecipientAddress' } ).Id 
        $Worksheet.Column($Column).Width = 30

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Subject' } ).Id 
        $Worksheet.Column($Column).Width = 100

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'FromIp' } ).Id 
        $Worksheet.Column($Column).Width = 20

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'ToIp' } ).Id 
        $Worksheet.Column($Column).Width = 20

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'MessageTraceId' } ).Id
        $Worksheet.Column($Column).Width = 20

        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'MessageTraceId' } ).Id
        $Worksheet.Column($Column).Width = 200

        #region FORMATTING

        # set date format 
        $FmtParams = @{
            Worksheet = $Worksheet
            Range = "B:B"
            NumberFormat  = 'm/d/yyyy h:mm:ss AM/PM'
        }
        Set-Format @FmtParams

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
        Set-Format @BorderParams

        #region OUTPUT

        # save and close
        Write-Host @Blue "${Function}: Exporting to: ${ExcelOutputPath}"
        $Workbook | Close-ExcelPackage -Show

        if ($Script:Test) {
            $ElapsedString = ($StopWatch.Elapsed).ToString('mm\:ss')
            Write-Host @Yellow "${Function} took ${ElapsedString}" | Out-Host
        }
    }
}