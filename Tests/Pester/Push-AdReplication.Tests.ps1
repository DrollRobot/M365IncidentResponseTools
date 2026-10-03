#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Push-AdReplication.

.DESCRIPTION
    All tests are offline. repadmin only exists on hosts with the AD DS RSAT tools, so a
    global stub function named repadmin is created in BeforeAll and mocked; functions
    take precedence over applications, so the stub is used even where repadmin exists.
    Each mock sets $global:LASTEXITCODE the way the real executable would. Write-IRT is
    mocked to capture messages.

    'pushes replication from the given server'
        repadmin gets '/syncall <Server> /APed', naming the DC rather than the local
        computer.

    'does not warn when repadmin succeeds'
        Exit code 0 produces no warning.

    'warns when repadmin exits with an error'
        A non-zero exit code is reported with the server name.

    'warns and skips when repadmin is not installed'
        Without repadmin the push is skipped with a warning instead of an error.
#>

BeforeAll {
    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:repadmin {
        param([Parameter(ValueFromRemainingArguments)] $Arguments)
        $null = $Arguments
    }
}

AfterAll {
    Remove-Item -Path 'Function:\repadmin' -ErrorAction SilentlyContinue
}

InModuleScope M365IncidentResponseTools {

    Describe 'Push-AdReplication' -Tag 'unit' {

        BeforeEach {
            $script:Messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { $script:Messages.Add("${Level}: $Message") }
            Mock repadmin { $global:LASTEXITCODE = 0 }
        }

        It 'pushes replication from the given server' {
            Push-AdReplication -Server 'dc1.contoso.com'

            $F = {
                $Arguments[0] -eq '/syncall' -and
                $Arguments[1] -eq 'dc1.contoso.com' -and
                $Arguments[2] -eq '/APed'
            }
            Should -Invoke repadmin -Times 1 -Exactly -ParameterFilter $F
        }

        It 'does not warn when repadmin succeeds' {
            Push-AdReplication -Server 'dc1.contoso.com'

            $script:Messages | Where-Object { $_ -like 'Warn:*' } | Should -BeNullOrEmpty
        }

        It 'warns when repadmin exits with an error' {
            Mock repadmin { $global:LASTEXITCODE = 5 }

            Push-AdReplication -Server 'dc1.contoso.com'

            $script:Messages |
                Where-Object { $_ -like 'Warn:*dc1.contoso.com failed*exit code 5*' } |
                Should -HaveCount 1
        }

        It 'warns and skips when repadmin is not installed' {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'repadmin' }

            Push-AdReplication -Server 'dc1.contoso.com'

            Should -Invoke repadmin -Times 0 -Exactly
            $script:Messages |
                Where-Object { $_ -like 'Warn:*repadmin not found*' } |
                Should -HaveCount 1
        }
    }
}
