#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Write-IRTSuppressedError.

.DESCRIPTION
    Write-IRTSuppressedError is a temporary workaround for errors the module keeps quiet
    because they can't yet be told apart from normal conditions. On a normal run it only
    writes to the debug log. When IRT_TEST_STRICT_ERRORS is '1', as during a live test
    run, it reports the error with an Error-level Write-IRT message.

    Write-IRT and Write-PSFMessage are mocked to capture what would be printed and
    logged. Each test sets IRT_TEST_STRICT_ERRORS itself and puts it back afterwards.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Write-IRTSuppressedError' -Tag 'unit' {

        BeforeAll {
            Mock Import-IRTModule { }

            $script:Errors = [System.Collections.Generic.List[string]]::new()
            $script:Logged = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }
            Mock Write-PSFMessage { $script:Logged.Add($Message) }

            $script:Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden'), 'TestError', 'PermissionDenied', $null)
            $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
        }

        AfterAll {
            $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
        }

        BeforeEach {
            $script:Errors.Clear()
            $script:Logged.Clear()
        }

        It 'only logs the error on a normal run' {
            $env:IRT_TEST_STRICT_ERRORS = $null

            Write-IRTSuppressedError -ErrorRecord $script:Record -Message 'Lookup failed'

            $script:Errors | Should -BeNullOrEmpty
            $script:Logged | Should -Match 'kept quiet: Lookup failed: Forbidden'
        }

        It 'reports the error during a live test run' {
            $env:IRT_TEST_STRICT_ERRORS = '1'

            Write-IRTSuppressedError -ErrorRecord $script:Record -Message 'Lookup failed'

            $script:Errors | Should -Be @('Lookup failed: Forbidden')
        }

        It 'stays quiet for any value other than 1' {
            $env:IRT_TEST_STRICT_ERRORS = '0'

            Write-IRTSuppressedError -ErrorRecord $script:Record -Message 'Lookup failed'

            $script:Errors | Should -BeNullOrEmpty
        }
    }
}
