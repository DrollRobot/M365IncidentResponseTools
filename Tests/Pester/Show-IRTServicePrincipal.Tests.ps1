#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Show-IRTServicePrincipal.

.DESCRIPTION
    Show-IRTServicePrincipal prints several sections, each in its own try/catch that
    reports a failure with an Error-level message. The grant and directory role
    sections get their data from Request-* helpers, which report Graph errors without
    stopping. Without -ErrorAction Stop those errors slipped past the catch, and the
    grant section printed "No OAuth2 permission grants found" instead.

    The Graph cmdlets are replaced by global stubs and mocked inside the module.
    Write-IRT prints every message. Error-level messages, which these tests expect,
    are captured and asserted on rather than hidden.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Get-MgServicePrincipal {
        [CmdletBinding()] param([string] $ServicePrincipalId, [string[]] $Property)
        $null = $ServicePrincipalId, $Property
    }
    function global:Get-MgServicePrincipalAppRoleAssignment {
        [CmdletBinding()] param([string] $ServicePrincipalId, [switch] $All)
        $null = $ServicePrincipalId, $All
    }
    function global:Get-MgRoleManagementDirectoryRoleAssignment {
        [CmdletBinding()] param([string] $Filter, [switch] $All)
        $null = $Filter, $All
    }
    function global:Get-MgServicePrincipalAppRoleAssignedTo {
        [CmdletBinding()] param([string] $ServicePrincipalId, [switch] $All)
        $null = $ServicePrincipalId, $All
    }
}

AfterAll {
    $Stubs = @(
        'Get-MgServicePrincipal', 'Get-MgServicePrincipalAppRoleAssignment'
        'Get-MgRoleManagementDirectoryRoleAssignment', 'Get-MgServicePrincipalAppRoleAssignedTo'
    )
    $Stubs | ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction Ignore }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Show-IRTServicePrincipal' -Tag 'unit' {

        BeforeAll {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Get-MgServicePrincipal { [pscustomobject]@{ Id = 'sp-1'; AppRoles = @() } }
            Mock Show-GraphServicePrincipalTree { }
            Mock Get-MgServicePrincipalAppRoleAssignment { }
            Mock Get-MgRoleManagementDirectoryRoleAssignment { }
            Mock Get-MgServicePrincipalAppRoleAssignedTo { }
            Mock Request-GraphServicePrincipal { @{} }
            Mock Request-GraphUser { @{} }
            Mock Request-GraphOauth2Grant { @{} }
            Mock Request-DirectoryRoleTemplate { @{} }

            # print every message; collect Error-level ones for the tests to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }

            $script:Sp = [pscustomobject]@{ Id = 'sp-1'; AppDisplayName = 'App One' }
        }

        BeforeEach {
            $script:Errors.Clear()
        }

        It 'reports a failed grant lookup instead of an empty grant list' {
            Mock Request-GraphOauth2Grant { Write-Error 'Forbidden' }

            Show-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            $script:Errors | Should -Contain (
                'Failed to get OAuth2 permission grants: Forbidden')
            $NoGrants = { $Message -eq 'No OAuth2 permission grants found.' }
            Should -Invoke Write-IRT -ParameterFilter $NoGrants -Times 0 -Exactly
        }

        It 'reports a failed role template lookup' {
            Mock Request-DirectoryRoleTemplate { Write-Error 'Forbidden' }

            Show-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            $script:Errors | Should -Contain (
                'Failed to get directory role memberships: Forbidden')
        }

        It 'reports no errors when every lookup succeeds' {
            Show-IRTServicePrincipal -ServicePrincipalObject $script:Sp

            $script:Errors | Should -BeNullOrEmpty
        }
    }
}
