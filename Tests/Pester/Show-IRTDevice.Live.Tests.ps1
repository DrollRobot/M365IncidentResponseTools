#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Show-IRTDevice.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Show-IRTDevice fetches the full Entra device and Intune managed
    device for each combined device object and prints them. Neither Graph call is
    mocked.

    Show-IRTDevice reports a failed Graph call with an Error-level Write-IRT
    message and moves on, so Write-IRT is mocked to print every message and fail
    the test on Error-level ones. Format-Tree is mocked to capture the records it
    would print, so the test can confirm both device records came back.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - The test tenant has at least one device enrolled in both Entra and Intune.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Show-IRTDevice (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Show-IRTDevice online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Printed = [System.Collections.Generic.List[object]]::new()
            Mock Format-Tree { $script:Printed.Add($InputObject) }

            # a device with both an Entra and an Intune record exercises both calls
            $script:Device = Request-GraphDevice |
                Where-Object { $_.Entra -and $_.Intune } |
                Select-Object -First 1
            if (-not $script:Device) {
                throw 'The test tenant has no device enrolled in both Entra and Intune.'
            }

            Show-IRTDevice -DeviceObject $script:Device
        }

        It 'prints the full Entra device record' {
            $script:Printed.Id | Should -Contain $script:Device.Entra.Id
        }

        It 'prints the full Intune managed device record' {
            $script:Printed.Id | Should -Contain $script:Device.Intune.Id
        }
    }
}
