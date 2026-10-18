#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Find-IRTServicePrincipal.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Find-IRTServicePrincipal fetches every service principal in the
    tenant and filters them locally. The Graph call is not mocked.

    The search targets the Microsoft Graph Command Line Tools app, which
    Connect-IRT signs in with, so it is always present in the test tenant.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Find-IRTServicePrincipal (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Find-IRTServicePrincipal online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:AppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Graph CLI Tools
            $script:Found = @(Find-IRTServicePrincipal -Search $script:AppId -Script)
        }

        It 'finds exactly one service principal for the app ID' {
            $script:Found.Count | Should -Be 1
        }

        It 'returns the service principal for that app' {
            $script:Found[0].AppId | Should -Be $script:AppId
            $script:Found[0].Id | Should -Not -BeNullOrEmpty
        }
    }
}
