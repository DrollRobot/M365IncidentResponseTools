#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Request-IntuneDevice.

.DESCRIPTION
    A tenant without an Intune license rejects the managedDevices call with the same
    403 Forbidden as a caller without permission. Request-IntuneDevice tells the two
    apart by checking the tenant's licenses after a failure: with an active Intune plan
    the failure is reported as an error, otherwise it stays quiet.

    The Graph cmdlets are replaced by global stubs and mocked inside the module.
    Write-IRT prints every message. Error-level messages, which one test expects, are
    captured and asserted on rather than hidden.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Get-MgDeviceManagementManagedDevice {
        [CmdletBinding()] param([switch] $All)
        $null = $All
    }
    function global:Get-MgSubscribedSku {
        [CmdletBinding()] param()
    }
    function global:New-TestSku {
        param(
            [string[]] $PlanName,
            [string] $CapabilityStatus = 'Enabled',
            [string] $ProvisioningStatus = 'Success'
        )
        [pscustomobject]@{
            CapabilityStatus = $CapabilityStatus
            ServicePlans     = @(
                $PlanName | ForEach-Object {
                    [pscustomobject]@{
                        ServicePlanName    = $_
                        ProvisioningStatus = $ProvisioningStatus
                    }
                }
            )
        }
    }
}

AfterAll {
    'Get-MgDeviceManagementManagedDevice', 'Get-MgSubscribedSku', 'New-TestSku' |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction Ignore }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Request-IntuneDevice' -Tag 'unit' {

        BeforeAll {
            Mock Import-IRTModule { }
            Mock Get-MgSubscribedSku { }

            # print every message; collect Error-level ones for the tests to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }
        }

        BeforeEach {
            $script:Errors.Clear()
        }

        It 'returns the managed devices without checking licenses' {
            Mock Get-MgDeviceManagementManagedDevice { [pscustomobject]@{ Id = 'managed-1' } }

            $Result = @(Request-IntuneDevice)

            $Result.Id | Should -Be 'managed-1'
            Should -Invoke Get-MgSubscribedSku -Times 0 -Exactly
            $script:Errors | Should -BeNullOrEmpty
        }

        Context 'when the managed device call fails' {

            BeforeAll {
                Mock Get-MgDeviceManagementManagedDevice { throw 'Forbidden' }
            }

            It 'reports an error when an active Intune plan is licensed' {
                Mock Get-MgSubscribedSku {
                    New-TestSku -PlanName 'EXCHANGE_S_ENTERPRISE', 'INTUNE_A'
                }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors.Count | Should -Be 1
                $script:Errors[0] | Should -Match 'Forbidden'
            }

            It 'stays quiet when the tenant has no Intune plan' {
                Mock Get-MgSubscribedSku { New-TestSku -PlanName 'EXCHANGE_S_ENTERPRISE' }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'stays quiet when only Basic Mobility and Security is licensed' {
                Mock Get-MgSubscribedSku { New-TestSku -PlanName 'INTUNE_O365' }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'stays quiet when the Intune plan is not provisioned' {
                Mock Get-MgSubscribedSku {
                    New-TestSku -PlanName 'INTUNE_A' -ProvisioningStatus 'PendingActivation'
                }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'stays quiet when the subscription is suspended' {
                Mock Get-MgSubscribedSku {
                    New-TestSku -PlanName 'INTUNE_A' -CapabilityStatus 'Suspended'
                }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'stays quiet when the license check itself fails' {
                Mock Get-MgSubscribedSku { throw 'Forbidden' }

                Request-IntuneDevice | Should -BeNullOrEmpty
                $script:Errors | Should -BeNullOrEmpty
            }
        }
    }
}
