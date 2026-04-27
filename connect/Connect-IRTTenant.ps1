New-Alias -Name 'IRTTenant' -Value 'Connect-IRTTenant' -Force

function Connect-IRTTenant {
    <#
    .SYNOPSIS
    Connects to a tenant using a friendly alias looked up from a tenant configuration worksheet.

    .DESCRIPTION
    Reads tenant information from a worksheet and matches the provided alias against
    each tenant's Aliases regex pattern. Once matched, it passes the tenant's parameters
    to Connect-IRT and opens any configured URLs in the browser.

    The tenants worksheet should be stored at $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.
    A template file (tenants_TEMPLATE.xlsx) is included in the module_init folder for reference.

    .PARAMETER Alias
    A string to match against tenant alias patterns. Matched as a regex against the
    Aliases column in the tenants worksheet.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .PARAMETER Graph
    Connect to Microsoft Graph only.

    .PARAMETER Exchange
    Connect to Exchange Online only.

    .PARAMETER AdditionalScopes
    Additional Graph scopes to request beyond the default set.

    .PARAMETER DeviceCode
    Use device code authentication. Requires the tenant's DeviceAuthAllowed column to be set to 'yes'.
    Interactive authentication is used by default. An error is thrown if device code is requested
    but the tenant does not allow it.

    .PARAMETER Browser
    Browser to use for device code login and URL opening. Valid values: msedge, chrome, firefox, brave, default.

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
    Version: 1.1.0
    1.1.0 - Updated to use xlsx file instead of csv.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'PasswordBrowser')] # suppress annoying warning

    param (
        [Parameter( Mandatory, Position = 0 )]
        [string] $Alias,

        [string] $TenantFile = $(if ($Global:IRT_Config.TenantsSheetPath) {
            $Global:IRT_Config.TenantsSheetPath
        } else {
            Join-Path $env:APPDATA 'M365IncidentResponseTools\tenants.xlsx'
        }),

        [switch] $Graph,
        [switch] $Exchange,

        [string[]] $AdditionalScopes,
        [System.Nullable[bool]] $DeviceCode,

        [string] $PasswordBrowser = $IRT_Config.PasswordBrowser,

        [switch] $Private
    )

    process {

        # validate tenant file exists
        if (-not ( Test-Path $TenantFile )) {

            $Message  = "Tenant file not found: ${TenantFile}`n"
            $Message += "Run Open-IRTTenantsWorksheet to create it and edit with your tenant information."

            throw $Message
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

            $AvailableNames = ($Tenants | ForEach-Object {$_.TenantName}) -join ', '
            throw "No tenant matched alias '${Alias}'. Available tenants: ${AvailableNames}"
        }
        if ($MatchedTenants.Count -gt 1) {

            $MatchedNames = ($MatchedTenants | ForEach-Object {$_.TenantName}) -join ', '
            throw "Multiple tenants matched alias '${Alias}': ${MatchedNames}. Refine your alias patterns to avoid overlap."
        }

        $MatchedTenant = $MatchedTenants[0]

        Write-Host "Matched tenant: $($MatchedTenant.TenantName)" -ForegroundColor Cyan

        # build connection parameters
        $ConnectParams = @{
            TenantId = $MatchedTenant.TenantId
        }

        if ($MatchedTenant.GCCHigh -imatch 'yes|^y$') {
            $ConnectParams['GCCHigh'] = $true
        }

        if ($null -ne $DeviceCode) {
            if ($DeviceCode -eq $true -and $MatchedTenant.DeviceAuthAllowed -notmatch 'yes|^y$') {
                throw ("Device code authentication is not allowed for tenant '$($MatchedTenant.TenantName)'. " +
                       "Set DeviceAuthAllowed to 'yes' in the tenants worksheet to permit it.")
            }
            $ConnectParams['DeviceCode'] = $DeviceCode
        }

        if ($Graph)    { $ConnectParams['Graph']    = $true }
        if ($Exchange) { $ConnectParams['Exchange'] = $true }

        if ($AdditionalScopes) {
            $ConnectParams['AdditionalScopes'] = $AdditionalScopes
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

function Open-IRTTenantsWorksheet {
    <#
    .SYNOPSIS
    Opens the tenants worksheet for editing. Creates it from the template if it doesn't exist.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [string] $TenantFile = $(if ($Global:IRT_Config.TenantsSheetPath) { $Global:IRT_Config.TenantsSheetPath } else { Join-Path $env:APPDATA 'M365IncidentResponseTools\tenants.xlsx' })
    )

    process {

        if (-not ( Test-Path $TenantFile )) {

            $ConfigDir    = Split-Path $TenantFile
            $ModuleRoot   = $MyInvocation.MyCommand.Module.ModuleBase
            $TemplateFile = Join-Path $ModuleRoot 'module_init' 'tenants_TEMPLATE.xlsx'

            if (-not (Test-Path $ConfigDir)) {
                New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
            }

            Copy-Item -Path $TemplateFile -Destination $TenantFile
            Write-Host "Created tenants worksheet file from template: ${TenantFile}" -ForegroundColor Green
        }

        Invoke-Item $TenantFile
    }
}

