#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the Get-IRTGraphDefaultScope scope list.

.DESCRIPTION
    Get-IRTGraphDefaultScope is the single source of truth for the default
    Graph delegated scope set shared by Get-IRTAccessToken and
    Connect-IRTGraph. These tests pin the contract its consumers rely on:
    plain scope names (no resource-URL prefix), no duplicates, and the
    presence of scopes that other module functions depend on.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTGraphDefaultScope' -Tag 'unit' {

        BeforeAll {
            $script:Result = Get-IRTGraphDefaultScope
        }

        It 'returns a non-trivial list of scope names' {
            $script:Result.Count | Should -BeGreaterThan 30
        }

        It 'contains no duplicates' {
            ($script:Result | Select-Object -Unique).Count |
                Should -Be $script:Result.Count
        }

        It 'returns plain scope names without a resource-URL prefix' {
            $Prefixed = @($script:Result | Where-Object { $_ -like 'http*' })
            $Prefixed | Should -HaveCount 0
        }

        It 'includes scopes the module depends on' {
            $script:Result | Should -Contain 'AuditLog.Read.All'
            $script:Result | Should -Contain 'Directory.ReadWrite.All'
            $script:Result | Should -Contain 'User.ReadWrite.All'
        }
    }
}
