function Get-IRTServicePrincipal {
    <#
	.SYNOPSIS
	Displays all service principals in the tenant, or filters by a search term.

	.NOTES
	Version: 1.3.0
	1.3.0 - Added -Excel export option.
	#>
    [Alias('GetTenantServicePrincipal', 'GetTenantServicePrincipals',
        'GetTenantSP', 'GetTenantSPs',
        'GetTenantApp', 'GetTenantApps',
        'GetTenantApplication', 'GetTenantApplications',
        'GetTenantEnterpriseApp', 'GetTenantEnterpriseApps',
        'GetAllServicePrincipals', 'GetAllSP', 'GetAllSPs',
        'GetAllApps', 'GetAllApplications', 'GetAllEnterpriseApps',
        'Get-Apps', 'Get-ServicePrincipals', 'Get-EnterpriseApps', 'Get-Applications')]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    [CmdletBinding()]
    param (
        [string] $Search,
        [switch] $Cached,
        [switch] $Excel,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $TenantId = (Get-MgContext).TenantId
        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached

        # custom default display view - no ps1xml needed
        $TypeDataParams = @{
            TypeName                  = 'IRT.TenantServicePrincipal'
            DefaultDisplayPropertySet = 'CreatedDateTime', 'AppDisplayName', 'AppOwner', 'AppId'
            Force                     = $true
        }
        Update-TypeData @TypeDataParams

        # --- Resolve AppOwnerOrganizationIds via Get-IRTTenantOwner ---
        # Collect unique foreign owner org GUIDs (skip current tenant and blanks)
        $foreignOwnerIds = $ServicePrincipals |
            Select-Object -ExpandProperty AppOwnerOrganizationId -Unique |
            Where-Object { $_ -and $_ -ne $TenantId }

        $ownerDisplayNames = @{}
        if ($foreignOwnerIds) {
            $foreignOwnerIds | Get-IRTTenantOwner -ErrorAction SilentlyContinue | ForEach-Object {
                # Prefer DisplayName; fall back to GUID if Graph was unavailable
                $ownerDisplayNames[$_.TenantId] = if ($_.DisplayName) {
                    $_.DisplayName } else { $_.TenantId
                }
            }
        }
    }

    process {

        if ( $Search ) {
            Write-IRT "Service principals matching: ${Search}"
            $MatchingServicePrincipals = $ServicePrincipals |
                Where-Object { $_.DisplayName -match $Search }
        }
        else {
            Write-IRT "All service principals:"
            $MatchingServicePrincipals = $ServicePrincipals
        }

        $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($ServicePrincipal in $MatchingServicePrincipals) {

            # change date to local time
            $CreatedDateTime = $ServicePrincipal.CreatedDateTime
            if ( $CreatedDateTime ) {
                $CreatedDateTime = $CreatedDateTime.ToLocalTime()
            }

            # resolve AppOwnerOrganizationId to a display name
            $OwnerOrgId = $ServicePrincipal.AppOwnerOrganizationId
            $AppOwner = if (-not $OwnerOrgId) {
                $null
            }
            elseif ($OwnerOrgId -eq $TenantId) {
                'Current Tenant'
            }
            elseif ($ownerDisplayNames.ContainsKey($OwnerOrgId)) {
                $ownerDisplayNames[$OwnerOrgId]
            }
            else {
                $OwnerOrgId
            }

            # display sp
            $OutputTable.Add( [pscustomobject]@{
                    PSTypeName           = 'IRT.TenantServicePrincipal'
                    CreatedDateTime      = $CreatedDateTime
                    AppDisplayName       = $ServicePrincipal.AppDisplayName
                    ServicePrincipalType = $ServicePrincipal.ServicePrincipalType
                    SignInAudience       = $ServicePrincipal.SignInAudience
                    ReplyUrls            = $ServicePrincipal.ReplyUrls
                    AppOwner             = $AppOwner
                    AppId                = $ServicePrincipal.AppId
                    Id                   = $ServicePrincipal.Id
                    AccountEnabled       = $ServicePrincipal.AccountEnabled
                } )
        }
    }

    end {

        if (-not $Excel) {
            $OutputTable
        }
        else {

            $DomainName = Get-DefaultDomain
            $FileNameDateFormat = 'yy-MM-dd_HH-mm'
            $FileDateString = Get-Date -Format $FileNameDateFormat
            $ExcelOutputPath = "ServicePrincipals_${DomainName}_${FileDateString}.xlsx"
            $TitleDateString = Get-Date -Format 'MM/dd/yy HH:mm'
            $WorksheetName = 'ServicePrincipals'

            Write-IRT "Exporting Excel: ${ExcelOutputPath}"

            $ExportData = $OutputTable | Select-Object -Property @(
                'CreatedDateTime'
                'AppDisplayName'
                'ServicePrincipalType'
                'SignInAudience'
                'AppOwner'
                'AppId'
                'Id'
                @{ Name = 'ReplyUrls'; Expression = { $_.ReplyUrls -join ', ' } }
            )

            $ExcelParams = @{
                Path          = $ExcelOutputPath
                WorkSheetname = $WorksheetName
                TableName     = 'ServicePrincipals'
                TableStyle    = $TableStyle
                StartRow      = 3
                AutoSize      = $true
                Passthru      = $true
            }

            try {
                $Workbook = $ExportData | Export-Excel @ExcelParams
            }
            catch {
                Write-Error "Unable to write Excel file: ${ExcelOutputPath}"
                return
            }

            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
            $SheetEnd = $Worksheet.Dimension.End.Address

            Set-ExcelRange -Worksheet $Worksheet -Range "A1:${SheetEnd}" -FontName $Font

            $TitleText = if ($Search) {
                "Service principals matching '${Search}' for ${DomainName} as of ${TitleDateString}"
            }
            else {
                "All service principals for ${DomainName} as of ${TitleDateString}"
            }

            $Worksheet.Cells[1, 1].Value = $TitleText
            $Worksheet.Cells[1, 1].Style.Font.Bold = $true
            $Worksheet.Cells[1, 1].Style.Font.Size = 16

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