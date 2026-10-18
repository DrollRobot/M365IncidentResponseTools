#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTTeamsExternalDomain.

.DESCRIPTION
    These tests require active Exchange Online and Microsoft Graph sessions
    established by Connect-IRT. Get-IRTTeamsExternalDomain splits the range into
    Sunday-to-Saturday weeks, runs a Unified Audit Log search for each, and saves
    one CLIXML file per week. The tenant domain in the file names comes from
    Graph. Nothing is mocked except Write-IRT, and the files are written to a
    folder under TestDrive.

    A short range keeps the run to one or two weekly searches. The test tenant
    may have no Teams activity with outside parties, so the tests check that
    every week was searched completely rather than that records came back.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Exchange and Graph sessions active).
        Tests.ps1 runs Connect-IRT.Tests.ps1 first and only proceeds here on
        success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTTeamsExternalDomain (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Exchange -and
                    $Global:IRT_Session.Graph)) {
                throw ('Get-IRTTeamsExternalDomain online tests require active Exchange ' +
                    'Online and Graph sessions. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:OutDir = Join-Path -Path $TestDrive -ChildPath 'TeamsExternal'
            $null = New-Item -ItemType Directory -Path $script:OutDir
            Get-IRTTeamsExternalDomain -Days 2 -Path $script:OutDir

            $script:Files = @(
                Get-ChildItem -Path $script:OutDir -Filter 'TeamsExternalDomains_*.xml'
            )
            $script:Metadata = @(
                $script:Files | ForEach-Object {
                    @(Import-Clixml -Path $_.FullName)[0]
                }
            )
        }

        It 'writes a file for every week searched' {
            $script:Files.Count | Should -BeGreaterThan 0
        }

        It 'names each file after the tenant domain' {
            $Domain = Get-DefaultDomain
            foreach ($File in $script:Files) {
                $File.Name | Should -BeLike "TeamsExternalDomains_${Domain}_*"
            }
        }

        It 'searches every week completely' {
            foreach ($Entry in $script:Metadata) {
                $Entry.Metadata | Should -BeTrue
                $Entry.DataGapCount | Should -Be 0 -Because (
                    "week of $($Entry.WeekStart) must have no DATA MISSING markers")
            }
        }
    }
}
