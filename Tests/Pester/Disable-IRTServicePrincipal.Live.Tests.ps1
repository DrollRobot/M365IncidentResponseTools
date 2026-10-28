#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live destructive tests for Disable-IRTServicePrincipal and Enable-IRTServicePrincipal.

.DESCRIPTION
    These tests change the test tenant: they register a throwaway application with a
    service principal, disable the service principal with Disable-IRTServicePrincipal,
    enable it again with Enable-IRTServicePrincipal, then delete the application. They
    run only through '.\Tests.ps1 Destructive', after Tests\Confirm-RemoteDisposable.ps1
    confirms the tenant is marked disposable.

    The service principal object passed in carries only the fields the functions read:
    Id, AppId, AppDisplayName, and DisplayName. AfterAll deletes the application, which
    takes its service principal with it, and then purges it from deleted items.

    Write-IRT is mocked to print every message, and Error-level messages fail
    the test.

    Prerequisites:
      - An active Graph session to the test tenant. PreTests.ps1 opens one for
        Destructive runs. Registering the application, and enabling or disabling
        its service principal, need Application.ReadWrite.All, which Connect-IRT
        requests, and the Application Administrator or Cloud Application
        Administrator role.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Disable-IRTServicePrincipal and Enable-IRTServicePrincipal (live)' -Tag @(
        'live', 'integration', 'destructive', 'remote'
    ) {

        BeforeAll {
            # InModuleScope makes $script: the module's scope, shared with other test
            # files. Clear this first, so AfterAll never deletes an app left over from
            # another file.
            $script:AppObjectId = $null

            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Service principal online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }

            Import-IRTModule -Name 'Microsoft.Graph.Applications'

            # Returns the service principal with this object ID, or nothing once it is gone.
            function Get-TestServicePrincipal {
                param([Parameter(Mandatory)][string] $Id)
                $GetParams = @{
                    ServicePrincipalId = $Id
                    Property           = 'id', 'accountEnabled'
                    ErrorAction        = 'Stop'
                }
                try {
                    Get-MgServicePrincipal @GetParams
                }
                catch {
                    if ("$_" -notmatch 'Request_ResourceNotFound') { throw }
                }
            }

            $Name = "IRT-LIVE-TEST-$((New-Guid).Guid.Substring(0, 8))"
            $NewAppRequest = @{
                Method      = 'POST'
                Uri         = 'v1.0/applications'
                Body        = @{ displayName = $Name } | ConvertTo-Json
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }
            $App = Invoke-MgGraphRequest @NewAppRequest
            $script:AppObjectId = $App.id
            Write-Host "Registered test application $Name ($($script:AppObjectId))."

            $NewSpRequest = @{
                Method      = 'POST'
                Uri         = 'v1.0/servicePrincipals'
                Body        = @{ appId = $App.appId } | ConvertTo-Json
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }
            $script:SpId = (Invoke-MgGraphRequest @NewSpRequest).id

            # a new service principal can take a few seconds to show up
            $Sp = $null
            for ($i = 0; $i -lt 12 -and -not $Sp; $i++) {
                $Sp = Get-TestServicePrincipal -Id $script:SpId
                if (-not $Sp) { Start-Sleep -Seconds 5 }
            }
            if (-not $Sp) {
                throw "Test service principal $($script:SpId) never became readable."
            }
            if (-not $Sp.AccountEnabled) {
                throw "Test service principal $($script:SpId) was created disabled."
            }

            $script:SpObject = [pscustomobject]@{
                Id             = $script:SpId
                AppId          = $App.appId
                AppDisplayName = $Name
                DisplayName    = $Name
            }

            # Print every message rather than hiding it, and fail on Error-level ones.
            Mock Write-IRT { Write-Host "[$Level] $Message" }
            Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                throw "Write-IRT error: $Message"
            }

            $null = Disable-IRTServicePrincipal -ServicePrincipalObject $script:SpObject
            $script:AfterDisable = Get-TestServicePrincipal -Id $script:SpId

            $null = Enable-IRTServicePrincipal -ServicePrincipalObject $script:SpObject
            $script:AfterEnable = Get-TestServicePrincipal -Id $script:SpId
        }

        AfterAll {
            if ($script:AppObjectId) {
                $DeleteParams = @{
                    Method      = 'DELETE'
                    Uri         = "v1.0/applications/$($script:AppObjectId)"
                    ErrorAction = 'SilentlyContinue'
                }
                $null = Invoke-MgGraphRequest @DeleteParams
                # a deleted app is kept for 30 days; purge it so the tenant stays clean
                $PurgeParams = @{
                    Method      = 'DELETE'
                    Uri         = "v1.0/directory/deletedItems/$($script:AppObjectId)"
                    ErrorAction = 'SilentlyContinue'
                }
                $null = Invoke-MgGraphRequest @PurgeParams
            }
        }

        It 'disables the service principal' {
            $script:AfterDisable.AccountEnabled | Should -BeFalse
        }

        It 'enables the service principal again' {
            $script:AfterEnable.AccountEnabled | Should -BeTrue
        }
    }
}
