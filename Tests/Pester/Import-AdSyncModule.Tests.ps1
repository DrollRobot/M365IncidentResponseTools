#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Import-AdSyncModule.

.DESCRIPTION
    All tests are offline. The ADSync service's program path is read from the registry,
    so Get-ItemProperty is mocked to point it at a fake Entra Connect install folder in
    TestDrive. Write-IRT is mocked to capture messages.

    A shell opened by a remote support tool on a sync server could not find the ADSync
    module, so Start-ADSyncSyncCycle was "not recognized", while importing the module by
    its full path worked.

-- loading (unit) ------------------------------------------------------------------

    Import-Module and the Get-Command check for Start-ADSyncSyncCycle are mocked.

    'loads nothing when Start-ADSyncSyncCycle is already available'
        The usual case: the shell finds the module itself.

    'loads the module from the ADSync service's install folder (<Form>)'
        The module is Bin\ADSync\ADSync.psd1 next to the service's program, whether the
        service path is quoted with arguments or not.

    'reports an error when the ADSync service path is not found'
    'reports an error when the module is not in the install folder'
    'reports an error when loading the module fails'
        Each returns $false, so the caller skips the sync.

-- loading a real module (integration) ---------------------------------------------

    'makes Start-ADSyncSyncCycle available from the install folder'
        A real Import-Module of a fake ADSync module, with only the registry read mocked.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Import-AdSyncModule' {

        BeforeEach {
            $script:Messages = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { $script:Messages.Add("${Level}: $Message") }

            # fake install folder: <TestDrive>\<test>\Bin\miiserver.exe, Bin\ADSync\ADSync.psd1
            $Install = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
            $script:BinPath = Join-Path -Path $Install -ChildPath 'Bin'
            $script:ModuleFolder = Join-Path -Path $script:BinPath -ChildPath 'ADSync'
            $null = New-Item -Path $script:ModuleFolder -ItemType Directory
            $script:ModulePath = Join-Path -Path $script:ModuleFolder -ChildPath 'ADSync.psd1'
            $ExePath = Join-Path -Path $script:BinPath -ChildPath 'miiserver.exe'
            $script:ImagePath = "`"$ExePath`""

            $RegFilter = { $Path -like '*\Services\ADSync' -and $Name -eq 'ImagePath' }
            Mock Get-ItemProperty {
                [pscustomobject]@{ ImagePath = $script:ImagePath }
            } -ParameterFilter $RegFilter
        }

        Context 'loading' -Tag 'unit' {

            BeforeEach {
                $null = New-Item -Path $script:ModulePath -ItemType File
                Mock Import-Module { }
                Mock Get-Command { } -ParameterFilter { $Name -eq 'Start-ADSyncSyncCycle' }
            }

            It 'loads nothing when Start-ADSyncSyncCycle is already available' {
                Mock Get-Command {
                    [pscustomobject]@{ Name = 'Start-ADSyncSyncCycle' }
                } -ParameterFilter { $Name -eq 'Start-ADSyncSyncCycle' }

                Import-AdSyncModule | Should -BeTrue

                Should -Invoke Import-Module -Times 0 -Exactly
                Should -Invoke Get-ItemProperty -Times 0 -Exactly
            }

            It "loads the module from the ADSync service's install folder (<Form>)" -ForEach @(
                @{ Form = 'quoted, with arguments'; Quoted = $true }
                @{ Form = 'unquoted'; Quoted = $false }
            ) {
                $ExePath = Join-Path -Path $script:BinPath -ChildPath 'miiserver.exe'
                $script:ImagePath = if ($Quoted) { "`"$ExePath`" /service" } else { $ExePath }

                Import-AdSyncModule | Should -BeTrue

                $F = { $Name -eq $script:ModulePath }
                Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter $F
                $script:Messages | Should -BeNullOrEmpty
            }

            It 'reports an error when the ADSync service path is not found' {
                $script:ImagePath = $null

                Import-AdSyncModule | Should -BeFalse

                Should -Invoke Import-Module -Times 0 -Exactly
                $script:Messages |
                    Where-Object { $_ -like 'Error:*service program path not found*' } |
                    Should -HaveCount 1
            }

            It 'reports an error when the module is not in the install folder' {
                Remove-Item -Path $script:ModulePath

                Import-AdSyncModule | Should -BeFalse

                Should -Invoke Import-Module -Times 0 -Exactly
                $script:Messages |
                    Where-Object { $_ -like 'Error:*ADSync module not found at*ADSync.psd1*' } |
                    Should -HaveCount 1
            }

            It 'reports an error when loading the module fails' {
                Mock Import-Module { throw 'bad module' }

                Import-AdSyncModule | Should -BeFalse

                $script:Messages |
                    Where-Object { $_ -like 'Error:*loading ADSync module*failed: bad module' } |
                    Should -HaveCount 1
            }
        }

        Context 'loading a real module' -Tag 'integration' {

            BeforeEach {
                # a fake ADSync module with only the sync command
                $PsmPath = Join-Path -Path $script:ModuleFolder -ChildPath 'ADSync.psm1'
                $Psm = 'function Start-ADSyncSyncCycle { param($PolicyType) $null = $PolicyType }'
                Set-Content -Path $PsmPath -Value $Psm
                $ManifestParams = @{
                    Path              = $script:ModulePath
                    RootModule        = 'ADSync.psm1'
                    FunctionsToExport = 'Start-ADSyncSyncCycle'
                }
                New-ModuleManifest @ManifestParams
            }

            AfterEach {
                Remove-Module -Name 'ADSync' -ErrorAction Ignore
            }

            It 'makes Start-ADSyncSyncCycle available from the install folder' {
                Get-Command -Name 'Start-ADSyncSyncCycle' -ErrorAction Ignore |
                    Should -BeNullOrEmpty

                Import-AdSyncModule | Should -BeTrue

                Get-Command -Name 'Start-ADSyncSyncCycle' -ErrorAction Ignore |
                    Should -Not -BeNullOrEmpty
            }
        }
    }
}
