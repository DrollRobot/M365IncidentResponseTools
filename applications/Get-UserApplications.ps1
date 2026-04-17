New-Alias -Name 'UserApps' -Value 'Get-UserApplications' -Force
function Get-UserApplications {
    <#
	.SYNOPSIS
	Displays user's Oauth2 permission grants. (Applications they have granted consent to)
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Open = $true,
        [switch] $Test,
        [switch] $Cached
    )

    begin {

        #region BEGIN

        # constants
        # $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $WorksheetName = 'UserAppConsents'

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
    
        # if not passed directly, find global user object
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

        # check if connected to exchange
        try {
            $Exchange = Get-ConnectionInformation
        }
        catch {}
        if ( -not $Exchange ) {
            Write-Host @Red "Not connected to ExchangeOnlineManagement. Consent dates won't be checked."
        }

        # get client domain name for file output
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # prefetch graph data once
        $Grants = Request-GraphOauth2Grants -Cached:$Cached
        $ServicePrincipals = Request-GraphServicePrincipals -Cached:$Cached
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserId    = $ScriptUserObject.Id
            $UserName  = $UserEmail -split '@' | Select-Object -First 1

            # filenames
            $DateStamp        = Get-Date -Format $FileNameDateFormat
            $XmlOutputPath    = "UserApps_Raw_${DomainName}_${UserName}_${DateStamp}.xml"
            $ExcelOutputPath  = "UserApps_${DomainName}_${UserName}_${DateStamp}.xlsx"

            # worksheet title
            $TitleStamp     = (Get-Date).ToString("M/d/yy h:mmtt").ToLower()
            $WorksheetTitle = "Application consent for ${UserEmail} on ${TitleStamp}."

            # filter down to grants that apply to user
            $UserGrants = $Grants | Where-Object { $_.PrincipalId -eq $UserId }

            foreach ( $Grant in $UserGrants ) {

                # find application
                $Client   = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ClientId }   
                $Resource = $ServicePrincipals | Where-Object { $_.Id -eq $Grant.ResourceId }

                # find friendly name, or revert to id
                $AppName = if ($Client -and $Client.DisplayName){
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
                Write-Host @Red "No user consent applications."
                continue
            }

            if ($Xml) {
                Write-Host @Blue "Exporting raw data to: ${XmlOutputPath}"
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
                $Workbook = $OutputTable | Select-Object User,Application,Resource,Scope | Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to open new Excel document."
                if (Get-YesNo "Try closing open files.") {
                    try {
                        $Workbook = $OutputTable | Select-Object User,Application,Resource,Scope | Export-Excel @ExcelParams
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
            $SheetStartRow    = $Worksheet.Dimension.Start.Row
            $EndColumn        = ($Worksheet.Dimension.End.Column)   | Convert-DecimalToExcelColumn
            $EndRow           = $Worksheet.Dimension.End.Row

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
            Set-Format @BorderParams

            #region OUTPUT

            # save and open/close
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