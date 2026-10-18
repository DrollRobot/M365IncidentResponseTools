#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-FullUserObject's optional properties.

.DESCRIPTION
    Graph has no way to select every property of a user, and a $select that names a
    property the user or tenant doesn't have fails the whole request. So
    Get-FullUserObject fetches the properties every user has, then asks for each optional
    property in its own request, all sent together in one Graph batch request. Each
    request comes back with its own status. A failed property is expected and
    unavoidable, so it stays quiet in every mode, including live test runs
    (IRT_TEST_STRICT_ERRORS = '1'). A failed batch request is a different matter and, as
    a temporary workaround, is reported during live test runs.

    Get-MgUser and Invoke-MgGraphRequest are global stubs mocked in the module. The batch
    mock answers every request from its body: 'aboutMe' fails with 403 and every other
    property comes back with a value. Write-IRT prints every message, and Error-level
    ones are captured for the tests to check.
#>

BeforeAll {
    # Get-FullUserObject's -UserObject parameter is typed with a class from this
    # module, so the function can't be called until it is loaded
    Import-Module -Name 'Microsoft.Graph.Users' -ErrorAction Stop

    # params exist only so Mock can bind them; a function takes precedence over the
    # module's own cmdlet
    function global:Get-MgUser {
        [CmdletBinding()] param([string] $UserId, [string[]] $Property)
        $null = $UserId, $Property
    }
    function global:Invoke-MgGraphRequest {
        [CmdletBinding()] param([string] $Method, [string] $Uri, $Body, [string] $ContentType)
        $null = $Method, $Uri, $Body, $ContentType
    }
    $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
}

AfterAll {
    Remove-Item -Path 'Function:\Get-MgUser', 'Function:\Invoke-MgGraphRequest' -ErrorAction Ignore
    $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
}

InModuleScope M365IncidentResponseTools {

    Describe 'Get-FullUserObject optional properties' -Tag 'unit' {

        BeforeAll {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }

            # print every message; collect Error-level ones for the tests to check
            $script:Errors = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                $script:Errors.Add($Message)
            }

            # the full fetch: a user with an empty slot for every property name
            Mock Get-MgUser {
                $User = [pscustomobject]@{ Id = 'user-1' }
                $Names = @(
                    'aboutMe', 'birthday', 'hireDate', 'interests', 'mailboxSettings'
                    'mailFolders', 'mySite', 'pastProjects', 'preferredName'
                    'responsibilities', 'schools', 'skills'
                )
                foreach ($Name in $Names) {
                    $User | Add-Member -NotePropertyName $Name -NotePropertyValue $null
                }
                $User
            }

            # answer each batched request from the body it was sent
            $script:BatchBody = $null
            $script:AnswerBatch = {
                param($Body)
                $script:BatchBody = $Body | ConvertFrom-Json
                $Responses = foreach ($Request in $script:BatchBody.requests) {
                    $Property = ($Request.url -split '\$select=')[1]
                    if ($Property -eq 'aboutMe') {
                        $Error403 = @{ error = @{ code = 'Forbidden'; message = 'Denied' } }
                        @{ id = $Request.id; status = 403; body = $Error403 }
                    }
                    else {
                        @{ id = $Request.id; status = 200; body = @{ $Property = 'value' } }
                    }
                }
                @{ responses = @($Responses) }
            }
        }

        BeforeEach {
            $script:Errors.Clear()
        }

        Context 'when the batch request succeeds' {

            BeforeAll {
                Mock Invoke-MgGraphRequest { & $script:AnswerBatch $Body }
            }

            It 'asks for the optional properties in one batch request' {
                $env:IRT_TEST_STRICT_ERRORS = $null

                $null = Get-FullUserObject -UserId 'user-1'

                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
                # Graph rejects a batch of more than 20 requests
                $script:BatchBody.requests.Count | Should -BeLessOrEqual 20
                foreach ($Request in $script:BatchBody.requests) {
                    $Request.url | Should -Match '^/users/user-1\?\$select=\w+$'
                }
            }

            It 'sets the properties that come back' {
                $env:IRT_TEST_STRICT_ERRORS = $null

                $User = Get-FullUserObject -UserId 'user-1'

                $User.birthday | Should -Be 'value'
                $User.skills | Should -Be 'value'
                $User.aboutMe | Should -BeNullOrEmpty
                $User.AllProperties | Should -BeTrue
            }

            It 'keeps a failed property quiet on a normal run' {
                $env:IRT_TEST_STRICT_ERRORS = $null

                $null = Get-FullUserObject -UserId 'user-1'

                $script:Errors | Should -BeNullOrEmpty
            }

            It 'keeps a failed property quiet during a live test run' {
                $env:IRT_TEST_STRICT_ERRORS = '1'

                $null = Get-FullUserObject -UserId 'user-1'

                $script:Errors | Should -BeNullOrEmpty
            }
        }

        Context 'when the batch request fails' {

            BeforeAll {
                Mock Invoke-MgGraphRequest { throw 'Service unavailable' }
            }

            It 'still returns the user, quietly, on a normal run' {
                $env:IRT_TEST_STRICT_ERRORS = $null

                $User = Get-FullUserObject -UserId 'user-1'

                $User.AllProperties | Should -BeTrue
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'reports the failure during a live test run (temporary workaround)' {
                $env:IRT_TEST_STRICT_ERRORS = '1'

                $User = Get-FullUserObject -UserId 'user-1'

                $User.AllProperties | Should -BeTrue
                $script:Errors.Count | Should -Be 1
                $script:Errors[0] | Should -Match 'batch failed.*Service unavailable'
            }
        }
    }
}
