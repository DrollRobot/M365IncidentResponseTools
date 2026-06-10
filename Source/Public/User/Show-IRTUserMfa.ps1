function Show-IRTUserMfa {
    <#
    .SYNOPSIS
    Shows a graph user's MFA methods.

    .DESCRIPTION
    Retrieves all registered authentication methods for one or more Entra ID users and
    displays them in a formatted table. Each method row includes type, summary details,
    and a pre-built deletion command for quick remediation.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more Entra ID user objects to query. Falls back to global session objects if
    omitted. Accepts pipeline input.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .EXAMPLE
    Show-IRTUserMfa
    Displays MFA methods for the user in the global session.

    .EXAMPLE
    Show-IRTUserMfa -UserObject $User
    Displays MFA methods for a specific user.

    .OUTPUTS
    None. Results are displayed in the console and optionally exported to Excel.

    .NOTES
    Credit to:
    https://thesysadminchannel.com/get-mfa-methods-using-msgraph-api-and-powershell-sdk/
    #>
    [Alias('ShowMFA', 'UserMFA')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0,
            ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ImportParams = @{
            Name = @(
                'ImportExcel'
                'Microsoft.Graph.Identity.SignIns'
                'Microsoft.Graph.Users'
                'PSFramework'
            )
        }
        Import-IRTModule @ImportParams
        $OutputTable = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Properties = [System.Collections.Generic.Hashset[string]]::new()
        $PropertySortOrder = @(
            'Raw'
            'MethodType'
            'Summary'
            'Id'
            'DeleteCommand'
        )
        $EventDateFormat = 'MM/dd/yy hh:mm:sstt'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'MFAMethods'


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
        $DomainName = Get-DefaultDomain

        # get date/time string for filename
        $DateString = Get-Date -Format $FileNameDateFormat
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserId = $ScriptUserObject.Id

            # get username
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # build file name
            $XmlOutputPath = "MFAMethods_${DomainName}_${UserName}_${DateString}.xml"
            $ExcelOutputPath = "MFAMethods_${DomainName}_${UserName}_${DateString}.xlsx"

            # build worksheet title
            $DateString = ( Get-Date ).ToString( "M/d/yy h:mmtt" ).ToLower()
            $WorksheetTitle = "MFA methods for ${UserEmail} on ${DateString}."

            Write-IRT "Getting MFA methods for: ${UserEmail}"
            $Methods = Get-MgUserAuthenticationMethod -UserId $ScriptUserObject.Id -ErrorAction Stop

            foreach ( $Method in $Methods ) {

                # variables
                $MethodId = $Method.Id
                $CustomObject = [PSCustomObject]@{
                    Id = $Method.Id
                }

                # Raw
                $Raw = $Method | ConvertTo-Json -Depth 10
                $AddParams = @{
                    MemberType = 'NoteProperty'
                    Name       = 'Raw'
                    Value      = $Raw
                }
                $CustomObject | Add-Member @AddParams

                $SummaryParts = [System.Collections.Generic.List[string]]::new()

                foreach ( $Key in $Method.AdditionalProperties.Keys ) {

                    # set user friendly type name
                    if ( $Key -eq "@odata.type" ) {

                        # start params tables
                        $NameParams = @{
                            MemberType = 'NoteProperty'
                            Name       = 'MethodType'
                        }
                        $DeleteParams = @{
                            MemberType = 'NoteProperty'
                            Name       = 'DeleteCommand'
                        }

                        # add human friendly method name to table, then add table to custom object
                        switch -Wildcard ( $Method.AdditionalProperties["@odata.type"] ) {
                            # email
                            '#microsoft.graph.emailAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Email'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationEmailMethod' +
                                " -UserId ${UserId} -EmailAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # fido
                            '#microsoft.graph.fido2AuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Fido2'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationFido2Method' +
                                " -UserId ${UserId} -Fido2AuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # microsoft authenticator
                            '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'MicrosoftAuthenticator'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod' +
                                " -UserId ${UserId}" +
                                ' -MicrosoftAuthenticatorAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # password
                            '#microsoft.graph.passwordAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Password'
                                $CustomObject | Add-Member @NameParams
                            }
                            # passwordless
                            '*passwordlessMicrosoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Passwordless'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgBetaUserAuthentication' +
                                'PasswordlessMicrosoftAuthenticatorMethod' +
                                " -UserId ${UserId}" +
                                ' -PasswordlessMicrosoftAuthenticatorAuthentication' +
                                "MethodId  ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # phone
                            '#microsoft.graph.phoneAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Phone'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationPhoneMethod' +
                                " -UserId ${UserId} -PhoneAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # software oath
                            '#microsoft.graph.softwareOathAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'SoftwareOath'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = 'Remove-MgUserAuthenticationSoftwareOathMethod' +
                                " -UserId ${UserId}" +
                                ' -SoftwareOathAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # temporary access pass
                            '#microsoft.graph.temporaryAccessPassAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'TemporaryAccessPass'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationTemporaryAccessPassMethod' +
                                " -UserId ${UserId}" +
                                ' -TemporaryAccessPassAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # windows hello
                            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'WindowsHelloForBusiness'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString =
                                'Remove-MgUserAuthenticationWindowsHelloForBusinessMethod' +
                                " -UserId ${UserId}" +
                                ' -WindowsHelloForBusinessAuthenticationMethodId' +
                                " ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            default {

                                # add human friendly method name
                                $NameParams['Value'] = $Method.AdditionalProperties["@odata.type"]
                                $CustomObject | Add-Member @NameParams
                            }
                        }
                    }

                    # convert created date string to datetime object and add to summary
                    elseif ( $Key -eq 'createdDateTime' ) {

                        # cast string to datetime object
                        $DateTime = [datetime]( $Method.AdditionalProperties[$Key] )

                        ### build date string
                        $BuildString = $DateTime.ToLocalTIme().ToString(
                            $EventDateFormat).ToLower()
                        # create acronym from timezone full name
                        if ( $DateTime.ToLocalTIme().IsDaylightSavingTime()) {
                            $TimeZoneName = $TimeZoneInfo.DaylightName
                        }
                        else {
                            $TimeZoneName = $TimeZoneInfo.StandardName
                        }
                        $TimeZoneAcronym = -join ($TimeZoneName -split ' ' |
                                ForEach-Object { $_[0] })
                        # add time zone acronym to string
                        $EventDateString = $BuildString + " " + $TimeZoneAcronym
                        # if first character of date is 0, replace with space
                        if ( $EventDateString[0] -eq '0' ) {
                            $EventDateString = " " + $EventDateString.Substring(1)
                        }
                        # if first character of time is 0, replace with space
                        if ( $EventDateString[9] -eq '0' ) {
                            $EventDateString = $EventDateString.Substring(0, 9) +
                            ' ' + $EventDateString.Substring(10)
                        }

                        # add to summary list
                        $SummaryParts.Add( "CreatedDateTime: ${EventDateString}" )
                    }

                    # for other properties, add to summary list
                    else {

                        # capitalize propertyname
                        $CapPropertyName = $Key.Substring(0, 1).ToUpper() + $Key.Substring(1)

                        # format phone numbers for Excel compatibility
                        $Value = $Method.AdditionalProperties[$Key]
                        if ( $CapPropertyName -eq 'PhoneNumber' ) {
                            $Value = Format-PhoneNumber $Value
                        }

                        # add to summary list
                        if ( $null -ne $Value -and $Value -ne '' ) {
                            $SummaryParts.Add( "${CapPropertyName}: ${Value}" )
                        }
                    }
                }

                # add summary column
                if ( $SummaryParts.Count -gt 0 ) {
                    $SummaryString = $SummaryParts -join "`n"
                    $NpParams = @{
                        MemberType = 'NoteProperty'
                        Name       = 'Summary'
                        Value      = $SummaryString
                    }
                    $CustomObject | Add-Member @NpParams
                }

                # add loop object to table
                $OutputTable.Add( $CustomObject )
            }

            # show raw data if verbose
            if ($VerbosePreference -eq 'Continue') {
                Write-PSFMessage -Level 8 -Message "Raw data:"
                $Methods.AdditionalProperties
            }

            # collect all property names
            foreach ( $Object in $OutputTable ) {
                $Properties.UnionWith( [string[]]@($Object.PsObject.Properties.Name) )
            }

            # sort properties in custom order
            $SortedProperties = $Properties | Sort-Object -Property @{
                Expression = {
                    $Index = $PropertySortOrder.IndexOf( $_ )
                    # if not in the list, make last
                    if ( $Index -eq -1 ) {
                        [int]::MaxValue
                    }
                    else {
                        $Index
                    }
                }
                Ascending  = $true
            }

            if ($Xml) {
                # export raw data as xml
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $Methods | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            #region EXCEL
            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorkSheetName
                Title         = $WorksheetTitle
                TableStyle    = $TableStyle
                AutoSize      = $true
                FreezeTopRow  = $true
                Passthru      = $true
            }
            try {
                $Workbook = $OutputTable |
                    Select-Object $SortedProperties | Export-Excel @ExcelParams
            }
            catch {
                Write-IRT "Unable to open new Excel document." -Level Error
                if ( Get-YesNo "Try closing open files. Respond y when done." ) {
                    try {
                        $Workbook = $OutputTable | Export-Excel @ExcelParams
                    }
                    catch {
                        Write-IRT "Unable to open new Excel document. Exiting." -Level Error
                    }
                }
            }
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

            # get table ranges
            $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $WorkSheet.Dimension.Start.Row
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 )
            #     .Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            $SummaryColumn = ($Worksheet.Tables[0].Columns |
                    Where-Object { $_.Name -eq 'Summary' }).Id |
                    Convert-DecimalToExcelColumn

            #region COLUMN WIDTH

            # column widths
            $ColumnWidths = @{
                'Raw'           = 8
                'MethodType'    = 20
                'Summary'       = 70
                'Id'            = 42
                'DeleteCommand' = 200
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            #region FORMATTING

            # enable text wrapping on Summary column
            $WrapParams = @{
                Worksheet = $Worksheet
                Range     = "${SummaryColumn}${TableStartRow}:${SummaryColumn}${EndRow}"
                WrapText  = $true
            }
            Set-ExcelRange @WrapParams

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
            if ($Open) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}
