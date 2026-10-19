#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for New-IRTEmailSearch.

.DESCRIPTION
    These tests require an active IPPS (Security & Compliance) session
    established by Connect-IRT. New-IRTEmailSearch checks the IPPS connection,
    looks up whether the search name is already in use, then creates and starts
    the search.

    Only the reads run against the tenant. New-ComplianceSearch and
    Start-ComplianceSearch are mocked, so no search is created; creating one is a
    write test. The search is named after an existing one, with -Force, so the
    name lookup must find it and pick the next free name. A failed lookup looks
    the same as a free name, so this is the only way to see the lookup work.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (IPPS session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - The test tenant has at least one email search.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'New-IRTEmailSearch (live)' -Tag 'live', 'integration' {

        BeforeAll {
            # the function adds its result to this list; keep the user's own
            $script:SavedSearches = $Global:IRT_EmailSearch

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.IPPS)) {
                throw ('New-IRTEmailSearch online tests require an active IPPS ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            Mock New-ComplianceSearch { [pscustomobject]@{ Identity = $Name } }
            Mock Start-ComplianceSearch { }

            $script:Existing = (Get-ComplianceSearch | Select-Object -First 1).Name
            if (-not $script:Existing) {
                throw ('The test tenant has no email search. Create one with ' +
                    'New-IRTEmailSearch.')
            }

            $Global:IRT_EmailSearch = $null
            $SearchParams = @{
                Start      = (Get-Date).AddDays(-1).ToString('o')
                Subject    = 'IRT live test'
                Name       = $script:Existing
                NamePrefix = ''
                Force      = $true
            }
            $script:Result = New-IRTEmailSearch @SearchParams
        }

        AfterAll {
            $Global:IRT_EmailSearch = $script:SavedSearches
        }

        It 'finds the name in use and picks the next free one' {
            $script:Result.Name | Should -Not -Be $script:Existing
            $script:Result.Name.StartsWith("$($script:Existing) ") | Should -BeTrue
        }

        It 'creates the search under the free name' {
            Should -Invoke New-ComplianceSearch -Times 1 -Exactly -Scope Describe -ParameterFilter {
                $Name -eq $script:Result.Name -and
                $ContentMatchQuery -eq $script:Result.Query
            }
        }

        It 'starts the search' {
            Should -Invoke Start-ComplianceSearch -Times 1 -Exactly -Scope Describe
            $script:Result.Started | Should -BeTrue
        }
    }
}
