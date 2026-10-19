#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for New-IRTEmailSearch.

.DESCRIPTION
    These tests require an active IPPS (Security & Compliance) session
    established by Connect-IRT. New-IRTEmailSearch checks the IPPS connection,
    looks up whether the search name is already in use, then creates and starts
    the search.

    In the first block only the reads run against the tenant. New-ComplianceSearch
    and Start-ComplianceSearch are mocked, so no search is created. The second
    block, tagged 'destructive','remote', creates a real search and deletes it;
    it runs only through '.\Tests.ps1 Destructive'.

    The first block's search is named after an existing one, with -Force, so the
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

    # Creates and starts a real search, then deletes it. Deleting it also covers
    # Get-IRTEmailSearch's delete, which makes the same Remove-ComplianceSearch call.
    # The search only covers the disposable test user's mailbox, and looks for a
    # random subject, so it matches nothing.
    Describe 'New-IRTEmailSearch creates a search (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never deletes a search left over
            # from another file.
            $script:CreatedName = $null
            $script:SavedSearches = $Global:IRT_EmailSearch

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph -and
                    $Global:IRT_Session.IPPS)) {
                throw ('New-IRTEmailSearch online tests require active Graph and IPPS ' +
                    'sessions. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_DISPOSABLE_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID not set. Run Tests/.env.ps1 first.'
            }

            Import-IRTModule -Name 'Microsoft.Graph.Users'
            $GetParams = @{
                UserId   = $env:IRT_TEST_DISPOSABLE_USER_ID
                Property = 'Id', 'UserPrincipalName'
            }
            $script:Mailbox = (Get-MgUser @GetParams).UserPrincipalName

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $Token = (New-Guid).Guid
            $Global:IRT_EmailSearch = $null
            $SearchParams = @{
                Start            = (Get-Date).AddDays(-1).ToString('o')
                Subject          = $Token
                Name             = "IRT live test $Token"
                NamePrefix       = ''
                ExchangeLocation = $script:Mailbox
            }
            $script:Result = New-IRTEmailSearch @SearchParams
            $script:CreatedName = $script:Result.Name

            $script:Search = Get-ComplianceSearch -Identity $script:CreatedName -ErrorAction Stop
        }

        AfterAll {
            $Global:IRT_EmailSearch = $script:SavedSearches
            if ($script:CreatedName) {
                $StopParams = @{
                    Identity    = $script:CreatedName
                    Confirm     = $false
                    ErrorAction = 'Ignore'
                }
                Stop-ComplianceSearch @StopParams
                Remove-ComplianceSearch -Identity $script:CreatedName -Confirm:$false
            }
        }

        It 'creates the search' {
            $script:Search.ContentMatchQuery | Should -Be $script:Result.Query
            $script:Search.ExchangeLocation | Should -Contain $script:Mailbox
        }

        It 'starts the search' {
            $script:Result.Started | Should -BeTrue
            $script:Search.Status | Should -Not -Be 'NotStarted'
        }
    }
}
