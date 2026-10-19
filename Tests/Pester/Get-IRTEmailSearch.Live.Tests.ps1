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
}
