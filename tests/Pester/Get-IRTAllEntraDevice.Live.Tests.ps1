#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-IRTAllEntraDevice.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. The Graph SDK cmdlet (Get-MgDevice) is NOT mocked; the query
    goes to the real Entra devices endpoint.

    Devices are pulled once in BeforeAll (the same query the function makes) and
    run through the real Build-EntraDeviceRow helper, so the live transformation
    (sort, JoinType mapping, owner resolution, date conversion) is asserted
    against real device shapes. A final context runs the full public function
    end-to-end with Export-Excel mocked (no workbook written) to confirm the whole
    query / build / export pipeline executes against live data.

    If the tenant happens to have no Entra devices, the data assertions skip
    rather than fail.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTAllEntraDevice (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTAllEntraDevice online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            $Props = @(
                'Id'
                'DeviceId'
                'DisplayName'
                'AccountEnabled'
                'OperatingSystem'
                'OperatingSystemVersion'
                'TrustType'
                'RegistrationDateTime'
                'ApproximateLastSignInDateTime'
                'IsCompliant'
                'IsManaged'
                'IsRooted'
                'DeviceOwnership'
                'EnrollmentType'
                'ProfileType'
                'ManagementType'
                'MdmAppId'
            )
            $script:LiveDevices = @(
                Get-MgDevice -All -Property $Props -ExpandProperty 'RegisteredOwners'
            )
            $script:Rows = @(Build-EntraDeviceRow -Device $script:LiveDevices)
        }

        It 'retrieves Entra devices (or skips when the tenant has none)' {
            if ($script:Rows.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the tenant has no Entra devices'
                return
            }
            $script:Rows.Count | Should -BeGreaterThan 0
        }

        It 'sorts the devices newest registration first' {
            if ($script:Rows.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the tenant has no Entra devices'
                return
            }
            $Dates = $script:Rows |
                Where-Object { $_.RegistrationDateTime } |
                ForEach-Object { $_.RegistrationDateTime }
            $Sorted = $Dates | Sort-Object -Descending
            $Dates | Should -Be $Sorted
        }

        It 'labels every device with a known JoinType' {
            if ($script:Rows.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the tenant has no Entra devices'
                return
            }
            $Known = @('Entra joined', 'Hybrid joined', 'Entra registered')
            foreach ($Row in $script:Rows) {
                # a friendly label, or a raw TrustType passthrough for unmapped values
                $Ok = ($Row.JoinType -in $Known) -or ($Row.JoinType -eq $Row.TrustType)
                $Ok | Should -BeTrue
            }
        }

        It 'never reports a registration date in the future' {
            if ($script:Rows.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the tenant has no Entra devices'
                return
            }
            $Cutoff = (Get-Date).AddDays(1)
            foreach ($Row in $script:Rows) {
                if ($Row.RegistrationDateTime) {
                    $Row.RegistrationDateTime | Should -BeLessOrEqual $Cutoff
                }
            }
        }

        Context 'full function end to end' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }
                Mock Export-Excel { }

                Get-IRTAllEntraDevice -Open $false -Xml $false
            }

            It 'runs end to end and exports when devices exist' {
                if ($script:Rows.Count -eq 0) {
                    Set-ItResult -Skipped -Because 'the tenant has no Entra devices'
                    return
                }
                Should -Invoke Export-Excel -Scope Context
            }
        }
    }
}
