#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-LocalAdSyncService.

.DESCRIPTION
    The ADSync service runs only on Windows, and Get-Service exists only there. The
    helper returns nothing where Get-Service is missing, so the AD functions that look
    for a local sync service work on every platform. Off Windows a Get-Service stub is
    created so the found-service case can still be mocked.

-- Get-LocalAdSyncService --------------------------------------------------

    'returns nothing when Get-Service does not exist'
        Calling the missing command threw CommandNotFoundException on Linux and macOS.

    'returns the adsync service when this device runs it'

    'returns nothing when this device does not run adsync'
#>

BeforeAll {
    $script:StubbedGetService = -not (Get-Command -Name 'Get-Service' -ErrorAction Ignore)
    if ($script:StubbedGetService) {
        function global:Get-Service {
            [CmdletBinding()]
            param($Name)
            $null = $Name
        }
    }
}

AfterAll {
    if ($script:StubbedGetService) {
        Remove-Item -Path 'Function:\Get-Service' -ErrorAction SilentlyContinue
    }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Get-LocalAdSyncService' -Tag 'unit' {

        It 'returns nothing when Get-Service does not exist' -Tag 'regression' {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'Get-Service' }
            Mock Get-Service { [pscustomobject]@{ Name = 'adsync' } }
            Get-LocalAdSyncService | Should -BeNullOrEmpty
            Should -Invoke Get-Service -Times 0 -Exactly
        }

        It 'returns the adsync service when this device runs it' {
            Mock Get-Service { [pscustomobject]@{ Name = 'adsync' } } -ParameterFilter {
                $Name -eq 'adsync'
            }
            (Get-LocalAdSyncService).Name | Should -Be 'adsync'
        }

        It 'returns nothing when this device does not run adsync' {
            Mock Get-Service { } -ParameterFilter { $Name -eq 'adsync' }
            Get-LocalAdSyncService | Should -BeNullOrEmpty
        }
    }
}
