#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Find-IRTDirectoryObject.

.DESCRIPTION
    Find-IRTDirectoryObject looks up each GUID in a block of text. A GUID that matches
    nothing is normal and reported with an informational message. Any other failed
    lookup, such as access denied, used to be written to the output stream as an error
    record, where nothing treated it as an error. It now goes to the error stream.

    Get-MgDirectoryObject is replaced by a global stub and mocked inside the module.
    Each test runs the function with its output and error streams captured separately.
    Write-IRT is mocked to print every message and fail the test on Error-level ones.
#>

BeforeAll {
    # params exist only so Mock can bind them
    function global:Get-MgDirectoryObject {
        [CmdletBinding()] param([string] $DirectoryObjectId)
        $null = $DirectoryObjectId
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Get-MgDirectoryObject' -ErrorAction Ignore
}

InModuleScope M365IncidentResponseTools {

    Describe 'Find-IRTDirectoryObject' -Tag 'unit' {

        BeforeAll {
            Mock Import-IRTModule { }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Guid = '11111111-2222-3333-4444-555555555555'
        }

        It 'sends a failed lookup to the error stream, not the output' {
            Mock Get-MgDirectoryObject {
                throw 'Insufficient privileges to complete the operation.'
            }

            $script:Output = @()
            $Run = { $script:Output = @(Find-IRTDirectoryObject -Content $script:Guid) }
            $Errors = @(& $Run 2>&1)

            "$Errors" | Should -Match 'Insufficient privileges'
            $InOutput = @($script:Output | Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord]
                })
            $InOutput | Should -BeNullOrEmpty
        }

        It 'reports a GUID that matches nothing without an error' {
            Mock Get-MgDirectoryObject {
                throw ("Resource '$DirectoryObjectId' does not exist or one of its queried " +
                    'reference-property objects are not present.')
            }

            $Errors = @(& { $null = Find-IRTDirectoryObject -Content $script:Guid } 2>&1)

            $Errors | Should -BeNullOrEmpty
            $NotFound = { $Message -eq 'Unable to find object.' }
            Should -Invoke Write-IRT -ParameterFilter $NotFound -Times 1 -Exactly
        }
    }
}
