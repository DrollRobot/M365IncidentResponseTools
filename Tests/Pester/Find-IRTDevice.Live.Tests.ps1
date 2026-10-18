#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Find-IRTDevice.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Nothing that talks to Graph is mocked: Find-IRTDevice builds its
    combined Entra + Intune device list from the real devices and managedDevices
    endpoints.

    The Intune half is the one that can fail quietly: Request-IntuneDevice
    returns nothing when the managedDevices call fails, so a missing permission
    looks the same as a tenant without Intune. BeforeAll queries managedDevices
    directly (failing loudly), and the tests then require every Intune device to
    appear in Find-IRTDevice's results.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - The test tenant has at least one Entra device.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Find-IRTDevice (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Find-IRTDevice online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:EntraDevices = @(Get-MgDevice -All -ErrorAction Stop)
            $script:IntuneDevices = @(
                Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
            )
            if ($script:EntraDevices.Count -eq 0) {
                throw 'The test tenant has no Entra devices to search for.'
            }

            # search for a device by its exact display name
            $script:Target = $script:EntraDevices[0]
            $Pattern = "^$([regex]::Escape($script:Target.DisplayName))$"
            $script:Found = @(Find-IRTDevice -Search $Pattern -AllMatches -Script)
        }

        It 'finds the device searched for' {
            $script:Found.Count | Should -BeGreaterThan 0
            $script:Found.DeviceId | Should -Contain $script:Target.DeviceId
        }

        It 'includes Intune data for every Intune device' {
            if ($script:IntuneDevices.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the test tenant has no Intune devices'
                return
            }
            # every Intune device should come back from the combined list, either
            # joined to its Entra record or on its own
            $AllCombined = @(Request-GraphDevice -Cached)
            foreach ($IntuneDevice in $script:IntuneDevices) {
                $AllCombined.Intune.Id | Should -Contain $IntuneDevice.Id -Because (
                    'Find-IRTDevice must not drop Intune data when managedDevices ' +
                    'is readable')
            }
        }
    }
}
