#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Show-IRTMailbox.

.DESCRIPTION
    Show-IRTMailbox looks up each user's mailbox and prints it. A user without a mailbox
    is normal and reported as a warning. A failed lookup used to leave the previous
    user's mailbox in place, which was then printed under the failed user's name.

    The Exchange cmdlets are replaced by global stubs and mocked inside the module.
    Format-List is mocked to capture the mailbox records that would be printed.
    Write-IRT is mocked to print every message and fail the test on Error-level ones.
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
}

AfterAll {
    'Get-EXOMailbox', 'Get-EXOMailboxPermission' |
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

            $Users = @(
                [pscustomobject]@{ UserPrincipalName = 'one@contoso.com' }
                [pscustomobject]@{ UserPrincipalName = 'two@contoso.com' }
            )
            Show-IRTMailbox -UserObject $Users
        }

        It 'prints the mailbox of the user who has one' {
            $script:Printed.Count | Should -Be 1
            $script:Printed[0].DisplayName | Should -Be 'User One'
        }

        It 'reports the failed lookup as no mailbox instead of reusing the last one' {
            $NoMailbox = { $Level -eq 'Warn' -and $Message -like '*two@contoso.com*' }
            Should -Invoke Write-IRT -ParameterFilter $NoMailbox -Times 1 -Exactly -Scope Describe
        }
    }
}
