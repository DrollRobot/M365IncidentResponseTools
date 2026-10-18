#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Show-IRTServicePrincipal.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Show-IRTServicePrincipal prints five sections for a service
    principal: its properties, delegated permission grants, app role assignments,
    directory role memberships, and the principals assigned to it. Each section
    is a separate Graph call, and none is mocked.

    Every section catches its own failure and reports it with an Error-level
    Write-IRT message, so Write-IRT is mocked to print every message and fail
    the test on Error-level ones. Format-Table is mocked to capture the rows each
    section would print.

    The target is the Microsoft Graph Command Line Tools app. Connect-IRT signs
    in with it, so it always holds a tenant-wide delegated permission grant,
    which makes the grant section print real data. Reading grants depends on
    DelegatedPermissionGrant.Read.All (or Directory.Read.All).

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Show-IRTServicePrincipal (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Show-IRTServicePrincipal online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $SpFilter = "appId eq '14d82eec-204b-4c2f-b7e8-296a70dab67e'"
            $script:Sp = Get-MgServicePrincipal -Filter $SpFilter -ErrorAction Stop

            $script:Printed = [System.Collections.Generic.List[object]]::new()
            Mock Format-Table { $script:Printed.Add($InputObject) }

            Show-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            # grant rows are the only ones with a Scope column
            $script:Grants = @($script:Printed | Where-Object {
                    $_.PSObject.Properties.Name -contains 'Scope'
                })
        }

        It 'prints the delegated permission grants' {
            $script:Grants.Count | Should -BeGreaterThan 0
        }

        It 'prints the grant Connect-IRT signs in with' {
            # the tenant-wide grant carries the default scope set
            $AdminGrant = $script:Grants | Where-Object { $_.ConsentType -eq 'AllPrincipals' }
            $AdminGrant | Should -Not -BeNullOrEmpty
            $AdminGrant.Scope | Should -Match 'Directory\.Read\.All'
        }
    }
}
