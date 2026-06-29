#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Open-IRTSpreadsheet: workbook discovery, lock-file
    filtering, -Recurse behavior, and the not-found / empty-folder paths.

.DESCRIPTION
    All tests are offline. Invoke-Item and Write-IRT are mocked so no files are
    actually opened and no host output is produced; the tests assert on which
    paths the function hands to Invoke-Item. Workbooks are represented by empty
    files created under the Pester TestDrive.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Open-IRTSpreadsheet' {

        BeforeEach {
            Mock Invoke-Item { }
            Mock Write-IRT { }
        }

        Context 'a folder containing .xlsx files' {

            BeforeEach {
                $script:Dir = Join-Path -Path $TestDrive -ChildPath 'sheets'
                $null = New-Item -ItemType Directory -Path $script:Dir -Force
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Dir -ChildPath 'a.xlsx')
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Dir -ChildPath 'b.xlsx')
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Dir -ChildPath 'notes.txt')
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Dir -ChildPath '~$a.xlsx')
            }

            It 'opens every .xlsx file in the path' {
                Open-IRTSpreadsheet -Path $script:Dir
                Should -Invoke Invoke-Item -Times 2 -Exactly
            }

            It 'opens the a.xlsx workbook' {
                Open-IRTSpreadsheet -Path $script:Dir
                Should -Invoke Invoke-Item -Times 1 -Exactly -ParameterFilter {
                    $Path -like '*a.xlsx' -and $Path -notlike '*~$*'
                }
            }

            It 'skips non-xlsx files' {
                Open-IRTSpreadsheet -Path $script:Dir
                Should -Invoke Invoke-Item -Times 0 -Exactly -ParameterFilter {
                    $Path -like '*notes.txt'
                }
            }

            It 'skips Excel lock/temp files beginning with ~$' {
                Open-IRTSpreadsheet -Path $script:Dir
                Should -Invoke Invoke-Item -Times 0 -Exactly -ParameterFilter {
                    $Path -like '*~$*'
                }
            }
        }

        Context '-Recurse' {

            BeforeEach {
                $script:Root = Join-Path -Path $TestDrive -ChildPath 'recurse'
                $script:Sub = Join-Path -Path $script:Root -ChildPath 'sub'
                $null = New-Item -ItemType Directory -Path $script:Sub -Force
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Root -ChildPath 'top.xlsx')
                $null = New-Item -ItemType File -Force -Path (
                    Join-Path -Path $script:Sub -ChildPath 'nested.xlsx')
            }

            It 'opens only the top-level workbook by default' {
                Open-IRTSpreadsheet -Path $script:Root
                Should -Invoke Invoke-Item -Times 1 -Exactly
            }

            It 'opens nested workbooks when -Recurse is set' {
                Open-IRTSpreadsheet -Path $script:Root -Recurse
                Should -Invoke Invoke-Item -Times 2 -Exactly
            }
        }

        Context 'a folder with no .xlsx files' {

            It 'opens nothing and warns' {
                $Empty = Join-Path -Path $TestDrive -ChildPath 'empty'
                $null = New-Item -ItemType Directory -Path $Empty -Force
                Open-IRTSpreadsheet -Path $Empty
                Should -Invoke Invoke-Item -Times 0 -Exactly
                Should -Invoke Write-IRT -ParameterFilter { $Level -eq 'Warn' }
            }
        }

        Context 'a path that does not exist' {

            It 'opens nothing and writes an error' {
                $Missing = Join-Path -Path $TestDrive -ChildPath 'does-not-exist'
                Open-IRTSpreadsheet -Path $Missing
                Should -Invoke Invoke-Item -Times 0 -Exactly
                Should -Invoke Write-IRT -ParameterFilter { $Level -eq 'Error' }
            }
        }
    }
}
