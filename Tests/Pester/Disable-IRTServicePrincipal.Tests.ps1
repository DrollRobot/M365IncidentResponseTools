#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Disable-IRTServicePrincipal and Enable-IRTServicePrincipal.

.DESCRIPTION
    Both commands are thin wrappers around Set-ServicePrincipalEnabled, which is mocked.
    These tests check that each passes the right -Enabled value, and passes the
    service principal objects through only when given some, so the helper's fallback
    to the global selection still applies.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Disable-IRTServicePrincipal and Enable-IRTServicePrincipal' -Tag 'unit' {

        BeforeEach {
            Mock Set-ServicePrincipalEnabled { }
            $script:Sp = [pscustomobject]@{ Id = 'sp-1'; AppDisplayName = 'App One' }
        }

        It 'Disable-IRTServicePrincipal disables the service principals it is given' {
            Disable-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            $F = { $Enabled -eq $false -and $ServicePrincipalObject[0].Id -eq 'sp-1' }
            Should -Invoke Set-ServicePrincipalEnabled -Times 1 -Exactly -ParameterFilter $F
        }

        It 'Enable-IRTServicePrincipal enables the service principals it is given' {
            Enable-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            $F = { $Enabled -eq $true -and $ServicePrincipalObject[0].Id -eq 'sp-1' }
            Should -Invoke Set-ServicePrincipalEnabled -Times 1 -Exactly -ParameterFilter $F
        }

        It 'leaves the selection to the helper when no object is passed' {
            Disable-IRTServicePrincipal

            $F = {
                $Enabled -eq $false -and
                -not $PSBoundParameters.ContainsKey('ServicePrincipalObject')
            }
            Should -Invoke Set-ServicePrincipalEnabled -Times 1 -Exactly -ParameterFilter $F
        }
    }
}
