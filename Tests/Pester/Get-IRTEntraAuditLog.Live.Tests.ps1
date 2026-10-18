#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTEntraAuditLog and Show-IRTEntraAuditLog.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Get-IRTEntraAuditLog pulls the tenant's directory audit logs and
    hands them to Show-IRTEntraAuditLog, which resolves the user, group, role,
    and service principal IDs in them to names and writes the workbook. Nothing
    is mocked except Write-IRT: the workbook is really written, into a folder
    under TestDrive.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - The test tenant has directory audit activity in the last 7 days. Each
        live run produces some, such as consent and sign-in changes.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTEntraAuditLog (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTEntraAuditLog online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            # Show-IRTEntraAuditLog writes into the current folder
            $script:OutDir = Join-Path -Path $TestDrive -ChildPath 'EntraAudit'
            $null = New-Item -ItemType Directory -Path $script:OutDir
            Push-Location -Path $script:OutDir
            try {
                Get-IRTEntraAuditLog -AllUsers -Days 7 -Open $false -Xml $false
            }
            finally {
                Pop-Location
            }
            $script:Files = @(
                Get-ChildItem -Path $script:OutDir -Filter 'EntraAuditLogs_*.xlsx'
            )
        }

        It 'writes one workbook' {
            $script:Files.Count | Should -Be 1
        }

        It 'fills the workbook with audit rows' {
            # row 1 holds the title, row 2 the column headers
            $ImportParams = @{
                Path          = $script:Files[0].FullName
                WorksheetName = 'EntraAudit'
                StartRow      = 2
            }
            $Rows = @(Import-Excel @ImportParams)
            $Rows.Count | Should -BeGreaterThan 0
        }
    }
}
