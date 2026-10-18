#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the caching in the Request-* Graph helpers and Get-DefaultDomain.

.DESCRIPTION
    Each helper fetches a list from Graph and caches it in global variables, so later
    -Cached calls skip Graph. Graph SDK errors do not stop a function, so a failed fetch
    used to be cached as an empty list and handed back by every later -Cached call.

    These tests make the Graph cmdlet write an error, then check that nothing was cached
    and that the next -Cached call goes back to Graph. A successful fetch must still be
    cached and reused. Whether the error reaches the caller's -ErrorVariable is not
    checked: PowerShell leaves it out when the failing cmdlet sits in an assigned
    pipeline, as most of these calls do, and that is unchanged by the fix.

    The Graph cmdlets are replaced by global stubs, because Import-IRTModule is mocked and
    their modules are never imported, and the stubs are then mocked inside the module.
    Write-IRT is mocked to print every message and fail the test on Error-level ones.
    The expected Graph errors are the point of these tests, so only their console
    display is sent to $null.
#>

BeforeAll {
    # params exist only so Mock can bind them; CmdletBinding gives the stubs the common
    # parameters (-ErrorVariable) the helpers pass
    function global:Get-MgUser {
        [CmdletBinding()] param([switch] $All, [string[]] $Property)
        $null = $All, $Property
    }
    function global:Get-MgGroup {
        [CmdletBinding()] param([switch] $All, [string[]] $Property)
        $null = $All, $Property
    }
    function global:Get-MgGroupMember {
        [CmdletBinding()] param([string] $GroupId, [switch] $All)
        $null = $GroupId, $All
    }
    function global:Get-MgDirectoryRole {
        [CmdletBinding()] param([switch] $All, [string[]] $Property, [string[]] $ExpandProperty)
        $null = $All, $Property, $ExpandProperty
    }
    function global:Get-MgDirectoryRoleTemplate {
        [CmdletBinding()] param([switch] $All, [string[]] $Property)
        $null = $All, $Property
    }
    function global:Get-MgServicePrincipal {
        [CmdletBinding()] param([switch] $All)
        $null = $All
    }
    function global:Get-MgOauth2PermissionGrant {
        [CmdletBinding()] param([switch] $All)
        $null = $All
    }
    function global:Get-MgDevice {
        [CmdletBinding()] param([switch] $All, [string[]] $ExpandProperty)
        $null = $All, $ExpandProperty
    }
    function global:Get-MgDomain {
        [CmdletBinding()] param()
    }

    # leave any session caches as they were found
    $script:CacheNames = @(
        'IRT_Users', 'IRT_UsersById', 'IRT_Groups', 'IRT_GroupsById'
        'IRT_DirectoryRoles', 'IRT_DirectoryRolesById'
        'IRT_DirectoryRoleTemplates', 'IRT_DirectoryRoleTemplatesById'
        'IRT_ServicePrincipals', 'IRT_ServicePrincipalsByAppId', 'IRT_ServicePrincipalsById'
        'IRT_Oauth2Grants', 'IRT_Oauth2GrantsByClientId', 'IRT_Devices', 'IRT_DevicesById'
    )
    $script:SavedCaches = @(
        Get-Variable -Scope Global -Name $script:CacheNames -ErrorAction Ignore
    )
    $script:SavedSession = Get-Variable -Scope Global -Name 'IRT_Session' -ErrorAction Ignore
}

AfterAll {
    $Stubs = @(
        'Get-MgUser', 'Get-MgGroup', 'Get-MgGroupMember', 'Get-MgDirectoryRole'
        'Get-MgDirectoryRoleTemplate', 'Get-MgServicePrincipal'
        'Get-MgOauth2PermissionGrant', 'Get-MgDevice', 'Get-MgDomain'
    )
    $Stubs | ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction Ignore }

    Remove-Variable -Scope Global -Name $script:CacheNames -ErrorAction Ignore
    foreach ($Saved in $script:SavedCaches) {
        Set-Variable -Scope Global -Name $Saved.Name -Value $Saved.Value
    }
    Remove-Variable -Scope Global -Name 'IRT_Session' -ErrorAction Ignore
    if ($script:SavedSession) {
        Set-Variable -Scope Global -Name 'IRT_Session' -Value $script:SavedSession.Value
    }
}

