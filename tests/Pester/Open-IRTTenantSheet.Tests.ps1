#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Open-IRTTenantSheet.

.DESCRIPTION
    Open-IRTTenantSheet generates the tenants worksheet on first run and then hands it to
    the shell. New-TenantSheet and Invoke-Item are mocked throughout, so no workbook is
    written and no application is launched.

-- first run -------------------------------------------------------------

    'generates the worksheet when it does not exist'
    'opens the worksheet after generating it'

-- subsequent runs -------------------------------------------------------

    'does not regenerate an existing worksheet'
        Regenerating would destroy the user's tenant list.

    'opens the existing worksheet'

-- default path ----------------------------------------------------------

    'falls back to IRT_Config.TenantsSheetPath when TenantFile is omitted'
        The configured path is the one every other tenant function reads.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Open-IRTTenantSheet' -Tag 'unit' {

        BeforeAll {
            $TempRoot = [System.IO.Path]::GetTempPath()
            $TempName = [System.Guid]::NewGuid().ToString()
            $script:TempDir = Join-Path -Path $TempRoot -ChildPath $TempName
        }

        Context 'the worksheet does not exist' {

            BeforeAll {
                $script:MissingPath = Join-Path -Path $script:TempDir -ChildPath 'missing.xlsx'

                Mock New-TenantSheet {}
                Mock Invoke-Item {}
                Mock Write-IRT {}

                Open-IRTTenantSheet -TenantFile $script:MissingPath
            }

            It 'generates the worksheet when it does not exist' {
                Should -Invoke New-TenantSheet -Times 1 -Scope Context -ParameterFilter {
                    $Path -eq $script:MissingPath
                }
            }

            It 'opens the worksheet after generating it' {
                Should -Invoke Invoke-Item -Times 1 -Scope Context
            }
        }

        Context 'the worksheet already exists' {

            BeforeAll {
                $script:ExistingPath = Join-Path -Path $script:TempDir -ChildPath 'tenants.xlsx'
                $null = New-Item -ItemType Directory -Path $script:TempDir -Force
                Set-Content -LiteralPath $script:ExistingPath -Value 'placeholder'

                Mock New-TenantSheet {}
                Mock Invoke-Item {}
                Mock Write-IRT {}

                Open-IRTTenantSheet -TenantFile $script:ExistingPath
            }

            AfterAll {
                $RemoveParams = @{
                    LiteralPath = $script:TempDir
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = 'SilentlyContinue'
                }
                Remove-Item @RemoveParams
            }

            It 'does not regenerate an existing worksheet' {
                Should -Invoke New-TenantSheet -Times 0 -Scope Context
            }

            It 'opens the existing worksheet' {
                Should -Invoke Invoke-Item -Times 1 -Scope Context -ParameterFilter {
                    $Path -eq $script:ExistingPath
                }
            }
        }

        Context 'TenantFile is omitted' {

            BeforeAll {
                $script:ConfigPath = Join-Path -Path $script:TempDir -ChildPath 'configured.xlsx'
                $script:SavedConfig = $Global:IRT_Config
                $Global:IRT_Config = @{ TenantsSheetPath = $script:ConfigPath }

                Mock New-TenantSheet {}
                Mock Invoke-Item {}
                Mock Write-IRT {}

                Open-IRTTenantSheet
            }

            AfterAll {
                $Global:IRT_Config = $script:SavedConfig
            }

            It 'falls back to IRT_Config.TenantsSheetPath when TenantFile is omitted' {
                Should -Invoke Invoke-Item -Times 1 -Scope Context -ParameterFilter {
                    $Path -eq $script:ConfigPath
                }
            }
        }
    }
}
