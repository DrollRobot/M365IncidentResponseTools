function Get-IRTInboxRule {
    <#
    .SYNOPSIS
    Retrieves and displays Exchange Online inbox rules for one or more users.

    .DESCRIPTION
    Fetches all inbox rules for each provided user via Exchange Online and exports them
    to a formatted Excel workbook. Each rule row includes its enabled state, name,
    description, and a pre-built deletion command for quick remediation.

    Disabled rules are highlighted in the Excel output. Falls back to
    $Global:IRT_UserObjects if no -UserObject is passed. Requires an active Exchange
    Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Get-IRTInboxRule
    Retrieves and exports inbox rules for the user in the global session.

    .EXAMPLE
    Get-IRTInboxRule -UserObject $User
    Retrieves inbox rules for a specific user.

    .OUTPUTS
    None. Results are exported to an Excel file and optionally displayed in the console.

    .NOTES
    Version: 1.1.6
    1.1.6 - Added column borders, raw json. Fixed bugs.
    1.1.5 - Added rule to highlight disabled rules.
    #>
    [Alias('InboxRule', 'InboxRules')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {
        Update-IRTToken -Service 'Exchange'
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

        # if user objects not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # get client domain name for file output
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
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
            Write-IRT "Getting Inbox rules for ${UserEmail}"
            $OutputTable = Get-InboxRule -Mailbox $UserEmail
            if ( @( $OutputTable ).Count -eq 0 ) {
                Write-IRT "No inbox rules found for ${UserEmail}." -Level Warn
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
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
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
                $Workbook = $OutputTable |
                    Select-Object $DisplayProperties |
                    Export-Excel @ExcelParams
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
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1
            #     ).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            $EnabledColumn = (
                $Worksheet.Tables[0].Columns |
                    Where-Object { $_.Name -eq 'Enabled' }
                ).Id | Convert-DecimalToExcelColumn
                $DescriptionColumn = (
                    $Worksheet.Tables[0].Columns |
                        Where-Object { $_.Name -eq 'Description' }
                    ).Id | Convert-DecimalToExcelColumn

                    #region CELL COLORING

                    # if enabled column is 'FALSE', make background blue
                    $EnabledRange = "${EnabledColumn}${TableStartRow}:${EnabledColumn}${EndRow}"
                    $CFParams = @{
                        Worksheet       = $WorkSheet
                        Address         = $EnabledRange
                        RuleType        = 'ContainsText'
                        ConditionValue  = 'FALSE'
                        BackgroundColor = 'LightBlue'
                    }
                    Add-ConditionalFormatting @CFParams

                    $DescRange = "${DescriptionColumn}${TableStartRow}" +
                    ":${DescriptionColumn}${EndRow}"

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
                            Address         = $DescRange
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
                            Address         = $DescRange
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
                        $Col = ($Worksheet.Tables[0].Columns |
                                Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # set text wrapping in description column
            $WrappingParams = @{
                Worksheet = $Worksheet
                Range     = $DescRange
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
            Set-ExcelRange @BorderParams

            #region OUTPUT

            # save and close
            Write-IRT "Exporting to: ${ExcelOutputPath}"
            if ( $Open ) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
