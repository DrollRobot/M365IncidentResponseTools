#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Reset-IRTUserPassword.

.DESCRIPTION
    These tests change the test tenant: they set a new random password on the
    disposable test user. The old password is not put back; nobody signs in as
    that user. They run only through '.\Tests.ps1 Destructive', after
    Tests\Confirm-RemoteDisposable.ps1 confirms the tenant is marked disposable.

    Every password mode makes the same Update-MgUser passwordProfile call, so
    only -RandomCharacters is run. The reset is checked through
    lastPasswordChangeDateTime, which Entra moves forward on every change.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - An active Graph session to the test tenant. PreTests.ps1 opens one for
        Destructive runs.
      - IRT_TEST_DISPOSABLE_USER_ID names a cloud-only user that is not a real
        person's account (see Tests/.env.ps1.example). A synced user would make
        Reset-IRTUserPassword warn about local AD, which fails the test.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Reset-IRTUserPassword (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Reset-IRTUserPassword online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_DISPOSABLE_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID not set. Run Tests/.env.ps1 first.'
            }
            if ($env:IRT_TEST_DISPOSABLE_USER_ID -eq $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID must not be the same user as IRT_TEST_USER_ID.'
            }

            Import-IRTModule -Name 'Microsoft.Graph.Users'
            $GetParams = @{
                UserId   = $env:IRT_TEST_DISPOSABLE_USER_ID
                Property = @(
                    'Id'
                    'LastPasswordChangeDateTime'
                    'OnPremisesSyncEnabled'
                    'UserPrincipalName'
                )
            }
            $script:User = Get-MgUser @GetParams
            if ($script:User.UserPrincipalName -eq (Get-MgContext).Account) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID is the signed-in account.'
            }
            if ($script:User.OnPremisesSyncEnabled) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID must be a cloud-only user, not synced.'
            }
            $script:ChangedBefore = $script:User.LastPasswordChangeDateTime

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $null = Reset-IRTUserPassword -UserObject $script:User -RandomCharacters

            $script:After = Get-MgUser @GetParams
        }

        It 'sets a new password' {
            $script:After.LastPasswordChangeDateTime |
                Should -BeGreaterThan $script:ChangedBefore
        }
    }
}
