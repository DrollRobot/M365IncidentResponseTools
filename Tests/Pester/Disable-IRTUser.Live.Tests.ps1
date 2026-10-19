#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Disable-IRTUser.

.DESCRIPTION
    These tests change the test tenant: they disable the disposable test user
    and sign it out everywhere, then put its enabled state back. They run only
    through '.\Tests.ps1 Destructive', after Tests\Confirm-RemoteDisposable.ps1
    confirms the tenant is marked disposable.

    The user is enabled first if needed, so disabling it is a real change. The
    sign-out is checked through signInSessionsValidFromDateTime, which Entra
    moves forward when sessions are revoked.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - An active Graph session to the test tenant. PreTests.ps1 opens one for
        Destructive runs.
      - IRT_TEST_DISPOSABLE_USER_ID names a cloud-only user that is not a real
        person's account (see Tests/.env.ps1.example). A synced user would make
        Disable-IRTUser warn about local AD, which fails the test.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Disable-IRTUser (live)' -Tag 'live', 'integration', 'destructive', 'remote' {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear these first, so AfterAll never restores a user left over
            # from another file.
            $script:User = $null
            $script:WasEnabled = $null

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Disable-IRTUser online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_DISPOSABLE_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID not set. Run Tests/.env.ps1 first.'
            }
            if ($env:IRT_TEST_DISPOSABLE_USER_ID -eq $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID must not be the same user as IRT_TEST_USER_ID.'
            }

            Import-IRTModule -Name 'Microsoft.Graph.Users'
            $script:UserProperties = @(
                'AccountEnabled'
                'Id'
                'OnPremisesSyncEnabled'
                'SignInSessionsValidFromDateTime'
                'UserPrincipalName'
            )
            $GetParams = @{
                UserId   = $env:IRT_TEST_DISPOSABLE_USER_ID
                Property = $script:UserProperties
            }
            $script:User = Get-MgUser @GetParams
            if ($script:User.UserPrincipalName -eq (Get-MgContext).Account) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID is the signed-in account.'
            }
            if ($script:User.OnPremisesSyncEnabled) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID must be a cloud-only user, not synced.'
            }

            # Start from enabled, so disabling is a real change. Put back what was found.
            $script:WasEnabled = $script:User.AccountEnabled
            if (-not $script:WasEnabled) {
                Update-MgUser -UserId $script:User.Id -AccountEnabled:$true
            }
            $script:SessionsBefore = $script:User.SignInSessionsValidFromDateTime

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $null = Disable-IRTUser -UserObject $script:User

            $script:After = Get-MgUser @GetParams
        }

        AfterAll {
            if ($null -ne $script:WasEnabled) {
                Update-MgUser -UserId $script:User.Id -AccountEnabled:$script:WasEnabled
            }
        }

        It 'disables the account' {
            $script:After.AccountEnabled | Should -BeFalse
        }

        It 'signs the user out of every session' {
            $script:After.SignInSessionsValidFromDateTime |
                Should -BeGreaterThan $script:SessionsBefore
        }
    }
}
