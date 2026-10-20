#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Push-RemoteAdSync: which servers get checked, and what it returns when no
    server syncs.

.DESCRIPTION
    Write-IRT and Write-Progress are mocked to capture messages. The checks run the real
    runspace pool and New-PSSession against host names that cannot resolve, with a dummy
    credential, so each session fails in seconds with no network target. A server that
    syncs needs a real Entra Connect server, so the success path is covered only by the
    mocked Push-IRTAdSync tests.

-- names (unit) --------------------------------------------------------------------

    'skips blank names'
        No session is attempted for an empty or null name.

-- server checks (integration) -----------------------------------------------------

    'returns nothing and reports each server when no session opens'
        Every server gets its own session error, and nothing is returned, so the caller
        does not save a server.

    'checks the host name without the domain'
        'host.domain' is checked as 'host'.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Push-RemoteAdSync' {

        BeforeEach {
            $script:Messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { $script:Messages.Add($Message) }
            Mock Write-Progress { }
            $script:Credential = [pscredential]::new('irt-pester', [securestring]::new())
        }

        Context 'names' -Tag 'unit' {

            It 'skips blank names' {
                $Result = Push-RemoteAdSync -ComputerName '', $null -Credential $Credential

                $Result | Should -BeNullOrEmpty
                Should -Invoke Write-IRT -Times 0 -Exactly
            }
        }

        Context 'server checks' -Tag 'integration' {

            It 'returns nothing and reports each server when no session opens' {
                $PushParams = @{
                    ComputerName = 'irt-pester-nohost-a', 'irt-pester-nohost-b'
                    Credential   = $Credential
                }
                $Result = Push-RemoteAdSync @PushParams

                $Result | Should -BeNullOrEmpty
                # checks are reported as they finish, so compare without order
                $Checked = $script:Messages |
                    Where-Object { $_ -like 'Opening session on * failed: ?*' } |
                    ForEach-Object { ($_ -split ' ')[3] } |
                    Sort-Object
                $Checked | Should -Be @('irt-pester-nohost-a', 'irt-pester-nohost-b')
            }

            It 'checks the host name without the domain' {
                $PushParams = @{
                    ComputerName = 'irt-pester-nohost.contoso.invalid'
                    Credential   = $Credential
                }
                Push-RemoteAdSync @PushParams

                $script:Messages |
                    Where-Object { $_ -like 'Opening session on irt-pester-nohost failed: ?*' } |
                    Should -HaveCount 1
            }
        }
    }
}
