#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Disable-IRTDevice and Remove-IRTDevice.

.DESCRIPTION
    These tests change the test tenant: they create a throwaway Entra device,
    disable it with Disable-IRTDevice, then delete it with Remove-IRTDevice. They
    run only through '.\Tests.ps1 Destructive', after
    Tests\Confirm-RemoteDisposable.ps1 confirms the tenant is marked disposable.

    Enable-IRTDevice makes the same call as Disable-IRTDevice, so it is not run.
    The device is not enrolled in Intune, so Remove-IRTDevice's Intune delete
    (Remove-MgDeviceManagementManagedDevice) is not covered here.

    The device object passed in carries only the fields both functions read:
    DisplayName, OperatingSystem, Entra, and Intune. Remove-IRTDevice runs with
    -Force and -Confirm:$false, so it never prompts; Read-Host is mocked to throw
    in case it tries. If the delete fails, AfterAll deletes the device directly.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - An active Graph session to the test tenant. PreTests.ps1 opens one for
        Destructive runs. Creating the device needs Directory.AccessAsUser.All,
        which Connect-IRT requests.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Disable-IRTDevice and Remove-IRTDevice (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never deletes a device left over
            # from another file.
            $script:DeviceId = $null

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Device online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            Import-IRTModule -Name 'Microsoft.Graph.Identity.DirectoryManagement'

            # Returns the device with this object ID, or nothing once it is gone.
            function Get-TestDevice {
                param([Parameter(Mandatory)][string] $Id)
                $GetParams = @{
                    DeviceId    = $Id
                    Property    = 'id', 'accountEnabled'
                    ErrorAction = 'Stop'
                }
                try {
                    Get-MgDevice @GetParams
                }
                catch {
                    if ("$_" -notmatch 'Request_ResourceNotFound') { throw }
                }
            }

            $Name = "IRT-LIVE-TEST-$((New-Guid).Guid.Substring(0, 8))"
            $DeviceBody = @{
                accountEnabled         = $true
                alternativeSecurityIds = @(
                    @{
                        type = 2
                        key  = [Convert]::ToBase64String((New-Guid).ToByteArray())
                    }
                )
                deviceId               = (New-Guid).Guid
                displayName            = $Name
                operatingSystem        = 'Windows'
                operatingSystemVersion = '10.0.19045'
            }
            $NewRequest = @{
                Method      = 'POST'
                Uri         = 'v1.0/devices'
                Body        = $DeviceBody | ConvertTo-Json -Depth 3
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }
            $script:DeviceId = (Invoke-MgGraphRequest @NewRequest).id
            Write-Host "Created test device $Name ($($script:DeviceId))."

            # a new device can take a few seconds to show up
            $Device = $null
            for ($i = 0; $i -lt 12 -and -not $Device; $i++) {
                $Device = Get-TestDevice -Id $script:DeviceId
                if (-not $Device) { Start-Sleep -Seconds 5 }
            }
            if (-not $Device) {
                throw "Test device $($script:DeviceId) never became readable."
            }

            $script:DeviceObject = [pscustomobject]@{
                DisplayName     = $Name
                OperatingSystem = 'Windows'
                Entra           = $Device
                Intune          = $null
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }
            Mock Read-Host { throw 'Read-Host must not run.' }

            $null = Disable-IRTDevice -DeviceObject $script:DeviceObject
            $script:AfterDisable = Get-TestDevice -Id $script:DeviceId

            $RemoveParams = @{
                DeviceObject = $script:DeviceObject
                Force        = $true
                Confirm      = $false
            }
            $null = Remove-IRTDevice @RemoveParams

            # a deleted device can take a few seconds to disappear
            $script:Gone = $false
            for ($i = 0; $i -lt 12 -and -not $script:Gone; $i++) {
                $script:Gone = -not (Get-TestDevice -Id $script:DeviceId)
                if (-not $script:Gone) { Start-Sleep -Seconds 5 }
            }
        }

        AfterAll {
            if ($script:DeviceId -and (Get-TestDevice -Id $script:DeviceId)) {
                Remove-MgDevice -DeviceId $script:DeviceId
            }
        }

        It 'disables the device' {
            $script:AfterDisable.AccountEnabled | Should -BeFalse
        }

        It 'deletes the device' {
            $script:Gone | Should -BeTrue
        }
    }
}
