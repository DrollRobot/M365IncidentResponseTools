#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Initialize-IRTFileLogging, which maps the LogFolderPath config value
    onto the PSFramework logfile provider.

.DESCRIPTION
    All tests are offline. Set-PSFLoggingProvider, Write-IRT and Write-PSFMessage are
    mocked, so no real logging provider is touched. Folders and files live under
    $TestDrive. $Global:IRT_Config is swapped for a minimal stand-in before each test
    and restored afterwards, so the real session config is never modified.

-- LogFolderPath is blank ------------------------------------------------

    File logging must be turned off. Disabling a provider instance that was never
    created throws inside PSFramework; that must not escape, because this runs at
    module import.

-- LogFolderPath is a folder ---------------------------------------------

    The provider is enabled with a per-day TXT file in that folder, and cleanup is
    limited to IRT-*.log files older than 30 days so other files in the folder are
    never deleted. A folder that does not exist yet is created.

-- LogFolderPath is unusable ---------------------------------------------

    A path that is an existing file, or a folder that cannot be created, must warn
    the user and must never enable the provider or throw.
#>

# ---------------------------------------------------------------------------
# All tests run inside InModuleScope so that Mock intercepts the calls made from
# within Initialize-IRTFileLogging, not from the outer session scope.
# ---------------------------------------------------------------------------
InModuleScope M365IncidentResponseTools {

    Describe 'Initialize-IRTFileLogging' {

        BeforeEach {
            $script:SavedConfig = (
                Get-Variable -Name IRT_Config -Scope Global -ErrorAction SilentlyContinue
            )?.Value

            # Capture every provider call's parameters. FilePath, LogRotatePath and
            # friends are dynamic parameters, so read them from the recorded calls
            # rather than a ParameterFilter.
            $script:ProviderCalls = [System.Collections.Generic.List[hashtable]]::new()
            Mock Set-PSFLoggingProvider {
                $Recorded = @{}
                foreach ($Key in $PesterBoundParameters.Keys) {
                    $Recorded[$Key] = $PesterBoundParameters[$Key]
                }
                $script:ProviderCalls.Add($Recorded)
            }
            Mock Write-IRT {}
            Mock Write-PSFMessage {}
        }
        AfterEach {
            $Global:IRT_Config = $script:SavedConfig
        }

        # -------------------------------------------------------------------
        Context 'LogFolderPath is blank' {

            It 'disables the logfile provider when LogFolderPath is <Label>' -TestCases @(
                @{ Label = 'null'; Value = $null }
                @{ Label = 'empty'; Value = '' }
                @{ Label = 'whitespace'; Value = '   ' }
            ) {
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $Value }

                Initialize-IRTFileLogging

                $script:ProviderCalls.Count | Should -Be 1
                $script:ProviderCalls[0].Name | Should -Be 'logfile'
                $script:ProviderCalls[0].InstanceName | Should -Be 'M365IRT'
                $script:ProviderCalls[0].Enabled | Should -BeFalse
                Should -Invoke Write-IRT -Times 0
            }

            It 'does not throw when there is no provider instance to disable' {
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $null }
                Mock Set-PSFLoggingProvider { throw 'No such logging provider instance' }

                { Initialize-IRTFileLogging } | Should -Not -Throw
            }
        }

        # -------------------------------------------------------------------
        Context 'LogFolderPath is a folder' {

            It 'enables a per-day TXT log file in that folder' {
                $Folder = Join-Path -Path $TestDrive -ChildPath 'logs'
                $null = New-Item -ItemType Directory -Path $Folder
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $Folder }

                Initialize-IRTFileLogging

                $script:ProviderCalls.Count | Should -Be 1
                $Call = $script:ProviderCalls[0]
                $Call.Name | Should -Be 'logfile'
                $Call.InstanceName | Should -Be 'M365IRT'
                $Call.Enabled | Should -BeTrue
                $Call.FileType | Should -Be 'TXT'
                $ExpectedPath = Join-Path -Path $Folder -ChildPath 'IRT-%Date%.log'
                $Call.FilePath | Should -Be $ExpectedPath
                $Call.MutexName | Should -Not -BeNullOrEmpty
                Should -Invoke Write-IRT -Times 0
            }

            It 'limits cleanup to IRT-*.log files older than 30 days' {
                $Folder = Join-Path -Path $TestDrive -ChildPath 'logs'
                $null = New-Item -ItemType Directory -Path $Folder -Force
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $Folder }

                Initialize-IRTFileLogging

                $Call = $script:ProviderCalls[0]
                $ExpectedGlob = Join-Path -Path $Folder -ChildPath 'IRT-*.log'
                $Call.LogRotatePath | Should -Be $ExpectedGlob
                $Call.LogRetentionTime | Should -Be '30d'
            }

            It 'creates the folder when it does not exist' {
                $Folder = Join-Path -Path $TestDrive -ChildPath 'new\nested\logs'
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $Folder }

                Initialize-IRTFileLogging

                Test-Path -LiteralPath $Folder -PathType Container | Should -BeTrue
                $script:ProviderCalls[0].Enabled | Should -BeTrue
            }
        }

        # -------------------------------------------------------------------
        Context 'LogFolderPath is unusable' {

            It 'warns and disables logging when the path is an existing file' {
                $File = Join-Path -Path $TestDrive -ChildPath 'not-a-folder.log'
                $null = New-Item -ItemType File -Path $File -Force
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $File }

                Initialize-IRTFileLogging

                Should -Invoke Write-IRT -Times 1 -Exactly -ParameterFilter {
                    $Level -eq 'Warn' -and $Message -match 'is a file'
                }
                $script:ProviderCalls.Count | Should -Be 1
                $script:ProviderCalls[0].Enabled | Should -BeFalse
            }

            It 'warns without throwing when the folder cannot be created' {
                $Folder = Join-Path -Path $TestDrive -ChildPath 'denied'
                $Global:IRT_Config = [pscustomobject]@{ LogFolderPath = $Folder }
                Mock New-Item { throw 'Access to the path is denied.' }

                { Initialize-IRTFileLogging } | Should -Not -Throw

                Should -Invoke Write-IRT -Times 1 -Exactly -ParameterFilter {
                    $Level -eq 'Warn' -and $Message -match 'Failed to enable file logging'
                }
                $script:ProviderCalls.Count | Should -Be 0
            }
        }
    }
}