InModuleScope M365IncidentResponseTools {

    Describe '<Helper> caching' -Tag 'unit' -ForEach @(
        @{ Helper = 'Request-GraphUser'; Cmdlet = 'Get-MgUser'
            Names = 'IRT_Users', 'IRT_UsersById' }
        @{ Helper = 'Request-GraphGroup'; Cmdlet = 'Get-MgGroup'
            Names = 'IRT_Groups', 'IRT_GroupsById' }
        @{ Helper = 'Request-DirectoryRole'; Cmdlet = 'Get-MgDirectoryRole'
            Names = 'IRT_DirectoryRoles', 'IRT_DirectoryRolesById' }
        @{ Helper = 'Request-DirectoryRoleTemplate'; Cmdlet = 'Get-MgDirectoryRoleTemplate'
            Names = 'IRT_DirectoryRoleTemplates', 'IRT_DirectoryRoleTemplatesById' }
        @{ Helper = 'Request-GraphServicePrincipal'; Cmdlet = 'Get-MgServicePrincipal'
            Names = 'IRT_ServicePrincipals', 'IRT_ServicePrincipalsByAppId',
            'IRT_ServicePrincipalsById' }
        @{ Helper = 'Request-GraphOauth2Grant'; Cmdlet = 'Get-MgOauth2PermissionGrant'
            Names = 'IRT_Oauth2Grants', 'IRT_Oauth2GrantsByClientId' }
        @{ Helper = 'Request-GraphDevice'; Cmdlet = 'Get-MgDevice'
            Names = 'IRT_Devices', 'IRT_DevicesById' }
    ) {

        BeforeAll {
            # These tests expect non-terminating errors, as the module sees them under
            # PowerShell's default preference. The pre-push hook runs with 'Stop'.
            $ErrorActionPreference = 'Continue'

            Mock Import-IRTModule { }
            Mock Get-DefaultDomain { 'contoso' }
            Mock Get-MgGroupMember { }
            Mock Request-IntuneDevice { }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            # one record with every property any of the helpers reads
            $script:Record = [pscustomobject]@{
                Id                   = 'id-1'
                AppId                = 'app-1'
                ClientId             = 'client-1'
                DeviceId             = 'device-1'
                DisplayName          = 'Record one'
                AdditionalProperties = @{}
                RegisteredOwners     = @()
            }
        }

        BeforeEach {
            Remove-Variable -Scope Global -Name $Names -ErrorAction Ignore
        }

        It 'does not cache a fetch that returns a Graph error' {
            Mock $Cmdlet { Write-Error 'Forbidden' }

            & $Helper -Xml $false 2>$null

            Get-Variable -Scope Global -Name $Names -ErrorAction Ignore |
                Should -BeNullOrEmpty
        }

        It 'goes back to Graph on the next -Cached call after a failure' {
            Mock $Cmdlet { Write-Error 'Forbidden' }

            & $Helper -Xml $false 2>$null
            & $Helper -Cached -Xml $false 2>$null

            Should -Invoke $Cmdlet -Times 2 -Exactly
        }

        It 'caches a successful fetch and serves -Cached calls from it' {
            Mock $Cmdlet { $script:Record }

            $First = @(& $Helper -Xml $false)
            $Second = @(& $Helper -Cached -Xml $false)

            Should -Invoke $Cmdlet -Times 1 -Exactly
            $First.Count | Should -Be 1
            $Second.Count | Should -Be 1
            foreach ($Name in $Names) {
                (Get-Variable -Scope Global -Name $Name).Value | Should -Not -BeNullOrEmpty
            }
        }
    }

    Describe 'Request-GraphGroup member lookups' -Tag 'unit' {

        BeforeAll {
            # These tests expect non-terminating errors, as the module sees them under
            # PowerShell's default preference. The pre-push hook runs with 'Stop'.
            $ErrorActionPreference = 'Continue'

            Mock Import-IRTModule { }
            Mock Get-DefaultDomain { 'contoso' }
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Get-MgGroup { [pscustomobject]@{ Id = 'group-1'; DisplayName = 'Hidden' } }
            Mock Get-MgGroupMember { Write-Error 'Forbidden' }
        }

        BeforeEach {
            Remove-Variable -Scope Global -Name 'IRT_Groups', 'IRT_GroupsById' -ErrorAction Ignore
        }

        It 'still caches the groups when one group hides its members' {
            Request-GraphGroup -Xml $false -ErrorVariable Failure 2>$null

            "$Failure" | Should -Match 'Forbidden'
            $Global:IRT_GroupsById.Keys | Should -Contain 'group-1'
        }
    }

    Describe 'Get-DefaultDomain caching' -Tag 'unit' {

        BeforeAll {
            # These tests expect non-terminating errors, as the module sees them under
            # PowerShell's default preference. The pre-push hook runs with 'Stop'.
            $ErrorActionPreference = 'Continue'

            Mock Import-IRTModule { }
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
        }

        BeforeEach {
            $Global:IRT_Session = [pscustomobject]@{ TenantId = 'tenant-1' }
        }

        It 'does not cache a lookup that returns a Graph error' {
            Mock Get-MgDomain { Write-Error 'Forbidden' }

            $null = Get-DefaultDomain 2>$null

            $Global:IRT_Session.PSObject.Properties.Name | Should -Not -Contain 'DefaultDomain'
        }

        It 'goes back to Graph on the next call after a failure' {
            Mock Get-MgDomain { Write-Error 'Forbidden' }

            $null = Get-DefaultDomain 2>$null
            $null = Get-DefaultDomain 2>$null

            Should -Invoke Get-MgDomain -Times 2 -Exactly
        }

        It 'caches a successful lookup' {
            Mock Get-MgDomain {
                [pscustomobject]@{ Id = 'other.com'; IsDefault = $false }
                [pscustomobject]@{ Id = 'contoso.com'; IsDefault = $true }
            }

            Get-DefaultDomain | Should -Be 'contoso'
            Get-DefaultDomain | Should -Be 'contoso'

            Should -Invoke Get-MgDomain -Times 1 -Exactly
        }
    }
}
