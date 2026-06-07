function Get-IRTUserServicePrincipal {
    <#
    .SYNOPSIS
    Displays user's Oauth2 permission grants. (Applications they have granted consent to)

    .DESCRIPTION
    Retrieves all OAuth2 permission grants for one or more Entra ID users and displays the
    applications they have personally consented to. Each row shows the app name, granted
    scopes, and the consent date if available.

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

    .PARAMETER Cached
    Use pre-cached Graph service principal data instead of making new API calls.

    .EXAMPLE
    Get-IRTUserServicePrincipal
    Shows OAuth app consents for the user in the global session.

    .EXAMPLE
    Get-IRTUserServicePrincipal -UserObject $User
    Shows OAuth app consents for a specific user.

    .OUTPUTS
    None. Results are displayed in the console and optionally exported to Excel.
    #>
    [Alias('UserApps', 'UserSPs',
        'GetUserSP', 'GetUserSPs',
        'GetUserApp', 'GetUserApps',
        'GetUserApplication', 'GetUserApplications',
        'GetUserServicePrincipal', 'GetUserServicePrincipals',
        'GetUserEnterpriseApp', 'GetUserEnterpriseApps',
        'Get-UserApplication')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Open = $true,
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Graph'
        Import-IRTModule -Name 'ImportExcel'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'UserAppConsents'

        # if not passed directly, find global user object
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

        # prefetch graph data once
        $Grants = Request-GraphOauth2Grant -Cached:$Cached
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserId = $ScriptUserObject.Id
            $UserName = $UserEmail -split '@' | Select-Object -First 1

            # filenames
            $DateStamp = Get-Date -Format $FileNameDateFormat
            $XmlOutputPath = "UserSPs_Raw_${DomainName}_${UserName}_${DateStamp}.xml"
            $ExcelOutputPath = "UserSPs_${DomainName}_${UserName}_${DateStamp}.xlsx"

            # worksheet title
            $TitleStamp = (Get-Date).ToString("M/d/yy h:mmtt").ToLower()
            $WorksheetTitle = "Application consent for ${UserEmail} on ${TitleStamp}."

            # filter down to grants that apply to user
            $UserGrants = $Grants | Where-Object { $_.PrincipalId -eq $UserId }

            foreach ( $Grant in $UserGrants ) {

                # find application
                $Client = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ClientId }
                $Resource = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ResourceId }

                # find friendly name, or revert to id
                $AppName = if ($Client -and $Client.DisplayName) {
                    $Client.DisplayName
                }
                else {
                    $Grant.ClientId
                }
                $ResourceName = if ($Resource -and $Resource.DisplayName) {
                    $Resource.DisplayName
                }
                else {
                    $Grant.ResourceId
                }

                # add row
                $OutputTable.Add(
                    [pscustomobject]@{
                        User        = $UserEmail
                        Application = $AppName
                        Resource    = $ResourceName
                        Scopes       = $Grant.Scope
                    }
                )
            }

            if (($OutputTable | Measure-Object).Count -eq 0) {
                Write-IRT "No user consent applications." -Level Warn
                continue
            }

            if ($Xml) {
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $UserGrants | Export-CliXml -Depth 10 -Path $XmlOutputPath
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
                    Select-Object User, Application, Resource, Scope |
                    Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to open new Excel document."
                if (Get-YesNo "Try closing open files.") {
                    try {
                        $Workbook = $OutputTable |
                            Select-Object User, Application, Resource, Scope |
                            Export-Excel @ExcelParams
                    }
                    catch {
                        throw "Unable to open new Excel document. Exiting."
                    }
                }
                else {
                    throw
                }
            }

            # post-formatting
            $Worksheet = $Workbook.Workbook.Worksheets[$ExcelParams.WorksheetName]
            $SheetStartColumn = ($Worksheet.Dimension.Start.Column) | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $EndColumn = ($Worksheet.Dimension.End.Column) | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row

            #region FORMATTING

            # set font and size for full used range
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

            # save and open/close
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
