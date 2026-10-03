#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the Get-IRTGraphDefaultScope scope list.

.DESCRIPTION
    Get-IRTGraphDefaultScope is the single source of truth for the default
    Graph delegated scope set shared by Get-IRTAccessToken and
    Connect-IRTGraph. These tests pin the contract its consumers rely on:
    plain scope names (no resource-URL prefix) and no duplicates.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTGraphDefaultScope' -Tag 'unit' {

        BeforeAll {
            $script:Result = Get-IRTGraphDefaultScope
        }

        It 'returns a non-trivial list of scope names' {
            $script:Result.Count | Should -BeGreaterThan 20
        }

        It 'contains no duplicates' {
            ($script:Result | Select-Object -Unique).Count |
                Should -Be $script:Result.Count
        }

        It 'returns plain scope names without a resource-URL prefix' {
            $Prefixed = @($script:Result | Where-Object { $_ -like 'http*' })
            $Prefixed | Should -HaveCount 0
        }
    }
}
