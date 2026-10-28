#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Set-ServicePrincipalEnabled.

.DESCRIPTION
    All tests are offline. The Graph cmdlets (Update-MgServicePrincipal,
    Get-MgServicePrincipal) are replaced by global stubs and mocked inside the module.
    Update-IRTToken, Import-IRTModule, Get-GlobalServicePrincipalObject, Write-IRT, and
    Format-Table are mocked.

    'disables the service principal and reads it back'
    'enables the service principal'
        accountEnabled is set to the requested value on the object's ID, then the object
        is fetched again to show its new state.

    'falls back to the selected service principals when none are passed'
    'throws when no service principal is passed or selected'
        Mirrors Set-UserEnabled: the global selection is used, and an empty selection is
        an error.

    'skips an object with no ID'
        A warning is written and Graph is not called.

    'reports a failed update as an error and moves on to the next one'
        A Graph error on one service principal does not stop the others.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Update-MgServicePrincipal {
        [CmdletBinding()]
        param([string] $ServicePrincipalId, [switch] $AccountEnabled)
        $null = $ServicePrincipalId, $AccountEnabled
    }
    function global:Get-MgServicePrincipal {
        [CmdletBinding()]
        param([string] $ServicePrincipalId, [string[]] $Property)
        $null = $ServicePrincipalId, $Property
    }
}

AfterAll {
    @('Update-MgServicePrincipal', 'Get-MgServicePrincipal') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction Ignore }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Set-ServicePrincipalEnabled' -Tag 'unit' {

        BeforeEach {
            $script:Sp = [pscustomobject]@{ Id = 'sp-1'; AppDisplayName = 'App One' }
            $script:Warnings = [System.Collections.Generic.List[string]]::new()
            $script:Errors = [System.Collections.Generic.List[string]]::new()

            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Get-GlobalServicePrincipalObject { }
            Mock Format-Table { }
            Mock Update-MgServicePrincipal { }
            Mock Get-MgServicePrincipal {
                [pscustomobject]@{ Id = $ServicePrincipalId; AccountEnabled = $false }
            }

            # print every message; collect Warn and Error-level ones for the tests to check
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Warn' } {
                $script:Warnings.Add($Message)
            }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }
        }

        It 'disables the service principal and reads it back' {
            Set-ServicePrincipalEnabled -ServicePrincipalObject $script:Sp -Enabled $false

            $F = { $ServicePrincipalId -eq 'sp-1' -and -not $AccountEnabled }
            Should -Invoke Update-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $F
            $G = { $ServicePrincipalId -eq 'sp-1' -and 'accountEnabled' -in $Property }
            Should -Invoke Get-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $G
            $script:Errors | Should -HaveCount 0
        }

        It 'enables the service principal' {
            Set-ServicePrincipalEnabled -ServicePrincipalObject $script:Sp -Enabled $true

            $F = { $ServicePrincipalId -eq 'sp-1' -and $AccountEnabled }
            Should -Invoke Update-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $F
        }

        It 'falls back to the selected service principals when none are passed' {
            Mock Get-GlobalServicePrincipalObject {
                [pscustomobject]@{ Id = 'sp-2'; DisplayName = 'App Two' }
            }

            Set-ServicePrincipalEnabled -Enabled $false

            $F = { $ServicePrincipalId -eq 'sp-2' }
            Should -Invoke Update-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $F
        }

        It 'throws when no service principal is passed or selected' {
            { Set-ServicePrincipalEnabled -Enabled $false } |
                Should -Throw '*No service principal objects*'
            Should -Invoke Update-MgServicePrincipal -Times 0 -Exactly
        }

        It 'skips an object with no ID' {
            $NoId = [pscustomobject]@{ Id = $null; DisplayName = 'Broken' }

            Set-ServicePrincipalEnabled -ServicePrincipalObject $NoId -Enabled $false

            Should -Invoke Update-MgServicePrincipal -Times 0 -Exactly
            $script:Warnings | Should -HaveCount 1
            $script:Warnings[0] | Should -BeLike '*Broken*'
        }

        It 'reports a failed update as an error and moves on to the next one' {
            Mock Update-MgServicePrincipal { throw 'Insufficient privileges' } -ParameterFilter {
                $ServicePrincipalId -eq 'sp-1'
            }
            $Second = [pscustomobject]@{ Id = 'sp-2'; AppDisplayName = 'App Two' }

            Set-ServicePrincipalEnabled -ServicePrincipalObject $script:Sp, $Second -Enabled $false

            $script:Errors | Should -HaveCount 1
            $script:Errors[0] | Should -BeLike '*App One*Insufficient privileges*'
            $F = { $ServicePrincipalId -eq 'sp-2' }
            Should -Invoke Update-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $F
            Should -Invoke Get-MgServicePrincipal -Times 1 -Exactly -ParameterFilter $F
        }
    }
}
