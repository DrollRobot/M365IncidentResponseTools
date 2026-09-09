function New-TenantSheet {
    <#
    .SYNOPSIS
    Creates a new tenants worksheet containing the standard columns and sample rows.

    .DESCRIPTION
    Generates the tenants.xlsx workbook that Connect-IRTTenant reads. The worksheet
    holds four columns -- TenantName, Aliases, TenantId and PasswordURLs -- plus three
    sample rows showing the expected format for each.

    The workbook is generated here in code rather than copied from a bundled .xlsx
    template. Changing the column layout is an edit to the row definitions below, which
    reviews as a readable diff, instead of a hand edit to an opaque binary file.

    The parent directory is created when it does not already exist. An existing file at
    Path is never overwritten; callers are expected to test for the file first.

    .PARAMETER Path
    Full path of the workbook to create.

    .EXAMPLE
    New-TenantSheet -Path "$env:APPDATA\M365IncidentResponseTools\tenants.xlsx"

    Creates a starter tenants worksheet in the module's configuration directory.

    .OUTPUTS
    System.IO.FileInfo for the workbook that was created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name

        # Sample rows. Adding, removing or renaming a property here changes the
        # worksheet layout; Connect-IRTTenant reads these column names.
        $SampleTenants = @(
            [PSCustomObject]@{
                TenantName   = 'Contoso Inc'
                Aliases      = 'Contoso|ContosoInc|contoso'
                TenantId     = '00000000-0000-0000-0000-000000000000'
                PasswordURLs = ''
            }
            [PSCustomObject]@{
                TenantName   = 'Fabrikam LLC'
                Aliases      = 'Fabrikam|FabrikamLLC|fab'
                TenantId     = '11111111-1111-1111-1111-111111111111'
                PasswordURLs = ''
            }
            [PSCustomObject]@{
                TenantName   = 'GovClient'
                Aliases      = 'GovClient|GovC'
                TenantId     = '22222222-2222-2222-2222-222222222222'
                PasswordURLs = ''
            }
        )
    }

    process {

        if (Test-Path -LiteralPath $Path) {
            throw "Tenants worksheet already exists: ${Path}"
        }

        if (-not $PSCmdlet.ShouldProcess($Path, 'Create tenants worksheet')) {
            return
        }

        $ParentDir = Split-Path -Path $Path -Parent
        if ($ParentDir -and -not (Test-Path -LiteralPath $ParentDir)) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: creating parent directory '${ParentDir}'")
            $null = New-Item -ItemType Directory -Path $ParentDir -Force
        }

        $RowCount = ($SampleTenants | Measure-Object).Count
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: writing ${RowCount} sample rows to '${Path}'")

        $ExcelParams = @{
            Path          = $Path
            WorksheetName = 'tenants'
            TableName     = 'Tenants'
            TableStyle    = 'Medium15'
            AutoSize      = $true
            PassThru      = $true
        }
        $Package = $SampleTenants | Export-Excel @ExcelParams
        Close-ExcelPackage -ExcelPackage $Package

        Write-PSFMessage -Level 8 -Message "${FunctionName}: created '${Path}'"

        Get-Item -LiteralPath $Path
    }
}
