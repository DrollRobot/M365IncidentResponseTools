New-Alias -Name 'ShowMFA' -Value 'Show-UserMFA' -Force
New-Alias -Name 'UserMFA' -Value 'Show-UserMFA' -Force
function Show-UserMFA {
    <#
    .SYNOPSIS
    Shows a graph user's MFA methods.     

    .NOTES
    Inspired by:
    https://thesysadminchannel.com/get-mfa-methods-using-msgraph-api-and-powershell-sdk/ -
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [string] $TableStyle = 'Dark8',
        [boolean] $Xml = $true,
        [boolean] $Open = $true
    )
     
    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName

        $OutputTable = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Properties = [System.Collections.Generic.Hashset[string]]::new()
        $PropertySortOrder = @(
            'Raw'
            'CreatedDateTime'
            'MethodType'
            'DisplayName'
            'PhoneNumber'
            'PhoneType'
            'SmsSignInState'
            'EmailAddress'
            'DeviceTag'
            'Id'
            'DeleteCommand'
        )
        $EventDateFormat = 'MM/dd/yy hh:mm:sstt'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'MFAMethods'

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Red = @{ ForegroundColor = 'Red' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
        # $Yellow = @{ ForegroundColor = 'Yellow' }

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

        # get client domain name for file output
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

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

            Write-Host @Blue "`n${Function}: Getting MFA methods for: ${UserEmail}"
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
                        switch ( $Method.AdditionalProperties["@odata.type"] ) {
                            # email
                            '#microsoft.graph.emailAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Email'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationEmailMethod -UserId ${UserId} -EmailAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # fido
                            '#microsoft.graph.fido2AuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Fido2'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationFido2Method -UserId ${UserId} -Fido2AuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # microsoft authenticator
                            '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'MicrosoftAuthenticator'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId ${UserId} -MicrosoftAuthenticatorAuthenticationMethodId ${MethodId}"
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
                            '#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Passwordless'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgBetaUserAuthenticationPasswordlessMicrosoftAuthenticatorMethod -UserId ${UserId} -PasswordlessMicrosoftAuthenticatorAuthenticationMethodId  ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # phone
                            '#microsoft.graph.phoneAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'Phone'
                                $CustomObject | Add-Member @NameParams
                                
                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationPhoneMethod -UserId ${UserId} -PhoneAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # software oath
                            '#microsoft.graph.softwareOathAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'SoftwareOath'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationSoftwareOathMethod -UserId ${UserId} -SoftwareOathAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # temporary access pass
                            '#microsoft.graph.temporaryAccessPassAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'TemporaryAccessPass'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationTemporaryAccessPassMethod -UserId ${UserId} -TemporaryAccessPassAuthenticationMethodId ${MethodId}"
                                $DeleteParams['Value'] = $DeleteString
                                $CustomObject | Add-Member @DeleteParams
                            }
                            # windows hello
                            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {

                                # add human friendly method name
                                $NameParams['Value'] = 'WindowsHelloForBusiness'
                                $CustomObject | Add-Member @NameParams

                                # add delete command
                                $DeleteString = "Remove-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId ${UserId} -WindowsHelloForBusinessAuthenticationMethodId ${MethodId}"
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

                    # convert created date string to datetime object # FIXME use new function for date string
                    elseif ( $Key -eq 'createdDateTime' ) {

                        # start params table
                        $AddParams = @{
                            MemberType = 'NoteProperty'
                            Name       = 'CreatedDateTime'
                        }

                        # cast string to datetime object
                        $DateTime = [datetime]( $Method.AdditionalProperties[$Key] )

                        ### build date string
                        $BuildString = $DateTime.ToLocalTIme().ToString( $EventDateFormat ).ToLower()
                        # create acronym from timezone full name
                        if ( $DateTime.ToLocalTIme().IsDaylightSavingTime()) {
                            $TimeZoneName = $TimeZoneInfo.DaylightName
                        }
                        else {
                            $TimeZoneName = $TimeZoneInfo.StandardName
                        }
                        $TimeZoneAcronym = -join ( $TimeZoneName -split ' ' | ForEach-Object { $_[0] } )
                        # add time zone acronym to string
                        $EventDateString = $BuildString + " " + $TimeZoneAcronym
                        # if first character of date is 0, replace with space
                        if ( $EventDateString[0] -eq '0' ) {
                            $EventDateString = " " + $EventDateString.Substring(1)
                        }
                        # if first character of time is 0, replace with space
                        if ( $EventDateString[9] -eq '0' ) {
                            $EventDateString = $EventDateString.Substring(0, 9) + " " + $EventDateString.Substring(10)
                        }

                        # add object to table
                        $AddParams['Value'] = $EventDateString
                        $CustomObject | Add-Member @AddParams
                    }

                    # for other properties, add to table
                    else {

                        # capitalize propertyname
                        $CapPropertyName = $Key.Substring(0, 1).ToUpper() + $Key.Substring(1)

                        # add to object
                        $AddParams = @{
                            MemberType = 'NoteProperty'
                            Name       = $CapPropertyName
                            Value      = $Method.AdditionalProperties[$Key]
                        }
                        $CustomObject | Add-Member @AddParams
                    }
                }
    
                # add loop object to table
                $OutputTable.Add( $CustomObject )
            }

            # show raw data if verbose
            if ($VerbosePreference -eq 'Continue') {
                Write-Verbose "Raw data:"
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
                Write-Host @Blue "${Function}: Exporting raw data to: ${XmlOutputPath}"
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
                $Workbook = $OutputTable | Select-Object $SortedProperties | Export-Excel @ExcelParams
            }
            catch {
                Write-Error "${Function}: Unable to open new Excel document."
                if ( Get-YesNo "${Function}: Try closing open files." ) {
                    try {
                        $Workbook = $OutputTable | Export-Excel @ExcelParams
                    }
                    catch {
                        throw "${Function}: Unable to open new Excel document. Exiting."
                    }
                }
            }
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]

            # get table ranges
            $SheetStartColumn = $WorkSheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $WorkSheet.Dimension.Start.Row
            # $TableStartColumn = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Column | Convert-DecimalToExcelColumn
            # $TableStartRow = ( $workSheet.Tables.Address | Select-Object -First 1 ).Start.Row
            $EndColumn = $WorkSheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $WorkSheet.Dimension.End.Row

            #region COLUMN WIDTH

            # resize Raw column
            $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Raw' } ).Id 
            $Worksheet.Column($Column).Width = 8

            # resize DateTime column
            $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'CreatedDateTime' } ).Id 
            $Worksheet.Column($Column).Width = 26
            
            # resize Id column
            $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'Id' } ).Id
            $Worksheet.Column($Column).Width = 20

            # resize DeleteCommand column
            $Column = ( $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq 'DeleteCommand' } ).Id
            $Worksheet.Column($Column).Width = 100

            #region FORMATTING

            # # set text wrapping in description column
            # $WrappingParams = @{
            #     Worksheet = $Worksheet
            #     Range     = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"
            #     WrapText  = $true
            # }
            # Set-ExcelRange @WrappingParams

            # # set row height
            # for ( $i = $TableStartRow; $i -le $EndRow; $i++ ) {  
            #     $workSheet.Row($i).CustomHeight = 15
            # }
            
            # set font and size
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = 'Consolas'
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
            if ($Open) {
                Write-Host @Blue "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}