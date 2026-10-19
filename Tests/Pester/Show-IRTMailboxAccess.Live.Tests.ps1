#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Show-IRTMailboxAccess.

.DESCRIPTION
    These tests require active Exchange Online and Microsoft Graph sessions
    established by Connect-IRT. Show-IRTMailboxAccess looks up the test user's
    mailbox and prints who has access to it. No Exchange call is mocked. The test
    user comes from Graph, as it would from Get-IRTUser.

    Show-IRTMailboxAccess reports a failed mailbox lookup as a warning, so
    Format-Table is mocked to capture the permission rows it would print. Every
    mailbox has a FullAccess row for NT AUTHORITY\SELF, so that row must be there.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Exchange and Graph sessions active).
        Tests.ps1 runs Connect-IRT.Tests.ps1 first and only proceeds here on
        success.
      - IRT_TEST_USER_ID must be set to a valid user GUID (see Tests/.env.ps1),
        and the test user must have a mailbox.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Show-IRTMailboxAccess (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Exchange -and
                    $Global:IRT_Session.Graph)) {
                throw ('Show-IRTMailboxAccess online tests require active Exchange ' +
                    'Online and Graph sessions. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_USER_ID not set. Run Tests/.env.ps1 first.'
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Printed = [System.Collections.Generic.List[object]]::new()
            Mock Format-Table { $script:Printed.Add($InputObject) }

            $script:User = Get-MgUser -UserId $env:IRT_TEST_USER_ID -ErrorAction Stop
            $MailboxParams = @{
                UserPrincipalName = $script:User.UserPrincipalName
                ErrorAction       = 'SilentlyContinue'
            }
            if (-not (Get-EXOMailbox @MailboxParams)) {
                throw "The test user $($script:User.UserPrincipalName) has no mailbox."
            }

            Show-IRTMailboxAccess -UserObject $script:User
        }

        It 'prints the mailbox permissions' {
            $script:Printed.Count | Should -BeGreaterThan 0
        }

        It 'includes the mailbox owner''s own access' {
            $Self = @($script:Printed | Where-Object { "$($_.User)" -eq 'NT AUTHORITY\SELF' })
            $Self | Should -Not -BeNullOrEmpty
            "$($Self[0].AccessRights)" | Should -Match 'FullAccess'
        }
    }
}
