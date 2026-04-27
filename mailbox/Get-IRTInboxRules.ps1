New-Alias -Name 'InboxRule' -Value 'Get-IRTInboxRules' -Force
New-Alias -Name 'InboxRules' -Value 'Get-IRTInboxRules' -Force
New-Alias -Name 'Get-IRTInboxRule' -Value 'Get-IRTInboxRules' -Force

function Get-IRTInboxRules {
    <#
	.SYNOPSIS
	Downloads incoming and outgoing message trace for provided users, merges into one array, saves raw xml, then saves as excel spreadsheet.
	
	.NOTES
	Version: 1.1.6
    1.1.6 - Added column borders, raw json. Fixed bugs.
    1.1.5 - Added rule to highlight disabled rules.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Test
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName
        $WorksheetName = 'InboxRules'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = Get-Date -Format $FileNameDateFormat
        $EventDateFormat = 'MM/dd/yy hh:mm:sstt'
        $EventDateString = Get-Date -Format $EventDateFormat
        $DisplayProperties = @(
            'Raw'
            'Enabled'
            'Name'
            'Description'
            'DeleteCommand'
        )

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        

        # if user objects not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {
        
            # get from global variables
            $ScriptUserObjects = Get-IRTUserObjects
                        
            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }

        # verify connected to exchange
        try {
            [void](Get-AcceptedDomain)
        }
        catch {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # get client domain name for file output
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-Host @Red "${Function}: No mailbox for ${UserEmail}"
                continue
            }
            
            # get username
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # build file name
            $XmlOutputPath = "InboxRules_Raw_${DomainName}_${UserName}_${FileDateString}.xml"
            $ExcelOutputPath = "InboxRules_${DomainName}_${UserName}_${FileDateString}.xlsx"

            # build worksheet title
            $WorksheetTitle = "Inbox rules for ${UserEmail} as of ${EventDateString}"

            # get rules
            Write-Host @Blue "Getting Inbox rules for ${UserEmail}"
            $OutputTable = Get-InboxRule -Mailbox $UserEmail
            if ( @( $OutputTable ).Count -eq 0 ) {
                Write-Host @Red "No inbox rules found. Exiting."
                continue
            }

            #region ROW LOOP

            for ($i = 0; $i -lt $OutputTable.Count; $i++) {

                $Row = $OutputTable[$i]

                # Raw
                $Raw = $Row | ConvertTo-Json -Depth 10
                $AddParams = @{
                    MemberType = 'NoteProperty'
                    Name       = 'Raw'
                    Value      = $Raw
                }
                $Row | Add-Member @AddParams

                # DeleteCommand
                $Identity = $Row.Identity
                $DeleteCommand = "Remove-InboxRule -Identity '${Identity}'"
                $AddMemberParams = @{
                    MemberType  = 'NoteProperty'
                    Name        = 'DeleteCommand'
                    Value       = $DeleteCommand
                }
                $Row | Add-Member @AddMemberParams
            }

            # strip working table down to just desired properties
            $OutputTable = $OutputTable | Select-Object $DisplayProperties

            # export raw data
            if ($Xml) {
                Write-Host @Blue "Exporting raw data to: ${XmlOutputPath}"
                $RawOutputTable | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            #region EXPORT SHEET
            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorksheetName
                Title         = $WorksheetTitle
                TableStyle    = $TableStyle
                AutoSize      = $true
                FreezeTopRow  = $true
                Passthru      = $true
            }
            try {
                $Workbook = $OutputTable | Select-Object $DisplayProperties | Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to open new Excel document."
                if ( Get-YesNo "Try closing open files." ) {
                    try {
                        $Workbook = $OutputTable | Export-Excel @ExcelParams
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
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            $EnabledColumn = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Enabled' } ).Id | Convert-DecimalToExcelColumn
            $DescriptionColumn = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Description' } ).Id | Convert-DecimalToExcelColumn

            #region CELL COLORING

            # if enabled column is 'FALSE', make background blue
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${EnabledColumn}${TableStartRow}:${EnabledColumn}${EndRow}"
                RuleType        = 'ContainsText'
                ConditionValue  = 'FALSE'
                BackgroundColor = 'LightBlue'
            }
            Add-ConditionalFormatting @CFParams

            # if description column contains text, make background red
            $Strings = @(
                'phish'
                'spam'
                'compromise'
                'hack'
                'stolen'
                'Conversation History'
                'RSS Feeds'
            )
            foreach ( $String in $Strings ) {

                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${DescriptionColumn}${TableStartRow}:${DescriptionColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $String
                    BackgroundColor = 'LightPink'
                }
                Add-ConditionalFormatting @CFParams
            }

            # if description column CONTAINS text, make background BLUE
            $Strings = @(
                "move the message to folder 'Inbox'"
            )
            foreach ( $String in $Strings ) {
                $CFParams = @{
                    Worksheet       = $WorkSheet
                    Address         = "${DescriptionColumn}${TableStartRow}:${DescriptionColumn}${EndRow}"
                    RuleType        = 'ContainsText'
                    ConditionValue  = $String
                    BackgroundColor = 'LightBlue'
                }
                Add-ConditionalFormatting @CFParams
            }


            #region COLUMN WIDTH

            $ColumnWidths = @{
                'Raw' = 8
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # set text wrapping in description column
            $WrappingParams = @{
                Worksheet = $Worksheet
                Range     = "${DescriptionColumn}${TableStartRow}:${DescriptionColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @WrappingParams

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
            Write-Host @Blue "Exporting to: ${ExcelOutputPath}"
            if ( $Open ) {
                Write-Host "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}



