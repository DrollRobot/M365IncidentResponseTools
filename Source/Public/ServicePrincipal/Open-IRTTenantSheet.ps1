function Open-IRTTenantSheet {
    <#
    .SYNOPSIS
    Opens the tenants worksheet for editing. Creates it from the template if it doesn't exist.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Open-IRTTenantWorksheet', 'OpenIRTTenantWorksheet',
        'OpenIRTTenantSheet', 'IRTTenantSheet'
    )]
    [CmdletBinding()]
    param (
        [string] $TenantFile
    )

    begin {
        if (-not $TenantFile) {
            $TenantFile = $Global:IRT_Config.TenantsSheetPath
        }
    }

    process {

        if (-not ( Test-Path $TenantFile )) {

            $ConfigDir = Split-Path $TenantFile
            $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
            $TemplateParams = @{
                Path                = $ModuleRoot
                ChildPath           = 'Data'
                AdditionalChildPath = 'TenantsTemplate.xlsx'
            }
            $TemplateFile = Join-Path @TemplateParams

            if (-not (Test-Path $ConfigDir)) {
                $null = New-Item -ItemType Directory -Path $ConfigDir -Force
            }

            Copy-Item -Path $TemplateFile -Destination $TenantFile
            Write-IRT "Created tenants worksheet file from template: ${TenantFile}"
        }

        Invoke-Item $TenantFile
    }
}