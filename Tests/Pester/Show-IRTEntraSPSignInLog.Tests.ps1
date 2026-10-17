#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the workbook Show-IRTEntraSPSignInLog writes.

.DESCRIPTION
    Builds one sign-in log in the shape Get-IRTEntraSPSignInLog returns, with a
    metadata entry first, and lets the real Export-Excel write it to Pester's
    TestDrive. IP enrichment and opening the workbook are turned off.

-- IP addresses ---------------------------------------------------------

    Export-Excel saves any value .NET reads as a full URL as a link. An IPv6
    address whose first block starts with a letter, such as fd00::, reads as a
    URL scheme, so these addresses were saved as links. The IpAddress cell must
    hold plain text.

    Rows are a fixed height, so a wrapped IP address showed only one line of
    it. The IpAddress cell must not wrap.
#>

Describe 'Show-IRTEntraSPSignInLog workbook' -Tag 'integration', 'regression' {

    BeforeAll {
        $Mod = 'M365IncidentResponseTools'
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod

        $script:IpAddress = 'fd00::dd4:6b1f:200:a63:8400'
        $SheetName = 'SPSignInLogs'
        $FileName = Join-Path -Path $TestDrive -ChildPath $SheetName

        $Log = [System.Collections.Generic.List[psobject]]::new()
        $Log.Add([pscustomobject]@{
                Metadata       = $true
                FileName       = $FileName
                FileNamePrefix = $SheetName
                Title          = 'Service principal sign-in logs'
            })
        $Log.Add([pscustomobject]@{
                CreatedDateTime       = [datetime]'2026-10-15T12:00:00Z'
                ServicePrincipalName  = 'Contoso Backup'
                AppDisplayName        = 'Contoso Backup'
                ResourceDisplayName   = 'Microsoft Graph'
                Status                = [pscustomobject]@{ ErrorCode = 0 }
                IpAddress             = $script:IpAddress
                Location              = [pscustomobject]@{
                    City            = 'Dublin'
                    State           = 'Dublin'
                    CountryOrRegion = 'IE'
                }
                CorrelationId         = '11111111-1111-1111-1111-111111111111'
                UniqueTokenIdentifier = 'token-1'
            })

        Show-IRTEntraSPSignInLog -Log $Log -IpInfo $false -Open $false

        $Package = Open-ExcelPackage -Path "${FileName}.xlsx"
        $Table = $Package.Workbook.Worksheets[$SheetName].Tables[0]
        $Id = ($Table.Columns | Where-Object { $_.Name -eq 'IpAddress' }).Id
        $Row = $Table.Address.Start.Row + 1
        $Column = $Table.Address.Start.Column + $Id - 1
        $Cell = $Package.Workbook.Worksheets[$SheetName].Cells[$Row, $Column]
        $script:CellValue = $Cell.Value
        $script:CellLink = $Cell.Hyperlink
        $script:CellWrap = $Cell.Style.WrapText
        Close-ExcelPackage -ExcelPackage $Package -NoSave
    }

    It 'writes an IPv6 address that starts with a letter as text' {
        $script:CellValue | Should -Be $script:IpAddress
    }

    It 'does not save an IPv6 address that starts with a letter as a link' {
        $script:CellLink | Should -BeNullOrEmpty
    }

    It 'does not wrap the IP address' {
        $script:CellWrap | Should -BeFalse
    }
}
