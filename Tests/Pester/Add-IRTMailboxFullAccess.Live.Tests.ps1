#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Add-IRTMailboxFullAccess.

.DESCRIPTION
    These tests change the test tenant: they give the signed-in account full
    access to the disposable test user's mailbox, then take it away with
    -Remove. They run only through '.\Tests.ps1 Destructive', after
    Tests\Confirm-RemoteDisposable.ps1 confirms the tenant is marked disposable.

    If the signed-in account already has full access, it is removed first, so
    adding it is a real change, and put back afterward. -GrantAccessTo is passed,
    so the function never asks which account to use; Build-Menu is mocked to
    throw in case it tries.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Active Graph and Exchange sessions to the test tenant. PreTests.ps1 opens
        them for Destructive runs.
      - IRT_TEST_DISPOSABLE_USER_ID names a user that is not a real person's
        account and has a mailbox (see Tests/.env.ps1.example).
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Add-IRTMailboxFullAccess (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never changes a mailbox left over
            # from another file.
            $script:Restore = $false

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph -and
                    $Global:IRT_Session.Exchange)) {
                throw ('Add-IRTMailboxFullAccess online tests require active Graph and ' +
                    'Exchange sessions. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_DISPOSABLE_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID not set. Run Tests/.env.ps1 first.'
            }
            if ($env:IRT_TEST_DISPOSABLE_USER_ID -eq $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID must not be the same user as IRT_TEST_USER_ID.'
            }

            Import-IRTModule -Name 'Microsoft.Graph.Users', 'ExchangeOnlineManagement'
            $GetParams = @{
                UserId   = $env:IRT_TEST_DISPOSABLE_USER_ID
                Property = 'Id', 'UserPrincipalName'
            }
            $script:User = Get-MgUser @GetParams
            $script:Mailbox = $script:User.UserPrincipalName
            $script:Admin = $Global:IRT_Session.Graph.Account
            if ($script:Mailbox -eq $script:Admin) {
                throw 'IRT_TEST_DISPOSABLE_USER_ID is the signed-in account.'
            }
            if (-not (Get-EXOMailbox -UserPrincipalName $script:Mailbox -ErrorAction Ignore)) {
                throw "IRT_TEST_DISPOSABLE_USER_ID ($($script:Mailbox)) has no mailbox."
            }

            # Returns whether the signed-in account has its own full access grant.
            function Test-FullAccess {
                $PermissionParams = @{
                    Identity    = $script:Mailbox
                    User        = $script:Admin
                    ErrorAction = 'Ignore'
                }
                [bool](Get-MailboxPermission @PermissionParams | Where-Object {
                        "$($_.AccessRights)" -match 'FullAccess' -and -not $_.IsInherited
                    })
            }
            $script:PermissionParams = @{
                Identity     = $script:Mailbox
                User         = $script:Admin
                AccessRights = 'FullAccess'
            }

            # Start without access, so adding it is a real change. Put back what was found.
            $script:HadAccess = Test-FullAccess
            $script:Restore = $true
            if ($script:HadAccess) {
                Remove-MailboxPermission @script:PermissionParams -Confirm:$false
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Build-Menu { throw 'Build-Menu must not run.' }

            $AccessParams = @{
                UserObject    = $script:User
                GrantAccessTo = $script:Admin
            }
            $null = Add-IRTMailboxFullAccess @AccessParams
            $script:AfterAdd = Test-FullAccess

            $null = Add-IRTMailboxFullAccess @AccessParams -Remove
            $script:AfterRemove = Test-FullAccess
        }

        AfterAll {
            if ($script:Restore) {
                $HasAccess = Test-FullAccess
                if ($script:HadAccess -and -not $HasAccess) {
                    $null = Add-MailboxPermission @script:PermissionParams -InheritanceType All
                }
                elseif ($HasAccess -and -not $script:HadAccess) {
                    Remove-MailboxPermission @script:PermissionParams -Confirm:$false
                }
            }
        }

        It 'gives the account full access' {
            $script:AfterAdd | Should -BeTrue
        }

        It 'takes full access away with -Remove' {
            $script:AfterRemove | Should -BeFalse
        }
    }
}
