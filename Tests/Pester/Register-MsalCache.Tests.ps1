#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Register-MsalCache and Clear-IRTTokenCache.

.DESCRIPTION
    Get-MsalCacheHelper is mocked to return a fake helper that records its calls, so no
    keyring, Keychain, or DPAPI store is touched. The keyring checks run only off
    Windows, and the Windows check only on Windows, so each platform covers its own
    path.

-- Register-MsalCache ------------------------------------------------------

    'checks the OS keyring before registering off Windows'
        The cache used to be refused outright off Windows.
    'refuses to register when the keyring is not usable'
        There is no unencrypted fallback.

-- Clear-IRTTokenCache -----------------------------------------------------

    'clears the keyring entry off Windows'
        Off Windows the tokens live in the keyring, not the cache file, so deleting
        the file alone would leave them behind.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        # A stand-in MsalCacheHelper that records each call in order.
        function script:New-FakeCacheHelper {
            param([scriptblock] $Verify = {}, [scriptblock] $ClearAction = {})
            $Fake = [pscustomobject]@{
                Calls    = [System.Collections.Generic.List[string]]::new()
                OnVerify = $Verify
                OnClear  = $ClearAction
            }
            $Fake | Add-Member -MemberType ScriptMethod -Name RegisterCache -Value {
                param($Cache)
                $this.Calls.Add("register:$Cache")
            }
            $Fake | Add-Member -MemberType ScriptMethod -Name VerifyPersistence -Value {
                $this.Calls.Add('verify')
                & $this.OnVerify
            }
            $Fake | Add-Member -MemberType ScriptMethod -Name Clear -Value {
                $this.Calls.Add('clear')
                & $this.OnClear
            }
            $Fake
        }
        $script:App = [pscustomobject]@{ UserTokenCache = 'user-cache' }
    }

    Describe 'Register-MsalCache' -Tag 'unit' {

        BeforeEach {
            Mock Import-IRTModule { }
            $script:Helper = New-FakeCacheHelper
            Mock Get-MsalCacheHelper { $script:Helper }
        }

        It "registers the cache against the app's user token cache" {
            Register-MsalCache -App $script:App -CachePath 'cache.bin'
            $script:Helper.Calls | Should -Contain 'register:user-cache'
        }

        It 'checks the OS keyring before registering off Windows' -Tag 'regression' {
            if ($IsWindows) {
                Set-ItResult -Skipped -Because 'Windows keeps the cache in a DPAPI file'
                return
            }
            Register-MsalCache -App $script:App -CachePath 'cache.bin'
            $script:Helper.Calls | Should -Be @('verify', 'register:user-cache')
        }

        It 'refuses to register when the keyring is not usable' {
            if ($IsWindows) {
                Set-ItResult -Skipped -Because 'Windows keeps the cache in a DPAPI file'
                return
            }
            $script:Helper = New-FakeCacheHelper -Verify { throw 'no secret service' }
            { Register-MsalCache -App $script:App -CachePath 'cache.bin' } |
                Should -Throw '*keyring*no secret service*'
            $script:Helper.Calls | Should -Not -Contain 'register:user-cache'
        }

        It 'does not check a keyring on Windows' {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because 'only Windows skips the keyring check'
                return
            }
            Register-MsalCache -App $script:App -CachePath 'cache.bin'
            $script:Helper.Calls | Should -Not -Contain 'verify'
        }
    }

    Describe 'Clear-IRTTokenCache' -Tag 'unit' {

        BeforeAll {
            $script:SavedSession = $Global:IRT_Session
            $script:SavedConfig = $Global:IRT_Config
        }

        AfterAll {
            $Global:IRT_Session = $script:SavedSession
            $Global:IRT_Config = $script:SavedConfig
        }

        BeforeEach {
            $Global:IRT_Session = $null
            $CachePath = Join-Path -Path $TestDrive -ChildPath 'IRT-Cache.bin'
            $Global:IRT_Config = [pscustomobject]@{ MsalCachePath = $CachePath }
            $script:Helper = New-FakeCacheHelper
            Mock Get-MsalCacheHelper { $script:Helper }
            Mock Write-IRT { }
        }

        It 'clears the keyring entry off Windows' -Tag 'regression' {
            if ($IsWindows) {
                Set-ItResult -Skipped -Because 'Windows keeps the cache in the deleted file'
                return
            }
            Clear-IRTTokenCache -Confirm:$false
            $script:Helper.Calls | Should -Contain 'clear'
        }

        It 'leaves the keyring alone with -WhatIf' {
            Clear-IRTTokenCache -WhatIf
            $script:Helper.Calls | Should -Not -Contain 'clear'
        }

        It 'warns when the keyring cannot be cleared' {
            if ($IsWindows) {
                Set-ItResult -Skipped -Because 'Windows does not use a keyring'
                return
            }
            $script:Helper = New-FakeCacheHelper -ClearAction { throw 'locked' }
            Clear-IRTTokenCache -Confirm:$false
            Should -Invoke Write-IRT -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Warn' -and $Message -like '*keyring*locked*'
            }
        }

        It 'deletes the cache file' {
            Set-Content -Path $Global:IRT_Config.MsalCachePath -Value 'x'
            Clear-IRTTokenCache -Confirm:$false
            Test-Path -Path $Global:IRT_Config.MsalCachePath | Should -BeFalse
        }
    }
}
