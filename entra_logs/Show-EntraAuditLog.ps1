function Show-EntraAuditLog {
    <#
	.SYNOPSIS
    Shows Entra audit logs in terminal, or saves as an excel spreadsheet.

	.NOTES
	Version: 1.2.1
    1.2.1 - Updates to use new get-graphobject functions.
    1.2.0 - Many small updates to standardize across IR functions. Updated to readable date format.
	#>
    [CmdletBinding(DefaultParameterSetName='Objects')]
    param (
        [Parameter(Position=0, Mandatory, ParameterSetName='Objects')]
        [Alias('Logs')]
        [System.Collections.Generic.List[PSObject]] $Log,

        [Parameter(Mandatory, ParameterSetName='Xml')]
        [string] $XmlPath,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $IpInfo = $Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [switch] $Cached
    )

    begin {
        # get logs from file if xml path used
        if ( $XmlPath ) {

            $ResolvedXmlPath = Resolve-ScriptPath -Path $XmlPath -File -FileExtension 'xml'
            [System.Collections.Generic.List[PSObject]]$Log = Import-Clixml -Path $ResolvedXmlPath
        }
        elseif ( -not $Log ) {

            # run import-logs to get file name
            $ImportParams = @{
                Pattern    = "^EntraAuditLogs_Raw_.*\.xml$"
                ReturnPath = $true
            }
            $ResolvedXmlPath = Import-LogFile @ImportParams

            # use path to import logs
            [System.Collections.Generic.List[PSObject]]$Log = Import-Clixml -Path $ResolvedXmlPath
        }

        #region METADATA
        if ($Log[0].Metadata) {

            # remove metadata from beginning of list
            $Metadata = $Log[0]
            $Log.RemoveAt(0)

            # $UserEmail = $Metadata.UserEmail
            $UserName = $Metadata.UserName
            $StartDate = $Metadata.StartDate
            $EndDate = $Metadata.EndDate
            $Days = $Metadata.Days
            $DomainName = $Metadata.DomainName
            $FileNamePrefix = $Metadata.FileNamePrefix
        }
        else {
            Write-IRT "No Metadata found." -Level Error -FunctionName $Function
        }

        # build file name
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = $EndDate.ToLocalTime().ToString($FileNameDateFormat)
        $ExcelOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileDateString}.xlsx"

        # build worksheet title
        $TitleDateFormat = "M/d/yy h:mmtt"
        $TitleStartDate = $StartDate.ToLocalTime().ToString($TitleDateFormat)
        $TitleEndDate = $EndDate.ToLocalTime().ToString($TitleDateFormat)
        # if allusers, use domain as username
        if ( $UserName -eq 'AllUsers' ) {
            $UserName = $DomainName
        }
        $WorksheetTitle = "Entra audit logs for ${UserName}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

        #region CONSTANTS

        $Function = $MyInvocation.MyCommand.Name
        # $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $WorksheetName = 'EntraAudit'
        $Groups = Request-GraphGroup -Cached:$Cached
        $Roles = Request-DirectoryRole -Cached:$Cached
        $RoleTemplates = Request-DirectoryRoleTemplate -Cached:$Cached
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
        $Users = Request-GraphUser -Cached:$Cached

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

    }

    process {
        $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()

        # process each log
        for ($i = 0; $i -lt ($Log | Measure-Object).Count; $i++) {

            # variables
            $Target = $null
            $TargetString = $null
            $TargetStrings = [System.Collections.Generic.list[string]]::new()
            $AllTargets = $null
            $ModifiedStrings = [System.Collections.Generic.list[string]]::new()
            $InitiatedByStrings = [System.Collections.Generic.list[string]]::new()
            $DetailsString = $null
            $DetailStrings = [System.Collections.Generic.list[string]]::new()

            $LogEntry = $Log[$i]
            $Row = [PSCustomObject]@{}

            # Raw
            $Raw = $LogEntry | ConvertTo-Json -Depth 10
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Raw'
                Value      = $Raw
            }
            $Row | Add-Member @AddParams

            # DateTime
            $DateTime = $null
            if ($LogEntry.$RawDateProperty) {
                $DateTime = $LogEntry.$RawDateProperty.ToLocalTime()
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
                Value      = $LogEntry.OperationType
            }
            $Row | Add-Member @AddParams

            # category
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'Category'
                Value      = $LogEntry.Category
            }
            $Row | Add-Member @AddParams

            # ActivityDisplayName
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ActivityDisplayName'
                Value      = $LogEntry.ActivityDisplayName
            }
            $Row | Add-Member @AddParams

            ### initiated by
            # if user, get perferred property
            if ( $LogEntry.InitiatedBy.User.UserPrincipalName ) {
                $InitiatedByString = $LogEntry.InitiatedBy.User.UserPrincipalName
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            elseif ( $LogEntry.InitiatedBy.User.Id ) {
                $User = $Users | Where-Object { $_.Id -eq $LogEntry.InitiatedBy.User.Id }
                if ( $User ) {
                    $InitiatedByString = $User.UserPrincipalName
                }
                else {
                    $InitiatedByString = $LogEntry.InitiatedBy.User.Id
                }
                $InitiatedByStrings.Add( "User: ${InitiatedByString}" )

            }
            # if app, get preferred property
            if ( $LogEntry.InitiatedBy.App.DisplayName ) {
                $InitiatedByString = $LogEntry.InitiatedBy.App.DisplayName
                $InitiatedByStrings.Add( "App: ${InitiatedByString}" )

            }
            elseif ( $LogEntry.InitiatedBy.App.ServicePrincipalId ) {
                $ServicePrincipal = $ServicePrincipals | Where-Object { $_.Id -eq $LogEntry.InitiatedBy.App.ServicePrincipalId }
                if ( $ServicePrincipal ) {
                    $InitiatedByString = $ServicePrincipal.DisplayName
                }
                else {
                    $InitiatedByString = $LogEntry.InitiatedBy.App.ServicePrincipalId
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
                Value      = $LogEntry.InitiatedBy.User.IPAddress
            }
            $Row | Add-Member @AddParams

            # get target information
            foreach ( $Resource in $LogEntry.TargetResources ) {

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
            foreach ( $Detail in $LogEntry.AdditionalDetails ) {

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
                        $AppOwnerOrganizationId = $Detail.Value
                        try {
                            $TenantInfo = Get-IRTTenantInfo -TenantId $AppOwnerOrganizationId
                            if ( $TenantInfo.DisplayName ) {
                                $Value = $TenantInfo.DisplayName
                            }
                            else {
                                $Value = $Detail.Value
                            }
                        }
                        catch {
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
                Value      = $LogEntry.Result
            }
            $Row | Add-Member @AddParams

            # ResultReason
            $AddParams = @{
                MemberType = 'NoteProperty'
                Name       = 'ResultReason'
                Value      = $LogEntry.ResultReason
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

        if ($IpInfo) { Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'InitiatedByIp' }
        $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
        $SheetStartRow = $WorkSheet.Dimension.Start.Row
        $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
        $EndRow = $WorkSheet.Dimension.End.Row

        if ($Worksheet.Tables.Count -gt 0) {

        $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
        $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row

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

        $ColumnWidths = @{
            'Raw'                = 8
            $DateColumnHeader    = 26
            'ActivityDisplayName' = 25
            'InitiatedBy'        = 45
            'InitiatedByIp'      = 17
            'Target'             = 45
            'ModifiedProperties' = 25
            'Details'            = 25
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

        } # end if ($Worksheet.Tables.Count -gt 0)

        #region OUTPUT

        # save and close
        Write-IRT "Exporting to: ${ExcelOutputPath}" -FunctionName $Function
        if ( $Open ) {
            Write-IRT "Opening Excel." -FunctionName $Function
            $Workbook | Close-ExcelPackage -Show
        }
        else {
            $Workbook | Close-ExcelPackage
        }
    }
}
