function Connect-IRTTenant {
    <#
    .SYNOPSIS
    Connects to a tenant using a friendly alias looked up from a tenant configuration worksheet.

    .DESCRIPTION
    Reads tenant information from a worksheet and matches the provided alias against
    each tenant's Aliases regex pattern. Once matched, it passes the tenant's parameters
    to Connect-IRT and opens any configured URLs in the browser.

    If multiple tenants match the alias, a numbered menu is presented so the user can
    select which tenant to connect to. This allows the same alias patterns to be shared
    across multiple tenants belonging to the same client.

    The tenants worksheet should be stored at $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.
    A template file (TenantsTemplate.xlsx) is included in the Data folder for reference.

    .PARAMETER Alias
    A string to match against tenant alias patterns. Matched as a regex against the
    Aliases column in the tenants worksheet.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER AdditionalScope
    Additional Graph scopes to request beyond the default set.

    .PARAMETER Browser
    Browser to use for URL opening. Valid values: msedge, chrome,
    firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .EXAMPLE
    Connect-IRTTenant contoso
    Looks up 'contoso' in the tenants worksheet and connects to all services.

    .EXAMPLE
    Connect-IRTTenant fab -Graph
    Looks up 'fab' in the tenants worksheet and connects to Graph only.

    .EXAMPLE
    irttenant bestcompany
    Uses the alias to connect to the matching tenant.

    .NOTES
    Version: 1.2.0
    1.2.0 - Multiple-match now prompts user with a selection menu instead of throwing.
    1.1.0 - Updated to use xlsx file instead of csv.
    #>
    [Alias('IRTTenant')]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword', 'PasswordBrowser')]

    param (
        [Parameter( Mandatory, Position = 0 )]
        [string] $Alias,

        [string] $TenantFile,

        [switch] $Graph,
        [switch] $Exchange,

        [Alias('AdditionalScopes', 'Scopes', 'Scope')]
        [string[]] $AdditionalScope,

        [string] $PasswordBrowser = $IRT_Config.PasswordBrowser,

        [switch] $Private
    )

    begin {
        Import-IRTModule -Name 'ImportExcel'
        if (-not $TenantFile) {
            $TenantFile = $Global:IRT_Config.TenantsSheetPath
        }
    }

    process {


        # validate tenant file exists
        if (-not ( Test-Path $TenantFile )) {
            Write-Error ("Tenant file not found: ${TenantFile}`n" +
                "Run Open-IRTTenantSheet to create it and edit with your tenant information.")
            return
        }

        # import and search for matching tenant
        $Tenants = Import-Excel -Path $TenantFile
        $MatchedTenants = @()

        foreach ($Tenant in $Tenants) {

            if ($Alias -match "^($($Tenant.Aliases))$") {
                $MatchedTenants += $Tenant
            }
        }
        if ($MatchedTenants.Count -eq 0) {

            $AvailableNames = ($Tenants | ForEach-Object { $_.TenantName }) -join ', '
            Write-Error "No tenant matched alias '${Alias}'. Available tenants: ${AvailableNames}"
            return
        }
        if ($MatchedTenants.Count -gt 1) {
            $TenantNames = $MatchedTenants | ForEach-Object { $_.TenantName }
            $MenuParams = @{
                Option = $TenantNames
                Title  = "Multiple tenants matched '${Alias}'. Select a tenant:"
                List   = $true
            }
            $SelectedName = Build-Menu @MenuParams
            $MatchedTenant = $MatchedTenants | Where-Object { $_.TenantName -eq $SelectedName }
        }
        else {
            $MatchedTenant = $MatchedTenants[0]
        }

        Write-IRT "Matched tenant: $($MatchedTenant.TenantName)"

        # build connection parameters
        $ConnectParams = @{
            TenantId = $MatchedTenant.TenantId
        }

        if ($Graph) { $ConnectParams['Graph'] = $true }
        if ($Exchange) { $ConnectParams['Exchange'] = $true }

        if ($AdditionalScope) {
            $ConnectParams['AdditionalScope'] = $AdditionalScope
        }

        if ($Private) { $ConnectParams['Private'] = $true }

        # open configured URLs
        if ($MatchedTenant.PasswordURLs) {
            $URLs = $MatchedTenant.PasswordURLs -split ';'
            foreach ($URL in $URLs) {
                $URL = $URL.Trim()
                if ($URL) {
                    Open-Browser -Browser $PasswordBrowser -Url $URL -Private:$Private
                }
            }
        }

        # connect
        Connect-IRT @ConnectParams
    }
}
