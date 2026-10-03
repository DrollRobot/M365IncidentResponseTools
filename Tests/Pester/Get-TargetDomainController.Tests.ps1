#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-TargetDomainController.

.DESCRIPTION
    All tests are offline. Get-ADDomainController only exists on hosts with the
    ActiveDirectory module, so a thin global stub is created in BeforeAll and mocked.
    Lookups by -Identity (is this computer a DC?) and -Discover (DC locator) are mocked
    separately via $PesterBoundParameters, since strict mode rejects reading an unbound
    switch variable.

    DC locator discovery can return a peer DC even when run on a DC, so the helper
    checks this computer first.

    'returns this computer when it is a writable DC'
        Looked up by $env:COMPUTERNAME; discovery is never called.

    'discovers a writable DC when this computer is a read-only DC'
        A read-only DC can't take changes, so it falls back to -Discover -Writable.

    'discovers a writable DC when this computer is not a DC'
        The identity lookup failing means this computer isn't a DC.

    'throws when this computer is not a DC and discovery fails'
        Callers decide how to handle having no DC.
#>

BeforeAll {
    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:Get-ADDomainController {
        [CmdletBinding()]
        param($Identity, [switch] $Discover, [switch] $Writable)
        $null = $Identity, $Discover, $Writable
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Get-ADDomainController' -ErrorAction SilentlyContinue
}

InModuleScope M365IncidentResponseTools {

    Describe 'Get-TargetDomainController' -Tag 'unit' {

        BeforeEach {
            $script:IdentityFilter = { $PesterBoundParameters.ContainsKey('Identity') }
            $script:DiscoverFilter = { $PesterBoundParameters.ContainsKey('Discover') }

            Mock Get-ADDomainController {
                [pscustomobject]@{ HostName = 'dc-local.contoso.com'; IsReadOnly = $false }
            } -ParameterFilter $script:IdentityFilter
            Mock Get-ADDomainController {
                [pscustomobject]@{ HostName = @('dc-found.contoso.com') }
            } -ParameterFilter $script:DiscoverFilter
        }

        It 'returns this computer when it is a writable DC' {
            Get-TargetDomainController | Should -Be 'dc-local.contoso.com'

            Should -Invoke Get-ADDomainController -Times 1 -Exactly -ParameterFilter {
                $Identity -eq $env:COMPUTERNAME
            }
            Should -Invoke Get-ADDomainController -Times 0 -Exactly -ParameterFilter (
                $script:DiscoverFilter
            )
        }

        It 'discovers a writable DC when this computer is a read-only DC' {
            Mock Get-ADDomainController {
                [pscustomobject]@{ HostName = 'rodc-local.contoso.com'; IsReadOnly = $true }
            } -ParameterFilter $script:IdentityFilter

            Get-TargetDomainController | Should -Be 'dc-found.contoso.com'

            Should -Invoke Get-ADDomainController -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Discover') -and $Writable
            }
        }

        It 'discovers a writable DC when this computer is not a DC' {
            Mock Get-ADDomainController {
                throw 'Cannot find an object with identity'
            } -ParameterFilter $script:IdentityFilter

            Get-TargetDomainController | Should -Be 'dc-found.contoso.com'
        }

        It 'throws when this computer is not a DC and discovery fails' {
            Mock Get-ADDomainController {
                throw 'Cannot find an object with identity'
            } -ParameterFilter $script:IdentityFilter
            Mock Get-ADDomainController {
                throw 'The server is not operational'
            } -ParameterFilter $script:DiscoverFilter

            { Get-TargetDomainController } | Should -Throw '*not operational*'
        }
    }
}
