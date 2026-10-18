#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Write-IRT's error stream output during live test runs.

.DESCRIPTION
    Write-IRT prints every message with Write-Host. As a temporary workaround, while
    IRT_TEST_STRICT_ERRORS is '1' (set by the live test run), an Error-level message is
    also written to the error stream. That is how an error printed inside a playbook
    step, which runs in its own PowerShell session, reaches the playbook's test.

    The real Write-IRT runs here. Write-Host is mocked so the tests' messages don't
    clutter the console. Each test sets IRT_TEST_STRICT_ERRORS itself and puts it back
    afterwards, and captures the error stream with -ErrorVariable.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Write-IRT' -Tag 'unit' {

        BeforeAll {
            # These tests expect non-terminating errors, as the module sees them under
            # PowerShell's default preference. The pre-push hook runs with 'Stop'.
            $ErrorActionPreference = 'Continue'

            Mock Write-Host { }
            $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
        }

        AfterAll {
            $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
        }

        It 'writes an Error-level message to the error stream during a live test run' {
            $env:IRT_TEST_STRICT_ERRORS = '1'

            Write-IRT 'Lookup failed' -Level Error -ErrorVariable Written 2>$null

            "$Written" | Should -Match 'Lookup failed'
        }

        It 'leaves Warn-level messages off the error stream during a live test run' {
            $env:IRT_TEST_STRICT_ERRORS = '1'

            Write-IRT 'Nothing found' -Level Warn -ErrorVariable Written 2>$null

            $Written | Should -BeNullOrEmpty
        }

        It 'leaves Error-level messages off the error stream on a normal run' {
            $env:IRT_TEST_STRICT_ERRORS = $null

            Write-IRT 'Lookup failed' -Level Error -ErrorVariable Written 2>$null

            $Written | Should -BeNullOrEmpty
        }
    }
}
