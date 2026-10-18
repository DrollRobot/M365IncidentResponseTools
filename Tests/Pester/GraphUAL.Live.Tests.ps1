#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Start-IRTGraphUAL, Wait-IRTGraphUAL, and Receive-IRTGraphUAL.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. They run one real audit search through the Graph audit search
    API, end to end: Start-IRTGraphUAL submits it, Wait-IRTGraphUAL polls until
    it finishes, and Receive-IRTGraphUAL downloads the records. Nothing that
    talks to Graph is mocked.

    The service schedules these searches in batches, so the run takes about 35
    minutes whatever the range, hence the 'slow' tag. Each run also leaves its
    search jobs in the tenant: the API cannot delete them, and they expire after
    about 30 days.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test. Each of the three functions reports a failed Graph call that way
    and carries on, so without this a failure looks like an empty result.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - IRT_TEST_USER_ID must be set to a valid user GUID (see Tests/.env.ps1).
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Graph audit log search (live)' -Tag 'live', 'integration', 'slow' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Graph audit log search online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_USER_ID not set. Run Tests/.env.ps1 first.'
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:TestUser = Get-MgUser -UserId $env:IRT_TEST_USER_ID -ErrorAction Stop

            $StartParams = @{
                UserObject = $script:TestUser
                Days       = 7
                NoWait     = $true
                Audio      = $false
            }
            $script:Group = Start-IRTGraphUAL @StartParams

            $WaitParams = @{
                Group          = $script:Group.GroupId
                NoReceive      = $true
                Audio          = $false
                TimeoutMinutes = 90
            }
            Wait-IRTGraphUAL @WaitParams

            $ReceiveParams = @{
                Group    = $script:Group.GroupId
                Excel    = $false
                Xml      = $false
                PassThru = $true
            }
            $script:Received = @(Receive-IRTGraphUAL @ReceiveParams | ForEach-Object { $_ })
            $script:Records = @(
                $script:Received | Where-Object { $_ -and -not $_.Metadata -and -not $_.IRTDataGap }
            )
        }

        It 'downloads every job without a gap' {
            $Gaps = @($script:Received | Where-Object { $_.IRTDataGap })
            $Gaps | Should -BeNullOrEmpty -Because 'every job must finish and download'
        }

        It 'returns records from the 7-day window, newest first' {
            if ($script:Records.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the test user had no audit activity in 7 days'
                return
            }
            $WindowStart = (Get-Date).AddDays(-8)
            foreach ($Record in $script:Records) {
                $Record.CreationDate | Should -BeGreaterOrEqual $WindowStart
            }
            $Dates = $script:Records.CreationDate
            $Dates | Should -Be ($Dates | Sort-Object -Descending)
        }
    }
}
