#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Invoke-IRTNativeCommand.

.DESCRIPTION
    Exercises the external-CLI wrapper against the current PowerShell executable
    (resolved from the running process) so the tests are deterministic and need
    no third-party tools. Covers stdout capture, stderr capture, a non-zero exit
    code, and the start-failure path where the executable cannot be launched.

    'captures stdout as a line array'
        StdOut is returned split into lines and contains the written text.

    'captures stderr text'
        Text written to the error stream is returned in StdErr, separate from
        StdOut, with a zero exit code.

    'returns the process exit code'
        A child process that exits non-zero surfaces that code in ExitCode.

    'returns exit code -1 and a message when the process cannot start'
        A non-existent executable does not throw; ExitCode is -1 and StdErr
        carries the exception message.

    'passes environment variables to the child process'
        A variable supplied via -Environment is visible to the child and does
        not leak into the caller's session.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Invoke-IRTNativeCommand' {

        BeforeAll {
            # Full path to the pwsh that is running these tests -- always present.
            $script:Pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            $script:BaseArgs = @('-NoProfile', '-NonInteractive', '-Command')
        }

        It 'captures stdout as a line array' {
            $Result = Invoke-IRTNativeCommand -FilePath $script:Pwsh -Arguments (
                $script:BaseArgs + "Write-Output 'hello-stdout'")
            $Result.ExitCode | Should -Be 0
            $Result.StdOut | Should -BeOfType ([string])
            ($Result.StdOut -join "`n") | Should -BeLike '*hello-stdout*'
            $Result.StdErr | Should -BeNullOrEmpty
        }

        It 'captures stderr text' {
            $Result = Invoke-IRTNativeCommand -FilePath $script:Pwsh -Arguments (
                $script:BaseArgs + "[Console]::Error.WriteLine('boom-stderr')")
            $Result.ExitCode | Should -Be 0
            $Result.StdErr | Should -BeLike '*boom-stderr*'
        }

        It 'returns the process exit code' {
            $Result = Invoke-IRTNativeCommand -FilePath $script:Pwsh -Arguments (
                $script:BaseArgs + 'exit 3')
            $Result.ExitCode | Should -Be 3
        }

        It 'returns exit code -1 and a message when the process cannot start' {
            $Result = Invoke-IRTNativeCommand -FilePath 'C:\does\not\exist\nope.exe'
            $Result.ExitCode | Should -Be -1
            $Result.StdErr | Should -Not -BeNullOrEmpty
        }

        It 'passes environment variables to the child process' {
            $Result = Invoke-IRTNativeCommand -FilePath $script:Pwsh -Arguments (
                $script:BaseArgs + 'Write-Output $env:IRT_TEST_VAR') -Environment @{
                IRT_TEST_VAR = 'child-value'
            }
            ($Result.StdOut -join "`n") | Should -BeLike '*child-value*'
            # Must not leak into the caller's session.
            $env:IRT_TEST_VAR | Should -BeNullOrEmpty
        }
    }
}
