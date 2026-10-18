#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTEntraSPSignInLog.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. The sign-in log query goes to the real Graph endpoint through
    the shared Invoke-IRTSignInLogQuery engine.

    Show-IRTEntraSPSignInLog is mocked to capture the records instead of writing
    a workbook. Write-IRT is mocked to print every message, and Error-level
    messages fail the test: the engine reports a chunk it gave up on that way,
    and that chunk's records are otherwise missing without a trace.

    The first context pulls 7 days for every service principal. The second
    repeats the pull for one service principal seen in the first, so it skips
    when the tenant had no service principal sign-ins that week.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTEntraSPSignInLog (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTEntraSPSignInLog online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Captured = $null
            Mock Show-IRTEntraSPSignInLog { param($Logs) $script:Captured = $Logs }

            $script:BaseParams = @{
                Days              = 7
                ChunkDays         = 7
                ChunkDelaySeconds = 0
                Excel             = $true
                Xml               = $false
            }
        }

        # -------------------------------------------------------------------
        Context '-AllServicePrincipals, 7-day query' {

            BeforeAll {
                $Params = $script:BaseParams.Clone()
                $Params['AllServicePrincipals'] = $true
                $script:Captured = $null
                Get-IRTEntraSPSignInLog @Params
                $script:AllLogs = @(
                    $script:Captured | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns only service principal sign-ins' {
                if ($script:AllLogs.Count -eq 0) {
                    Set-ItResult -Skipped -Because 'no service principal sign-ins in 7 days'
                    return
                }
                foreach ($Entry in $script:AllLogs) {
                    $Entry.ServicePrincipalId | Should -Not -BeNullOrEmpty
                }
            }

            It 'all records fall within the 7-day window' {
                $WindowStart = [datetime]::UtcNow.AddDays(-8)
                foreach ($Entry in $script:AllLogs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $WindowStart
                }
            }
        }

        # -------------------------------------------------------------------
        Context '-ServicePrincipalObject, one service principal' {

            BeforeAll {
                $script:Target = $script:AllLogs | Select-Object -First 1
                $script:OneLogs = @()
                if ($script:Target) {
                    $Params = $script:BaseParams.Clone()
                    $Params['ServicePrincipalObject'] = [pscustomobject]@{
                        Id          = $script:Target.ServicePrincipalId
                        DisplayName = $script:Target.ServicePrincipalName
                    }
                    $script:Captured = $null
                    Get-IRTEntraSPSignInLog @Params
                    $script:OneLogs = @(
                        $script:Captured | Where-Object { $_ -and -not $_.Metadata }
                    )
                }
            }

            It 'returns sign-ins for that service principal only' {
                if (-not $script:Target) {
                    Set-ItResult -Skipped -Because 'no service principal sign-ins in 7 days'
                    return
                }
                $script:OneLogs.Count | Should -BeGreaterThan 0
                foreach ($Entry in $script:OneLogs) {
                    $Entry.ServicePrincipalId | Should -Be $script:Target.ServicePrincipalId
                }
            }
        }
    }
}
