#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTServicePrincipal.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Get-IRTServicePrincipal lists every service principal in the
    tenant and resolves each foreign owning tenant to a name with
    Get-IRTTenantOwner. No Graph call is mocked.

    The owner lookup runs with -ErrorAction SilentlyContinue, and a failed lookup
    leaves the owner as a raw tenant GUID. Microsoft's own apps, such as
    Microsoft Graph, are owned by a foreign tenant, so the tests require their
    owner to come back as a name. That needs CrossTenantInformation.ReadBasic.All.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test. Export-Csv is mocked so the tenant name cache in the user's profile
    is left alone.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTServicePrincipal (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTServicePrincipal online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Export-Csv { }

            $script:Rows = @(Get-IRTServicePrincipal)
            $script:GraphRow = $script:Rows |
                Where-Object { $_.AppId -eq '00000003-0000-0000-c000-000000000000' }
        }

        It 'returns the tenant service principals' {
            $script:Rows.Count | Should -BeGreaterThan 0
            $script:Rows.AppId | Should -Contain '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        }

        It 'resolves a foreign owning tenant to a name' {
            $script:GraphRow | Should -Not -BeNullOrEmpty
            $Parsed = [guid]::Empty
            $IsGuid = [guid]::TryParse([string]$script:GraphRow.AppOwner, [ref]$Parsed)
            $IsGuid | Should -BeFalse -Because (
                "the owner of Microsoft Graph must resolve to a name, " +
                "got '$($script:GraphRow.AppOwner)'")
        }
    }
}
