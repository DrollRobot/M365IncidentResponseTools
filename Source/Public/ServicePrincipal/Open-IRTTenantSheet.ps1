function Open-IRTTenantSheet {
    <#
    .SYNOPSIS
    Opens the tenants worksheet for editing. Creates it if it doesn't exist.

    .DESCRIPTION
    Opens the tenants worksheet that Connect-IRTTenant reads. When the file is not
    present it is generated first, with the standard columns and a few sample rows
    showing the expected format, then opened in the default handler for .xlsx files.

    .PARAMETER TenantFile
    Path to the tenants worksheet. Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

    .EXAMPLE
    ```powershell
    Open-IRTTenantSheet
    ```
    Opens the tenants worksheet, generating it first if this is the first run.

    .EXAMPLE
    ```powershell
    Open-IRTTenantSheet -TenantFile 'C:\Cases\tenants.xlsx'
    ```
    Opens a tenants worksheet stored outside the default configuration directory.

    .OUTPUTS
    None. The worksheet is opened in the default application for .xlsx files.

    .NOTES
    Version: 1.1.0
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
        $FunctionName = $MyInvocation.MyCommand.Name

        if (-not $TenantFile) {
            $TenantFile = $Global:IRT_Config.TenantsSheetPath
        }
    }

    process {

        if (-not (Test-Path -LiteralPath $TenantFile)) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: no worksheet at '${TenantFile}', generating one")
            $null = New-TenantSheet -Path $TenantFile
            Write-IRT "Created tenants worksheet: ${TenantFile}"
        }

        Write-PSFMessage -Level 8 -Message "${FunctionName}: opening '${TenantFile}'"
        Invoke-Item $TenantFile
    }
}
