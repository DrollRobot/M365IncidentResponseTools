#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Find-IRTDirectoryObject.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. Find-IRTDirectoryObject pulls every GUID out of a block of text,
    looks each one up with Get-MgDirectoryObject, and prints the matching user,
    group, or service principal. No Graph call is mocked.

    The text holds one GUID of each supported type plus a random GUID that
    matches nothing. Format-Table is mocked to capture the objects that would be
    printed. A failed lookup other than "not found" is written to the error
    stream, which the test merges into the output to check for those.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - IRT_TEST_USER_ID must be set to a valid user GUID (see Tests/.env.ps1).
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Find-IRTDirectoryObject (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Find-IRTDirectoryObject online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_USER_ID not set. Run Tests/.env.ps1 first.'
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $script:Printed = [System.Collections.Generic.List[object]]::new()
            Mock Format-Table { $script:Printed.Add($InputObject) }

            $script:UserId = $env:IRT_TEST_USER_ID
            $script:GroupId = (Get-MgGroup -Top 1 -ErrorAction Stop).Id
            $SpFilter = "appId eq '14d82eec-204b-4c2f-b7e8-296a70dab67e'"
            $script:SpId = (Get-MgServicePrincipal -Filter $SpFilter -ErrorAction Stop).Id
            $script:MissingId = [guid]::NewGuid().ToString()

            $Content = "user $($script:UserId), group $($script:GroupId), " +
            "app $($script:SpId), nothing $($script:MissingId)"
            # 2>&1 brings failed lookups, written to the error stream, into the output
            $script:Output = @(Find-IRTDirectoryObject -Content $Content 2>&1)
        }

        It 'lists every GUID found in the text' {
            foreach ($Id in $script:UserId, $script:GroupId, $script:SpId, $script:MissingId) {
                $script:Output | Should -Contain $Id
            }
        }

        It 'prints the user, group, and service principal' {
            $script:Printed.Id | Should -Contain $script:UserId
            $script:Printed.Id | Should -Contain $script:GroupId
            $script:Printed.Id | Should -Contain $script:SpId
        }

        It 'reports no failed lookups' {
            # the random GUID must be treated as "not found", not as a failure
            $Failures = @($script:Output | Where-Object {
                    $_ -is [System.Management.Automation.ErrorRecord]
                })
            $Failures | Should -BeNullOrEmpty -Because "$($Failures -join '; ')"
        }
    }
}
