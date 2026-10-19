#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTEmailSearch.

.DESCRIPTION
    These tests require an active IPPS (Security & Compliance) session
    established by Connect-IRT. Get-IRTEmailSearch lists the tenant's email
    searches, opens the one picked, and runs actions on it from a menu.

    The menu answers are fed to Read-Host in order: pick a completed search with
    hits, show its results, go back to the list, and quit. That covers listing
    the searches, reading one, and reading its results. The results are also
    saved as a workbook, under TestDrive. Nothing is mocked except Write-IRT and
    Read-Host.

    The actions that change the tenant (start, purge, delete) are mocked to
    throw, so a wrong answer can't change it. The wait actions are not run; they
    only repeat reads already covered, and play a sound.

    A second block, tagged 'destructive','remote', purges through the menu. It
    runs only through '.\Tests.ps1 Destructive'.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (IPPS session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - The test tenant has at least one completed email search with hits.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTEmailSearch (live)' -Tag 'live', 'integration' {

        BeforeAll {
            # the function caches searches here and saves the workbook in the
            # current folder, without opening it when OpenSpreadsheets is off
            $script:SavedDetail = $Global:IRT_EmailSearchDetail
            $script:SavedOpenSpreadsheets = $Global:IRT_Config.OpenSpreadsheets

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.IPPS)) {
                throw ('Get-IRTEmailSearch online tests require an active IPPS ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            # a wrong menu answer must not change the tenant
            Mock Start-ComplianceSearch { throw 'Start-ComplianceSearch must not run.' }
            Mock Remove-ComplianceSearch { throw 'Remove-ComplianceSearch must not run.' }
            Mock New-ComplianceSearchAction {
                throw 'New-ComplianceSearchAction must not run.'
            }

            # the same list, in the same order, the function shows
            $Searches = @(Get-ComplianceSearch | Sort-Object LastModifiedTime -Descending)
            $script:Index = $null
            for ($i = 0; $i -lt $Searches.Count; $i++) {
                if ($Searches[$i].Status -ne 'Completed') { continue }
                $Detail = Get-ComplianceSearch -Identity $Searches[$i].Name -ErrorAction Stop
                if ($Detail.Items -gt 0) {
                    $script:Index = $i + 1
                    $script:SearchName = $Detail.Name
                    break
                }
            }
            if (-not $script:Index) {
                throw ('The test tenant has no completed email search with hits. Create ' +
                    'one with New-IRTEmailSearch and wait for it to complete.')
            }

            # pick the search, show results, back to the list, quit
            $script:Answers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @("$($script:Index)", '3', 'B', 'Q')) {
                $script:Answers.Enqueue($Answer)
            }
            Mock Read-Host { $script:Answers.Dequeue() }

            $Global:IRT_EmailSearchDetail = $null
            $Global:IRT_Config.OpenSpreadsheets = $false
            Push-Location -Path $TestDrive
            $script:Pushed = $true

            Get-IRTEmailSearch
        }

        AfterAll {
            if ($script:Pushed) { Pop-Location }
            $Global:IRT_EmailSearchDetail = $script:SavedDetail
            $Global:IRT_Config.OpenSpreadsheets = $script:SavedOpenSpreadsheets
        }

        It 'uses every menu answer' {
            $script:Answers.Count | Should -Be 0
        }

        It 'opens the picked search' {
            $Global:IRT_EmailSearchDetail[$script:SearchName].Status | Should -Be 'Completed'
        }

        It 'reports the mailboxes with hits' {
            Should -Invoke Write-IRT -Times 1 -Exactly -Scope Describe -ParameterFilter {
                $Message -like '* mailbox(es) with hits, * item(s) total.'
            }
        }

        It 'saves the results workbook' {
            $Files = @(Get-ChildItem -Path $TestDrive -Filter 'EmailSearchResults_*.xlsx')
            $Files | Should -HaveCount 1
            # row 1 is the title
            $Rows = @(Import-Excel -Path $Files[0].FullName -StartRow 2)
            $Rows.Count | Should -BeGreaterThan 0
            $Rows[0].Mailbox | Should -Not -BeNullOrEmpty
        }

        It 'does not change the tenant' {
            Should -Invoke Start-ComplianceSearch -Times 0 -Exactly -Scope Describe
            Should -Invoke Remove-ComplianceSearch -Times 0 -Exactly -Scope Describe
            Should -Invoke New-ComplianceSearchAction -Times 0 -Exactly -Scope Describe
        }
    }

    # Purges through the menu. Start and delete are covered by the New-IRTEmailSearch
    # test, which makes the same calls. The search only covers the disposable test
    # user's mailbox, and looks for a random subject, so the purge has nothing to
    # delete; it still needs the 'Search And Purge' role to be accepted. Waiting for
    # the search to finish takes a few minutes.
    Describe 'Get-IRTEmailSearch purge (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote', 'slow'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never deletes a search left over
            # from another file.
            $script:PurgeSearchName = $null
            $script:SavedDetail = $Global:IRT_EmailSearchDetail

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph -and
                    $Global:IRT_Session.IPPS)) {
                throw ('Get-IRTEmailSearch online tests require active Graph and IPPS ' +
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
            $Mailbox = (Get-MgUser @GetParams).UserPrincipalName

            $Token = (New-Guid).Guid
            $NewParams = @{
                Name              = "IRT live purge test $Token"
                ExchangeLocation  = $Mailbox
                ContentMatchQuery = "subject:`"$Token`""
                ErrorAction       = 'Stop'
            }
            $null = New-ComplianceSearch @NewParams
            $script:PurgeSearchName = $NewParams.Name
            Start-ComplianceSearch -Identity $script:PurgeSearchName -ErrorAction Stop

            # purge needs a completed search
            $Deadline = (Get-Date).AddMinutes(10)
            do {
                Start-Sleep -Seconds 10
                $Search = Get-ComplianceSearch -Identity $script:PurgeSearchName -ErrorAction Stop
                Write-Host "Search status: $($Search.Status)"
            } while ($Search.Status -ne 'Completed' -and (Get-Date) -lt $Deadline)
            if ($Search.Status -ne 'Completed') {
                throw "Search '$($script:PurgeSearchName)' did not complete in 10 minutes."
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            # purge, soft delete, confirm, quit
            $script:Answers = [System.Collections.Generic.Queue[string]]::new()
            foreach ($Answer in @('4', '1', 'y', 'Q')) {
                $script:Answers.Enqueue($Answer)
            }
            Mock Read-Host { $script:Answers.Dequeue() }

            $Global:IRT_EmailSearchDetail = $null
            Get-IRTEmailSearch -Name $script:PurgeSearchName

            $ActionParams = @{
                Identity    = "$($script:PurgeSearchName)_Purge"
                ErrorAction = 'Ignore'
            }
            $script:Purge = Get-ComplianceSearchAction @ActionParams
        }

        AfterAll {
            $Global:IRT_EmailSearchDetail = $script:SavedDetail
            if ($script:PurgeSearchName) {
                # a search cannot be deleted while its purge is still running
                $ActionParams = @{
                    Identity    = "$($script:PurgeSearchName)_Purge"
                    ErrorAction = 'Ignore'
                }
                $Deadline = (Get-Date).AddMinutes(5)
                while (($Purge = Get-ComplianceSearchAction @ActionParams) -and
                    $Purge.Status -ne 'Completed' -and (Get-Date) -lt $Deadline) {
                    Start-Sleep -Seconds 10
                }
                if ($Purge) {
                    Remove-ComplianceSearchAction @ActionParams -Confirm:$false
                }
                Remove-ComplianceSearch -Identity $script:PurgeSearchName -Confirm:$false
            }
        }

        It 'uses every menu answer' {
            $script:Answers.Count | Should -Be 0
        }

        It 'submits the purge' {
            $script:Purge | Should -Not -BeNullOrEmpty
        }
    }
}
