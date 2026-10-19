#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Show-IRTMailbox.

.DESCRIPTION
    Show-IRTMailbox looks up each user's mailbox and prints it, followed by its automatic
    reply settings. A user without a mailbox is normal and reported as a warning. A
    failed lookup used to leave the previous user's mailbox in place, which was then
    printed under the failed user's name. Automatic reply messages are stored as HTML
    and printed as plain text; failing to read them is reported as an error, since the
    mailbox is known to exist by then.

    The Exchange cmdlets are replaced by global stubs and mocked inside the module.
    Format-List is mocked to capture the records that would be printed. Write-IRT is
    mocked to print every message and fail the test on Error-level ones, except where a
    test expects an error and captures it instead.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Get-EXOMailbox {
        [CmdletBinding()] param([string] $UserPrincipalName, [string[]] $PropertySets)
        $null = $UserPrincipalName, $PropertySets
    }
    function global:Get-EXOMailboxPermission {
        [CmdletBinding()] param([string] $Identity)
        $null = $Identity
    }
    function global:Get-MailboxAutoReplyConfiguration {
        [CmdletBinding()] param([string] $Identity)
        $null = $Identity
    }
}

AfterAll {
    'Get-EXOMailbox', 'Get-EXOMailboxPermission', 'Get-MailboxAutoReplyConfiguration' |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction Ignore }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Show-IRTMailbox' -Tag 'unit' {

        BeforeAll {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Get-EXOMailboxPermission { }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Printed = [System.Collections.Generic.List[object]]::new()
            Mock Format-List { $script:Printed.Add($InputObject) }

            # the first user has a mailbox; the lookup for the second one fails
            Mock Get-EXOMailbox {
                if ($UserPrincipalName -ne 'one@contoso.com') { throw 'Mailbox not found' }
                [pscustomobject]@{
                    DisplayName        = 'User One'
                    PrimarySmtpAddress = 'one@contoso.com'
                    IsMailboxEnabled   = $true
                }
            }
            Mock Get-MailboxAutoReplyConfiguration {
                [pscustomobject]@{
                    AutoReplyState   = 'Enabled'
                    ExternalAudience = 'All'
                    InternalMessage  = '<html><body><p>Out of office &amp; away</p></body></html>'
                    ExternalMessage  = ''
                }
            }

            # a normal run, where the failed lookup is kept quiet. The live run sets this
            # and NotLive can run after it in the same session.
            $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
            $env:IRT_TEST_STRICT_ERRORS = $null

            $Users = @(
                [pscustomobject]@{ UserPrincipalName = 'one@contoso.com' }
                [pscustomobject]@{ UserPrincipalName = 'two@contoso.com' }
            )
            Show-IRTMailbox -UserObject $Users

            $script:Mailboxes = @($script:Printed | Where-Object { $_.DisplayName })
            $script:AutoReplies = @($script:Printed | Where-Object { $_.AutoReplyState })
        }

        AfterAll {
            $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
        }

        It 'prints the mailbox of the user who has one' {
            $script:Mailboxes.Count | Should -Be 1
            $script:Mailboxes[0].DisplayName | Should -Be 'User One'
        }

        It 'prints the automatic replies with the messages as plain text' {
            $script:AutoReplies.Count | Should -Be 1
            $script:AutoReplies[0].AutoReplyState | Should -Be 'Enabled'
            $script:AutoReplies[0].InternalMessage | Should -Be 'Out of office & away'
            $script:AutoReplies[0].ExternalMessage | Should -Be ''
        }

        It 'reports the failed lookup as no mailbox instead of reusing the last one' {
            $NoMailbox = { $Level -eq 'Warn' -and $Message -like '*two@contoso.com*' }
            Should -Invoke Write-IRT -ParameterFilter $NoMailbox -Times 1 -Exactly -Scope Describe
        }
    }

    Describe 'Show-IRTMailbox automatic reply failure' -Tag 'unit' {

        BeforeAll {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Get-EXOMailboxPermission { }
            Mock Format-List { }
            Mock Get-EXOMailbox { [pscustomobject]@{ DisplayName = 'User One' } }
            Mock Get-MailboxAutoReplyConfiguration { throw 'Access denied' }

            # print every message; collect Error-level ones for the test to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }
        }

        It 'reports a failed automatic reply lookup as an error' {
            $User = [pscustomobject]@{ UserPrincipalName = 'one@contoso.com' }

            Show-IRTMailbox -UserObject $User

            $script:Errors.Count | Should -Be 1
            $script:Errors[0] | Should -Match 'automatic replies.*Access denied'
        }
    }

    Describe 'Show-IRTMailbox during a live test run' -Tag 'unit' {

        BeforeAll {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Get-EXOMailboxPermission { }
            Mock Format-List { }
            Mock Get-EXOMailbox { throw 'Mailbox not found' }

            # print every message; collect Error-level ones for the test to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }

            $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
            $env:IRT_TEST_STRICT_ERRORS = '1'
        }

        AfterAll {
            $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
        }

        It 'reports the failed lookup (temporary workaround)' {
            $User = [pscustomobject]@{ UserPrincipalName = 'two@contoso.com' }

            Show-IRTMailbox -UserObject $User

            $script:Errors.Count | Should -Be 1
            $script:Errors[0] | Should -Match 'two@contoso\.com: Mailbox not found'
        }
    }
}
