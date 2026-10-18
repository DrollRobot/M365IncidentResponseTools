#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live tests for Get-FullUserObject.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by Connect-IRT.
    Get-FullUserObject fetches the test user's always-present properties, then asks for
    each optional property in one Graph batch request. Nothing is mocked except
    Write-IRT.

    To check the batch against Graph itself, each optional property is also asked for
    the old way, one Get-MgUser call per property. Wherever that direct call returns a
    value for the test user, the batch must have returned the same value. Properties the
    test user doesn't have are skipped, since which ones exist depends on the user and
    tenant.

    Write-IRT is mocked to print every message, and Error-level messages fail the test.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - IRT_TEST_USER_ID must be set to a valid user GUID (see Tests/.env.ps1).
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-FullUserObject (live)' -Tag 'live', 'integration' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-FullUserObject online tests require an active Graph ' +
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

            $script:User = Get-FullUserObject -UserId $env:IRT_TEST_USER_ID

            # the same optional properties, asked for one at a time
            $script:Direct = @{}
            $Optional = @(
                'aboutMe', 'birthday', 'hireDate', 'interests', 'mailboxSettings'
                'mailFolders', 'mySite', 'pastProjects', 'preferredName'
                'responsibilities', 'schools', 'skills'
            )
            foreach ($Property in $Optional) {
                try {
                    $GetParams = @{
                        UserId      = $env:IRT_TEST_USER_ID
                        Property    = $Property
                        ErrorAction = 'Stop'
                    }
                    $Value = (Get-MgUser @GetParams).$Property
                    if ("$Value") { $script:Direct[$Property] = $Value }
                }
                catch {
                    Write-Host "[Info] $Property is not available for the test user: $_"
                }
            }
        }

        It 'returns the full user' {
            $script:User.Id | Should -Be $env:IRT_TEST_USER_ID
            $script:User.AllProperties | Should -BeTrue
        }

        It 'returns every optional property the user has, matching a direct query' {
            if ($script:Direct.Count -eq 0) {
                Set-ItResult -Skipped -Because 'the test user has no optional properties set'
                return
            }
            foreach ($Property in $script:Direct.Keys) {
                "$($script:User.$Property)" | Should -Be "$($script:Direct[$Property])" -Because (
                    "the batch must return the same '$Property' as a direct query")
            }
        }
    }
}
