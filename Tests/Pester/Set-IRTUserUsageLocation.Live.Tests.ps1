#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Set-IRTUserUsageLocation.

.DESCRIPTION
    These tests change the test tenant: they change the disposable test user's
    usage location, then put the old one back. They run only through
    '.\Tests.ps1 Destructive', after Tests\Confirm-RemoteDisposable.ps1 confirms
    the tenant is marked disposable.

    The new location is always different from the current one, so setting it is
    a real change. -CountryCode is passed, so the function never opens a browser
    or prompts; Start-Process is mocked to throw in case it tries.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - An active Graph session to the test tenant. PreTests.ps1 opens one for
        Destructive runs.
      - IRT_TEST_DISPOSABLE_USER_ID names a user that is not a real person's
        account (see Tests/.env.ps1.example).
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Set-IRTUserUsageLocation (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never restores a user left over
            # from another file.
            $script:Restore = $false

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Set-IRTUserUsageLocation online tests require an active Graph ' +
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
                Property = 'Id', 'UsageLocation', 'UserPrincipalName'
            }
            $script:User = Get-MgUser @GetParams
            if ($script:User.UserPrincipalName -eq (Get-MgContext).Account) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID is the signed-in account.'
            }

            $script:Original = $script:User.UsageLocation
            $script:NewCode = if ($script:Original -eq 'US') { 'CA' } else { 'US' }
            $script:Restore = $true

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Start-Process { throw 'Start-Process must not run.' }

            $SetParams = @{
                UserObject  = $script:User
                CountryCode = $script:NewCode
            }
            $null = Set-IRTUserUsageLocation @SetParams

            $script:After = Get-MgUser @GetParams
        }

        AfterAll {
            if ($script:Restore) {
                # PATCH directly, since the original may be empty, which Update-MgUser
                # cannot send
                $RestoreRequest = @{
                    Method      = 'PATCH'
                    Uri         = "v1.0/users/$($script:User.Id)"
                    Body        = @{ usageLocation = $script:Original } | ConvertTo-Json
                    ContentType = 'application/json'
                }
                $null = Invoke-MgGraphRequest @RestoreRequest
            }
        }

        It 'sets the usage location' {
            $script:After.UsageLocation | Should -Be $script:NewCode
        }
    }
}
