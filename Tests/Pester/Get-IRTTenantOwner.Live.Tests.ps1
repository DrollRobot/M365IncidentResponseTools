#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTTenantOwner.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Get-IRTTenantOwner resolves a tenant GUID or domain through OIDC
    discovery and the Graph cross-tenant information API. Neither is mocked.

    A failed Graph lookup is reported as a warning and the function still
    returns a result, built from public endpoints only and without a name. The
    tests therefore require Source to be 'Graph', which needs
    CrossTenantInformation.ReadBasic.All.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test. Export-Csv is mocked so the tenant name cache in the user's profile
    is left alone.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTTenantOwner (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTTenantOwner online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Export-Csv { }

            # Microsoft Services, the owner of Microsoft's first-party apps
            $script:ByGuid = Get-IRTTenantOwner -TenantId 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
            $script:ByDomain = Get-IRTTenantOwner -TenantId 'microsoft.com'
        }

        It 'resolves a tenant GUID through Graph' {
            $script:ByGuid.Exists | Should -BeTrue
            $script:ByGuid.Source | Should -Be 'Graph'
            $script:ByGuid.DisplayName | Should -Not -BeNullOrEmpty
            $script:ByGuid.DefaultDomain | Should -Not -BeNullOrEmpty
        }

        It 'resolves a domain to its tenant GUID through Graph' {
            $script:ByDomain.Source | Should -Be 'Graph'
            $Parsed = [guid]::Empty
            [guid]::TryParse($script:ByDomain.TenantId, [ref]$Parsed) | Should -BeTrue
            $script:ByDomain.DisplayName | Should -Not -BeNullOrEmpty
        }
    }
}
