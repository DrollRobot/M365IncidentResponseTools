#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTAllEntraDevice: Graph query shape and output plumbing.

.DESCRIPTION
    All tests are offline. The Microsoft Graph SDK cmdlet (Get-MgDevice), the
    ImportExcel cmdlet (Export-Excel), and the internal IRT helpers
    (Update-IRTToken, Import-IRTModule, Write-IRT, Write-PSFMessage,
    Get-DefaultDomain) are mocked so no network I/O or file writes occur.

    Get-MgDevice and Export-Excel only materialise after their modules import,
    and the function's Import-IRTModule call is mocked away here, so thin global
    stubs are created in BeforeAll. Export-Excel is mocked as a no-op; because the
    function guards all post-export formatting behind `if ($Workbook)` and the mock
    returns nothing, that block is skipped. All Mocks use
    -ModuleName M365IncidentResponseTools so the intercepts apply to calls made
    from within the module.

    The row-level transformations (sort, JoinType, owner, dates) are covered by the
    Build-EntraDeviceRow unit tests, which the function delegates to; these tests
    focus on the Graph query and the export/XML plumbing around it.
#>

BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'

    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:Get-MgDevice {
        param([switch] $All, [string[]] $Property, [string[]] $ExpandProperty)
        $null = $All, $Property, $ExpandProperty
    }
    function global:Export-Excel {
        param($TargetData, $Path, $WorkSheetname, $Title, $TableStyle)
        $null = $TargetData, $Path, $WorkSheetname, $Title, $TableStyle
    }

    function global:New-DeviceRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [datetime] $RegistrationDateTime = ([datetime]'2024-01-01'),
            [string]   $TrustType = 'AzureAd'
        )
        $Owners = @(
            [pscustomobject]@{
                AdditionalProperties = @{ userPrincipalName = 'owner@contoso.com' }
            }
        )
        [pscustomobject]@{
            Id                            = [string][guid]::NewGuid()
            DeviceId                      = [string][guid]::NewGuid()
            DisplayName                   = 'DEV-TEST'
            AccountEnabled                = $true
            OperatingSystem               = 'Windows'
            OperatingSystemVersion        = '10.0.19045'
            TrustType                     = $TrustType
            RegistrationDateTime          = $RegistrationDateTime
            ApproximateLastSignInDateTime = $RegistrationDateTime
            IsCompliant                   = $true
            IsManaged                     = $true
            IsRooted                      = $false
            DeviceOwnership               = 'Company'
            EnrollmentType                = 'AzureDomainJoined'
            ProfileType                   = 'RegisteredDevice'
            ManagementType                = 'MDM'
            MdmAppId                      = '0000000a-0000-0000-c000-000000000000'
            RegisteredOwners              = $Owners
        }
    }
}

AfterAll {
    @('Get-MgDevice', 'Export-Excel', 'New-DeviceRecord') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
}

Describe 'Get-IRTAllEntraDevice' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'

        Mock Update-IRTToken { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Export-Clixml { } -ModuleName $Mod
        Mock Get-DefaultDomain { 'contoso.com' } -ModuleName $Mod
        Mock Export-Excel { } -ModuleName $Mod

        # default: two devices
        Mock Get-MgDevice {
            New-DeviceRecord ([datetime]'2024-04-01') -TrustType 'AzureAd'
            New-DeviceRecord ([datetime]'2024-02-01') -TrustType 'Workplace'
        } -ModuleName $Mod
    }

    # -------------------------------------------------------------------
    Context 'graph query' {

        It 'queries every device with -All' {
            Get-IRTAllEntraDevice -Open $false -Xml $false
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $All } }
            Should -Invoke Get-MgDevice -Times 1 -Exactly @IA
        }

        It 'requests the registration date and trust type properties' {
            Get-IRTAllEntraDevice -Open $false -Xml $false
            $F = {
                $Property -contains 'RegistrationDateTime' -and
                $Property -contains 'TrustType'
            }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Get-MgDevice @IA
        }

        It 'expands the registered owners' {
            Get-IRTAllEntraDevice -Open $false -Xml $false
            $F = { $ExpandProperty -contains 'RegisteredOwners' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Get-MgDevice @IA
        }
    }

    # -------------------------------------------------------------------
    Context 'output' {

        It 'exports to Excel when devices are found' {
            Get-IRTAllEntraDevice -Open $false -Xml $false
            Should -Invoke Export-Excel -ModuleName $script:Mod
        }

        It 'warns and skips export when no devices are found' {
            Mock Get-MgDevice { @() } -ModuleName $script:Mod

            Get-IRTAllEntraDevice -Open $false -Xml $false

            $F = { $Level -eq 'Warn' -and $Message -match 'No devices found' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Export-Excel -Times 0 -ModuleName $script:Mod
        }

        It 'exports raw XML when -Xml is on' {
            Get-IRTAllEntraDevice -Open $false -Xml $true
            Should -Invoke Export-Clixml -ModuleName $script:Mod
        }

        It 'does not export XML when -Xml is off' {
            Get-IRTAllEntraDevice -Open $false -Xml $false
            Should -Invoke Export-Clixml -Times 0 -ModuleName $script:Mod
        }
    }
}
