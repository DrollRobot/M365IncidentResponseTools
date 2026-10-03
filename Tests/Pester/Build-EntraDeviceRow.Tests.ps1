#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the Build-EntraDeviceRow private helper.

.DESCRIPTION
    Build-EntraDeviceRow is a pure transformation (no I/O, no Graph), so it is
    dot-sourced and tested directly with synthetic Graph device objects -- no
    mocking required. Covers newest-first sorting, null-date placement, JoinType
    mapping, owner UPN resolution, local-time date conversion, the Raw JSON
    column, and empty input.
#>

BeforeAll {
    $Dir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Source\Private\Device'
    . (Join-Path -Path $Dir -ChildPath 'Build-EntraDeviceRow.ps1')

    function New-DeviceRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [datetime] $RegistrationDateTime = ([datetime]'2024-01-01'),
            [string]   $TrustType = 'AzureAd',
            [string]   $OwnerUpn = 'owner@contoso.com',
            [switch]   $NoRegistrationDate
        )
        $RegValue = if ($NoRegistrationDate) { $null } else { $RegistrationDateTime }
        $Owners = @()
        if ($OwnerUpn) {
            $Owners = @(
                [pscustomobject]@{ AdditionalProperties = @{ userPrincipalName = $OwnerUpn } }
            )
        }
        [pscustomobject]@{
            Id                            = [string][guid]::NewGuid()
            DeviceId                      = [string][guid]::NewGuid()
            DisplayName                   = 'DEV-TEST'
            AccountEnabled                = $true
            OperatingSystem               = 'Windows'
            OperatingSystemVersion        = '10.0.19045'
            TrustType                     = $TrustType
            RegistrationDateTime          = $RegValue
            ApproximateLastSignInDateTime = $RegValue
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

Describe 'Build-EntraDeviceRow' -Tag 'unit' {

    Context 'sorting' {

        It 'orders rows newest registration first' {
            $Devices = @(
                New-DeviceRecord -RegistrationDateTime ([datetime]'2024-03-01')
                New-DeviceRecord -RegistrationDateTime ([datetime]'2024-05-01')
                New-DeviceRecord -RegistrationDateTime ([datetime]'2024-01-01')
            )
            $Rows = Build-EntraDeviceRow -Device $Devices

            $Rows[0].RegistrationDateTime | Should -Be ([datetime]'2024-05-01').ToLocalTime()
            $Rows[-1].RegistrationDateTime | Should -Be ([datetime]'2024-01-01').ToLocalTime()
        }

        It 'places devices with no registration date last' {
            $Devices = @(
                New-DeviceRecord -RegistrationDateTime ([datetime]'2024-03-01')
                New-DeviceRecord -NoRegistrationDate
                New-DeviceRecord -RegistrationDateTime ([datetime]'2024-05-01')
            )
            $Rows = Build-EntraDeviceRow -Device $Devices

            $Rows[-1].RegistrationDateTime | Should -BeNullOrEmpty
        }
    }

    Context 'join type mapping' {

        It 'maps AzureAd to Entra joined' {
            $Rows = Build-EntraDeviceRow -Device @(New-DeviceRecord -TrustType 'AzureAd')
            $Rows[0].JoinType | Should -Be 'Entra joined'
        }

        It 'maps ServerAd to Hybrid joined' {
            $Rows = Build-EntraDeviceRow -Device @(New-DeviceRecord -TrustType 'ServerAd')
            $Rows[0].JoinType | Should -Be 'Hybrid joined'
        }

        It 'maps Workplace to Entra registered' {
            $Rows = Build-EntraDeviceRow -Device @(New-DeviceRecord -TrustType 'Workplace')
            $Rows[0].JoinType | Should -Be 'Entra registered'
        }

        It 'passes an unknown TrustType through unchanged' {
            $Rows = Build-EntraDeviceRow -Device @(New-DeviceRecord -TrustType 'SomethingNew')
            $Rows[0].JoinType | Should -Be 'SomethingNew'
        }
    }

    Context 'row content' {

        It 'resolves the registered owner UPN' {
            $Device = New-DeviceRecord -OwnerUpn 'alice@contoso.com'
            $Rows = Build-EntraDeviceRow -Device @($Device)
            $Rows[0].RegisteredOwnerUPN | Should -Be 'alice@contoso.com'
        }

        It 'exposes the date as a DateTime and Raw as valid JSON' {
            $Rows = Build-EntraDeviceRow -Device @(New-DeviceRecord)
            $Rows[0].RegistrationDateTime | Should -BeOfType [datetime]
            { $Rows[0].Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context 'empty input' {

        It 'returns no rows for an empty collection' {
            $Rows = Build-EntraDeviceRow -Device @()
            @($Rows).Count | Should -Be 0
        }
    }
}
