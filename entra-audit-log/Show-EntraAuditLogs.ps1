function Show-EntraAuditLogs {
    <#
	.SYNOPSIS
    Shows Entra audit logs in terminal, or saves as an excel spreadsheet.
	
	.NOTES
	Version: 1.2.1
    1.2.1 - Updates to use new get-graphobject functions.
    1.2.0 - Many small updates to standardize across IR functions. Updated to readable date format.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [string] $XmlPath,

        [string] $TableStyle = 'Dark8',
        [boolean] $Open = $true
    )

    begin {

        #region BEGIN
        
        # get file path
        if ( $XmlPath ) {

            $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
            $Logs = Import-Clixml -Path $ResolvedXmlPath
        }
        else {

            # run import-logs to get file name
            $ImportParams = @{
                Pattern    = "^EntraAuditLogs_Raw_.*\.xml$"
                ReturnPath = $true
            }
            $ResolvedXmlPath = Import-LogFile @ImportParams

            # use path to import logs
            $Logs = Import-Clixml -Path $ResolvedXmlPath
        }

        #region CONSTANTS

        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $WorksheetName = 'EntraAudit'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDatePattern = "\d{2}-\d{2}-\d{2}_\d{2}-\d{2}"
        $TitleDateFormat = "M/d/yy h:mmtt"
        $Groups = Request-GraphGroups
        $Roles = Request-DirectoryRoles
        $RoleTemplates = Request-DirectoryRoleTemplates
        $ServicePrincipals = Request-GraphServicePrincipals
        $Users = Request-GraphUsers

        # event date formatting
        $RawDateProperty = 'ActivityDateTime'
        $DateColumnHeader = 'DateTime'
        $DisplayProperties = @(
            'Raw'
            $DateColumnHeader
            'OperationType'
            'ActivityDisplayName'
            'InitiatedBy'
            'InitiatedByIp'
            'Target'
            'ModifiedProperties'
            'Details'
            'Result'
            'ResultReason'
        )

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }

        # import AppOwnerOrganizationId information
        $CsvPath = Join-Path -Path $ModuleRoot -ChildPath 'data\AppOwnerOrganizationId.csv'
        if ( Test-Path -Path $CsvPath ) {
            $AppOwnerTable = Import-Csv -Path $CsvPath
        }
        else {
            throw "Unable to find: ${CsvPath}. Exiting."
        }

        # build new file name out of old one
        $OldFileName = Split-Path -Path $ResolvedXmlPath -Leaf
        $SplitFileName = $OldFileName -split '_'
        $SplitFileName = $SplitFileName | Where-Object { $_ -ne 'Raw' }
        $UserString = $SplitFileName[3]
        $SplitFileName = $SplitFileName -replace '\.xml', '.xlsx'
        $ExcelOutputPath = $SplitFileName -join '_'

        ### build worksheet title
        # get number of days
        $ExcelOutputPath -match "(\d{1,3})Days" | Out-Null
        $Days = $Matches[1]
        # get date range
        $QueryDateString = $ExcelOutputPath | Select-String -Pattern $FileNameDatePattern -AllMatches | ForEach-Object { $_.Matches.Value }
        $ParsedDate = [DateTime]::ParseExact( $QueryDateString, $FileNameDateFormat, $null )
        $StartString = $ParsedDate.AddDays([int]$Days * -1).ToString( $TitleDateFormat ).ToLower()
        $EndString = $ParsedDate.ToString( $TitleDateFormat ).ToLower()
        # get username
        if ( $UserString -eq 'AllUsers' ) {
            # if all users, use domain as username
            $UserString = $SplitFileName[2]
        }
        # build title
        $WorksheetTitle = "Entra audit logs for ${UserString}. Covers ${Days} days, ${StartString} to ${EndString}."
    }

    process {

        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
     
        # process each log
        for ($i = 0; $i -lt ($Logs | Measure-Object).Count; $i++) {  
        
            # variables
            $Target = $null
            $TargetString = $null
            $TargetStrings = [System.Collections.Generic.list[string]]::new()
            $AllTargets = $null
            $ModifiedStrings = [System.Collections.Generic.list[string]]::new()
            $InitiatedByStrings = [System.Collections.Generic.list[string]]::new()
            $DetailsString = $null
            $DetailStrings = [System.Collections.Generic.list[string]]::new()

            $Log = $Logs[$i]
            $Row = [PSCustomObject]@{}

            # Raw
            $Raw = $Log | ConvertTo-Json -Depth 10
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Raw'
                Value      = $Raw
            }
            $Row | Add-Member @AddParams

            # DateTime
            $DateTime = $null
            if ($Log.$RawDateProperty) {
                $DateTime = $Log.$RawDateProperty.ToLocalTime()
            }
            $AddParams = @{
                MemberType  = 'NoteProperty'
                Name        = $DateColumnHeader
                Value       = $DateTime
            }
            $Row | Add-Member @AddParams

            # operationtype
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'OperationType'
                Value      = $Log.OperationType
            }
            $Row | Add-Member @AddParams

            # category
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Category'
                Value      = $Log.Category
            }
            $Row | Add-Member @AddParams

            # ActivityDisplayName
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ActivityDisplayName'
                Value      = $Log.ActivityDisplayName
            }
            $Row | Add-Member @AddParams
                
            ### initiated by
            # if user, get perferred property
            if ( $Log.InitiatedBy.User.UserPrincipalName ) {
                $InitiatedByString = $Log.InitiatedBy.User.UserPrincipalName
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            elseif ( $Log.InitiatedBy.User.Id ) {
                $User = $Users | Where-Object { $_.Id -eq $Log.InitiatedBy.User.Id }
                if ( $User ) {
                    $InitiatedByString = $User.UserPrincipalName
                }
                else {
                    $InitiatedByString = $Log.InitiatedBy.User.Id
                }
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            # if app, get preferred property
            if ( $Log.InitiatedBy.App.DisplayName ) {
                $InitiatedByString = $Log.InitiatedBy.App.DisplayName
                $InitiatedByStrings.Add( "App: ${InitiatedByString}" )

            }
            elseif ( $Log.InitiatedBy.App.ServicePrincipalId ) {
                $ServicePrincipal = $ServicePrincipals | Where-Object { $_.Id -eq $Log.InitiatedBy.App.ServicePrincipalId }
                if ( $ServicePrincipal ) {
                    $InitiatedByString = $ServicePrincipal.DisplayName
                }
                else {
                    $InitiatedByString = $Log.InitiatedBy.App.ServicePrincipalId
                }
                $InitiatedByStrings.Add( "App: ${InitiatedByString}" )
            }

            # join strings if multiple
            $AllInitiatedByStrings = $InitiatedByStrings -join ', '
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'InitiatedBy'
                Value      = $AllInitiatedByStrings
            }
            $Row | Add-Member @AddParams

            # initiatedby user ip
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'InitiatedByIp'
                Value      = $Log.InitiatedBy.User.IPAddress
            }
            $Row | Add-Member @AddParams

            # get target information
            foreach ( $Resource in $Log.TargetResources ) {

                # resource name
                $ResourceType = $Resource.Type
                if ( $ResourceType ) {
                    switch ( $ResourceType ) {
                        'Directory' {
                            $Target = $Resource.DisplayName
                        }
                        'Group' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $Group = $Groups | Where-Object { $_.Id -eq $Resource.Id } 
                                $Target = $Group.DisplayName
                            }
                        }
                        'N/A' {
                            $Target = $Resource.Id
                        }
                        'Other' {
                            $Target = $Resource.DisplayName
                        }
                        'Policy' {
                            $Target = $Resource.DisplayName
                        }
                        'Request' {
                            $Target = $Resource.Id
                        }
                        'Role' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $Role = $Roles | Where-Object { $_.Id -eq $Resource.Id }
                                if ( -not $Role ) {
                                    $Role = $RoleTemplates | Where-Object { $_.Id -eq $Resource.Id }
                                }
                                $Target = $Role.DisplayName
                            }
                        }
                        'ServicePrincipal' {
                            if ( $Resource.DisplayName ) {
                                $Target = $Resource.DisplayName
                            }
                            else {
                                $ServicePrincipal = $ServicePrincipals | Where-Object { $_.Id -eq $Resource.Id } 
                                $Target = $ServicePrincipal.DisplayName
                            }
                        }
                        'User' {
                            if ( $Resource.UserPrincipalName ) {
                                $Target = $Resource.UserPrincipalName
                            }
                            else {
                                $User = $Users | Where-Object { $_.Id -eq $Resource.Id } 
                                $Target = $User.UserPrincipalName
                            }
                        }
                        default {
                            $Target = $Resource.Id
                        }
                    }
                    $TargetString = "${ResourceType}: ${Target}"
                    $TargetStrings.Add( $TargetString )
                }

                # modified properties
                if ( $Resource.ModifiedProperties ) {
                    $ModifiedStrings.Add( "Target: ${TargetString}" )
                    foreach ( $Property in $Resource.ModifiedProperties ) {
                        $Name = $null
                        $Old = $null
                        $New = $null
                        $Name = $Property.DisplayName
                        $Old = $Property.OldValue
                        $New = $Property.NewValue
                        $ModifiedString = "Property: '${Name}', Old: '${Old}', New: '${New}'"
                        $ModifiedStrings.Add( $ModifiedString )
                    }
                }
            }
            # add target info
            $TargetStrings = $TargetStrings | Sort-Object -Unique
            $AllTargets = $TargetStrings -join ', '
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Target'
                Value      = $AllTargets
            }
            $Row | Add-Member @AddParams
            # add modified properties
            $AllModifiedStrings = $ModifiedStrings -join "`n"
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ModifiedProperties'
                Value      = $AllModifiedStrings
            }
            $Row | Add-Member @AddParams

            # AdditionalDetails
            foreach ( $Detail in $Log.AdditionalDetails ) {

                # variables
                $Key = $Detail.Key
                $AppId = $null
                $Value = $null

                # translate ids into human names
                switch ( $Key ) {
                    'AppId' {
                        $AppId = $Detail.Value
                        $Value = ( $ServicePrincipals | Where-Object { $_.AppId -eq $AppId } ).DisplayName
                    }
                    'AppOwnerOrganizationId' {
                        # if one of the common microsoft ids, change to microsoft
                        $AppOwnerOrganizationId = $Detail.Value
                        $CsvRow = $AppOwnerTable | Where-Object { $_.AppOwnerOrganizationId -eq $AppOwnerOrganizationId }
                        if ( $CsvRow ) {
                            $Value = $CsvRow.DisplayName
                        }
                        # otherwise, leave as id number
                        else {
                            $Value = $Detail.Value
                        }
                    }
                    default {
                        $Value = $Detail.Value
                    }
                }
                
                # add string to list of strings
                $DetailStrings.Add( "${Key}: ${Value}" )
            }
            # join list into one string
            $DetailsString = $DetailStrings -join ', '
            # add final string to object
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Details'
                Value      = $DetailsString
            }
            $Row | Add-Member @AddParams

            # Result
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Result'
                Value      = $Log.Result
            }
            $Row | Add-Member @AddParams

            # ResultReason
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ResultReason'
                Value      = $Log.ResultReason
            }
            $Row | Add-Member @AddParams

            # add to list
            $Rows.Add($Row)
        }

        # select just relevant properties
        $OutputTable = $OutputTable | Select-Object $DisplayProperties

        # export spreadsheet
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
        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        #region CELL COLORING

        # if cell matches EXACTLY, make background RED
        $Strings = @(
            'Add app role assignment grant to user'
            'Add member to role'
            'Change password (self-service)'
            'Change user password'
            'User registered all required security info'
            'User registered security info'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                RuleType        = 'Equal'
                ConditionValue  = $String
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }
        
        # if cell matches EXACTLY, make background YELLOW
        $Strings = @(
            'User started security info registration'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                RuleType        = 'Equal'
                ConditionValue  = $String
                BackgroundColor = 'LightGoldenRodYellow'
            }
            Add-ConditionalFormatting @CFParams
        }
        
        # if cell CONTAINS text anywhere, make background BLUE
        $Strings = @(
            'AppOwnerOrganizationId: Microsoft'
        )
        foreach ( $String in $Strings ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
                RuleType        = 'ContainsText'
                ConditionValue  = $String
                BackgroundColor = 'LightBlue'
            }
            Add-ConditionalFormatting @CFParams
        }

        #region COLUMN WIDTH

        # resize Raw column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Raw' } ).Id 
        $Worksheet.Column($Column).Width = 8

        # resize DateTime column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $DateColumnHeader } ).Id 
        $Worksheet.Column($Column).Width = 26

        # resize ActivityDisplayName column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'ActivityDisplayName' } ).Id
        $Worksheet.Column($Column).Width = 25

        # resize InitiatedBy column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'InitiatedBy' } ).Id
        $Worksheet.Column($Column).Width = 45

        # resize InitiatedByIp column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'InitiatedByIp' } ).Id
        $Worksheet.Column($Column).Width = 17
                
        # resize Target column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Target' } ).Id
        $Worksheet.Column($Column).Width = 45

        # resize ModifiedProperties column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'ModifiedProperties' } ).Id
        $Worksheet.Column($Column).Width = 25

        # resize Details column
        $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Details' } ).Id
        $Worksheet.Column($Column).Width = 25

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
            FontName  = 'Consolas'
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

        #region OUTPUT
                    
        # save and close
        Write-Host @Blue "Exporting to: ${ExcelOutputPath}"
        if ( $Open ) {
            Write-Host @Blue "Opening Excel."
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}