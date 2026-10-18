#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-UnknownObject's handling of a failed lookup.

.DESCRIPTION
    Get-UnknownObject names an object from the cached Graph lists, falling back to
    Get-MgDirectoryObject. A deleted object, such as one named in an old audit log, is
    normal and Graph reports it as Request_ResourceNotFound. Any other failure, such as
    access denied, used to look exactly like not found. As a temporary workaround, those
    other failures are reported while IRT_TEST_STRICT_ERRORS is '1'.

    The cached Graph lists are removed for the tests and put back afterwards, so every
    lookup reaches Get-MgDirectoryObject, which is a global stub mocked in the module.
    Write-IRT prints every message, and Error-level ones are captured for the tests to
    check. The function's own "Unable to find object" error is captured with
    -ErrorVariable.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Get-MgDirectoryObject {
        [CmdletBinding()] param([string] $DirectoryObjectId)
        $null = $DirectoryObjectId
    }

    # An error shaped like the Graph SDK's. A Write-Error inside a Pester mock doesn't
    # keep its error ID, so the mocks throw one of these instead.
    function global:New-GraphError {
        param([string] $Code, [string] $Message)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message),
            "${Code},Microsoft.Graph.PowerShell.Cmdlets.GetMgDirectoryObject_Get",
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null)
    }

    $script:CacheNames = 'IRT_UsersById', 'IRT_GroupsById', 'IRT_ServicePrincipalsById'
    $script:SavedCaches = @(
        Get-Variable -Scope Global -Name $script:CacheNames -ErrorAction Ignore
    )
    Remove-Variable -Scope Global -Name $script:CacheNames -ErrorAction Ignore
    $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
}

AfterAll {
    $Stubs = 'Function:\Get-MgDirectoryObject', 'Function:\New-GraphError'
    Remove-Item -Path $Stubs -ErrorAction Ignore
    foreach ($Saved in $script:SavedCaches) {
        Set-Variable -Scope Global -Name $Saved.Name -Value $Saved.Value
    }
    $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
}

InModuleScope M365IncidentResponseTools {

    Describe 'Get-UnknownObject' -Tag 'unit' {

        BeforeAll {
            Mock Import-IRTModule { }

            # print every message; collect Error-level ones for the tests to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }

            $script:Id = '11111111-2222-3333-4444-555555555555'
        }

        BeforeEach {
            $script:Errors.Clear()
        }

        Context 'during a live test run' {

            BeforeAll {
                $env:IRT_TEST_STRICT_ERRORS = '1'
            }

            It 'keeps a deleted object quiet' {
                Mock Get-MgDirectoryObject {
                    throw (New-GraphError -Code 'Request_ResourceNotFound' -Message 'Not found')
                }

                Get-UnknownObject -Id $script:Id -ErrorVariable Failure 2>$null

                $script:Errors | Should -BeNullOrEmpty
                "$Failure" | Should -Match 'Unable to find object'
            }

            It 'reports any other failure' {
                Mock Get-MgDirectoryObject {
                    $Denied = @{
                        Code    = 'Authorization_RequestDenied'
                        Message = 'Insufficient privileges'
                    }
                    throw (New-GraphError @Denied)
                }

                Get-UnknownObject -Id $script:Id -ErrorVariable Failure 2>$null

                $script:Errors.Count | Should -Be 1
                $script:Errors[0] | Should -Match 'Insufficient privileges'
                "$Failure" | Should -Match 'Unable to find object'
            }
        }

        Context 'on a normal run' {

            BeforeAll {
                $env:IRT_TEST_STRICT_ERRORS = $null
            }

            It 'keeps any failure quiet' {
                Mock Get-MgDirectoryObject {
                    $Denied = @{
                        Code    = 'Authorization_RequestDenied'
                        Message = 'Insufficient privileges'
                    }
                    throw (New-GraphError @Denied)
                }

                Get-UnknownObject -Id $script:Id -ErrorVariable Failure 2>$null

                $script:Errors | Should -BeNullOrEmpty
                "$Failure" | Should -Match 'Unable to find object'
            }
        }
    }
}
