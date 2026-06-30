function Show-IRTEntraUserSignInLog {
    <#
	.SYNOPSIS
	Processes Sign in log .XML file into Excel spreadsheet.

	.NOTES
	Version: 1.4.0
    1.4.0 - SignInEventTypes is now shown by default (right after UserPrincipalName)
            so interactive and non-interactive sign-ins can be told apart in a mixed
            pull.
    1.3.0 - OriginalTransferMethod is now shown by default immediately after
            AuthenticationProtocol, and both columns are highlighted when a cell
            contains a device code value. AutonomousSystemNumber now sits right after
            IpAddress (still hidden by default).
    1.2.0 - Surfaced many more sign-in fields as columns (incl. AuthenticationProtocol);
            all non-curated columns are present but hidden by default.
    1.1.3 - Added timers/progress for testing.
	#>
    [CmdletBinding(DefaultParameterSetName = 'Objects')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'Objects')]
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

        # logs must come from either -Log or -XmlPath
        if (-not $Log) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = 'No logs provided. Use -Log or -XmlPath.'
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
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

            # flatten applied conditional access policies to "Name=Result; Name=Result"
            $CaPolicies = ($LogEntry.AppliedConditionalAccessPolicies | ForEach-Object {
                    "$($_.DisplayName)=$($_.Result)" }) -join '; '

            # add to list. PSCustomObject literal order = column order, so keep Raw first
            # (column A) and DateTime second (column B) - the date format step hardcodes B:B.
            # Columns after Token are present for reference but hidden by default (see
            # $ColumnMeta below); unhide any when needed.
            [void]$Rows.Add([PSCustomObject]@{
                    # visible by default
                    Raw = $Raw
                    $DateColumnHeader = $DateTime
                    UserPrincipalName = $LogEntry.UserPrincipalName
                    SignInEventTypes = $LogEntry.SignInEventTypes -join ', '
                    Error = ConvertTo-HumanErrorDescription -ErrorCode $LogEntry.Status.ErrorCode
                    IpAddress = $IpText
                    AutonomousSystemNumber = $LogEntry.AutonomousSystemNumber
                    City = $LogEntry.Location.City
                    State = $LogEntry.Location.State
                    Co = $LogEntry.Location.CountryOrRegion
                    Application = $AppDisplayName
                    AuthenticationProtocol = $LogEntry.AuthenticationProtocol
                    OriginalTransferMethod = $LogEntry.OriginalTransferMethod
                    Browser = $LogEntry.DeviceDetail.Browser
                    OS = $LogEntry.DeviceDetail.OperatingSystem
                    Trust = $Trust
                    UserAgent = $LogEntry.UserAgent
                    Session = $LogEntry.CorrelationId
                    Token = $LogEntry.UniqueTokenIdentifier
                    # hidden by default
                    AppId = $LogEntry.AppId
                    ResourceDisplayName = $LogEntry.ResourceDisplayName
                    ResourceId = $LogEntry.ResourceId
                    ClientAppUsed = $LogEntry.ClientAppUsed
                    ClientCredentialType = $LogEntry.ClientCredentialType
                    IncomingTokenType = $LogEntry.IncomingTokenType
                    TokenIssuerType = $LogEntry.TokenIssuerType
                    AuthenticationRequirement = $LogEntry.AuthenticationRequirement
                    ConditionalAccessStatus = $LogEntry.ConditionalAccessStatus
                    ConditionalAccessPolicies = $CaPolicies
                    AuthenticationMethodsUsed = $LogEntry.AuthenticationMethodsUsed -join ', '
                    MfaAuthMethod = $LogEntry.MfaDetail.AuthMethod
                    IsInteractive = $LogEntry.IsInteractive
                    CrossTenantAccessType = $LogEntry.CrossTenantAccessType
                    IsThroughGlobalSecureAccess = $LogEntry.IsThroughGlobalSecureAccess
                    RiskState = $LogEntry.RiskState
                    RiskDetail = $LogEntry.RiskDetail
                    RiskLevelDuringSignIn = $LogEntry.RiskLevelDuringSignIn
                    RiskLevelAggregated = $LogEntry.RiskLevelAggregated
                    RiskEventTypes = $LogEntry.RiskEventTypesV2 -join ', '
                    ErrorCode = $LogEntry.Status.ErrorCode
                    FailureReason = $LogEntry.Status.FailureReason
                    StatusDetails = $LogEntry.Status.AdditionalDetails
                    DeviceId = $LogEntry.DeviceDetail.DeviceId
                    DeviceName = $LogEntry.DeviceDetail.DisplayName
                    IsCompliant = $LogEntry.DeviceDetail.IsCompliant
                    IsManaged = $LogEntry.DeviceDetail.IsManaged
                    HomeTenantId = $LogEntry.HomeTenantId
                    ResourceTenantId = $LogEntry.ResourceTenantId
                    UserId = $LogEntry.UserId
                    UserType = $LogEntry.UserType
                    SignInIdentifier = $LogEntry.SignInIdentifier
                    SignInIdentifierType = $LogEntry.SignInIdentifierType
                    SignInTokenProtectionStatus = $LogEntry.SignInTokenProtectionStatus
                    SessionId = $LogEntry.SessionId
                    ProcessingTimeMs = $LogEntry.ProcessingTimeInMilliseconds
                    FlaggedForReview = $LogEntry.FlaggedForReview
                    Id = $LogEntry.Id
                    OriginalRequestId = $LogEntry.OriginalRequestId
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
        $AuthenticationProtocolColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'AuthenticationProtocol' }).Id |
                Convert-DecimalToExcelColumn
        $OriginalTransferMethodColumn = ($Worksheet.Tables[0].Columns |
                Where-Object { $_.Name -eq 'OriginalTransferMethod' }).Id |
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

        # device code: flag both the redemption leg (AuthenticationProtocol) and the
        # downstream token use Entra carries forward on OriginalTransferMethod. Matches
        # 'deviceCode' and 'deviceCodeFlow' (ContainsText is case-insensitive).
        $DeviceCodeColumns = @(
            $AuthenticationProtocolColumn
            $OriginalTransferMethodColumn
        )
        foreach ( $Column in $DeviceCodeColumns ) {
            $CFParams = @{
                Worksheet       = $WorkSheet
                Address         = "${Column}:${Column}"
                RuleType        = 'ContainsText'
                ConditionValue  = 'devicecode'
                BackgroundColor = 'LightPink'
            }
            Add-ConditionalFormatting @CFParams
        }

        #region COLUMN WIDTH AND VISIBILITY

        # Width + default visibility for every column. Every field is present in the
        # workbook; only the curated subset (Visible = $true) shows on open. Unhide any
        # other column in Excel when needed.
        $ColumnMeta = @(
            # visible by default
            @{ Name = 'Raw';                         Width = 8;   Visible = $true }
            @{ Name = $DateColumnHeader;             Width = 26;  Visible = $true }
            @{ Name = 'UserPrincipalName';           Width = 30;  Visible = $true }
            @{ Name = 'SignInEventTypes';            Width = 20;  Visible = $true }
            @{ Name = 'Error';                       Width = 25;  Visible = $true }
            @{ Name = 'IpAddress';                   Width = 20;  Visible = $true }
            @{ Name = 'AutonomousSystemNumber';      Width = 14;  Visible = $false }
            @{ Name = 'City';                        Width = 10;  Visible = $true }
            @{ Name = 'State';                       Width = 10;  Visible = $true }
            @{ Name = 'Co';                          Width = 6;   Visible = $true }
            @{ Name = 'Application';                 Width = 25;  Visible = $true }
            @{ Name = 'AuthenticationProtocol';      Width = 4;  Visible = $true }
            @{ Name = 'OriginalTransferMethod';      Width = 4;  Visible = $true }
            @{ Name = 'Browser';                     Width = 20;  Visible = $true }
            @{ Name = 'OS';                          Width = 12;  Visible = $true }
            @{ Name = 'Trust';                       Width = 12;  Visible = $true }
            @{ Name = 'UserAgent';                   Width = 150; Visible = $true }
            @{ Name = 'Session';                     Width = 10;  Visible = $true }
            @{ Name = 'Token';                       Width = 10;  Visible = $true }
            # hidden by default
            @{ Name = 'AppId';                       Width = 38;  Visible = $false }
            @{ Name = 'ResourceDisplayName';         Width = 30;  Visible = $false }
            @{ Name = 'ResourceId';                  Width = 38;  Visible = $false }
            @{ Name = 'ClientAppUsed';               Width = 20;  Visible = $false }
            @{ Name = 'ClientCredentialType';        Width = 20;  Visible = $false }
            @{ Name = 'IncomingTokenType';           Width = 18;  Visible = $false }
            @{ Name = 'TokenIssuerType';             Width = 16;  Visible = $false }
            @{ Name = 'AuthenticationRequirement';   Width = 24;  Visible = $false }
            @{ Name = 'ConditionalAccessStatus';     Width = 22;  Visible = $false }
            @{ Name = 'ConditionalAccessPolicies';   Width = 40;  Visible = $false }
            @{ Name = 'AuthenticationMethodsUsed';   Width = 26;  Visible = $false }
            @{ Name = 'MfaAuthMethod';               Width = 16;  Visible = $false }
            @{ Name = 'IsInteractive';               Width = 12;  Visible = $false }
            @{ Name = 'CrossTenantAccessType';       Width = 20;  Visible = $false }
            @{ Name = 'IsThroughGlobalSecureAccess'; Width = 26;  Visible = $false }
            @{ Name = 'RiskState';                   Width = 12;  Visible = $false }
            @{ Name = 'RiskDetail';                  Width = 16;  Visible = $false }
            @{ Name = 'RiskLevelDuringSignIn';       Width = 20;  Visible = $false }
            @{ Name = 'RiskLevelAggregated';         Width = 18;  Visible = $false }
            @{ Name = 'RiskEventTypes';              Width = 18;  Visible = $false }
            @{ Name = 'ErrorCode';                   Width = 10;  Visible = $false }
            @{ Name = 'FailureReason';               Width = 30;  Visible = $false }
            @{ Name = 'StatusDetails';               Width = 24;  Visible = $false }
            @{ Name = 'DeviceId';                    Width = 38;  Visible = $false }
            @{ Name = 'DeviceName';                  Width = 24;  Visible = $false }
            @{ Name = 'IsCompliant';                 Width = 12;  Visible = $false }
            @{ Name = 'IsManaged';                   Width = 12;  Visible = $false }
            @{ Name = 'HomeTenantId';                Width = 38;  Visible = $false }
            @{ Name = 'ResourceTenantId';            Width = 38;  Visible = $false }
            @{ Name = 'UserId';                      Width = 38;  Visible = $false }
            @{ Name = 'UserType';                    Width = 12;  Visible = $false }
            @{ Name = 'SignInIdentifier';            Width = 30;  Visible = $false }
            @{ Name = 'SignInIdentifierType';        Width = 20;  Visible = $false }
            @{ Name = 'SignInTokenProtectionStatus'; Width = 26;  Visible = $false }
            @{ Name = 'SessionId';                   Width = 38;  Visible = $false }
            @{ Name = 'ProcessingTimeMs';            Width = 16;  Visible = $false }
            @{ Name = 'FlaggedForReview';            Width = 16;  Visible = $false }
            @{ Name = 'Id';                          Width = 38;  Visible = $false }
            @{ Name = 'OriginalRequestId';           Width = 38;  Visible = $false }
        )
        foreach ($Meta in $ColumnMeta) {
            $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $Meta.Name }).Id
            if ($Col) {
                $Worksheet.Column($Col).Width = $Meta.Width
                $Worksheet.Column($Col).Hidden = -not $Meta.Visible
            }
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
