#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTEntraSPSignInLog: service principal resolution, filter
    construction, gained date chunking, and output plumbing.

.DESCRIPTION
    All tests are offline. The Microsoft Graph SDK cmdlets (Get-MgBetaAuditLogSignIn,
    Get-MgAuditLogSignIn) and internal IRT helpers (Update-IRTToken, Import-IRTModule,
    Write-IRT, Write-PSFMessage, Get-DefaultDomain, Get-GlobalServicePrincipalObject,
    Resolve-DateRange, Show-IRTEntraSPSignInLog) are mocked so no network I/O
    occurs. Start-Sleep and Export-Clixml are mocked so retry/backoff paths and the XML
    export run instantly.

    The shared query/chunk/throttle engine (Invoke-IRTSignInLogQuery) is exercised
    through this wrapper rather than mocked, so chunking and dispatch are covered here.
    All Mocks use -ModuleName M365IncidentResponseTools so the intercepts apply to calls
    made from within the module.
#>

BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'

    # params exist only so Mock can bind -Filter for inspection; reference them
    # to satisfy PSReviewUnusedParameter
    function global:Get-MgBetaAuditLogSignIn {
        param([string] $Filter, $All)
        $null = $Filter, $All
    }
    function global:Get-MgAuditLogSignIn {
        param([string] $Filter, $All)
        $null = $Filter, $All
    }

    function global:New-SignInRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [datetime] $CreatedDateTime = ([datetime]'2024-01-15T00:00:00Z'),
            [string]   $Id
        )
        if (-not $Id) { $Id = [string][guid]::NewGuid() }
        [pscustomobject]@{
            Id              = $Id
            CreatedDateTime = $CreatedDateTime
            IpAddress       = '1.1.1.1'
        }
    }

    # fixed, deterministic 30-day UTC window for chunk-boundary math
    $script:RangeEnd = [datetime]::SpecifyKind([datetime]'2024-02-01T00:00:00', 'Utc')
    $script:RangeStart = $script:RangeEnd.AddDays(-30)

    $script:TestSP = [pscustomobject]@{
        Id          = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        DisplayName = 'Contoso App'
    }
}

AfterAll {
    @('Get-MgBetaAuditLogSignIn', 'Get-MgAuditLogSignIn', 'New-SignInRecord') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
}

Describe 'Get-IRTEntraSPSignInLog' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'

        Mock Update-IRTToken { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Start-Sleep { } -ModuleName $Mod
        Mock Export-Clixml { } -ModuleName $Mod
        Mock Get-DefaultDomain { 'contoso.com' } -ModuleName $Mod
        Mock Get-GlobalServicePrincipalObject { $script:TestSP } -ModuleName $Mod

        # captured side effects
        $script:CapturedFilters = [System.Collections.Generic.List[string]]::new()
        $script:CapturedLogs = $null
        Mock Show-IRTEntraSPSignInLog {
            param($Logs) $script:CapturedLogs = $Logs
        } -ModuleName $Mod

        # deterministic 30-day absolute range
        Mock Resolve-DateRange {
            [pscustomobject]@{
                RangeType = 'Absolute'
                Days      = 30
                StartUtc  = $script:RangeStart
                EndUtc    = $script:RangeEnd
            }
        } -ModuleName $Mod

        # default: every chunk returns one record and records its filter
        Mock Get-MgBetaAuditLogSignIn {
            $script:CapturedFilters.Add($Filter)
            New-SignInRecord
        } -ModuleName $Mod
        Mock Get-MgAuditLogSignIn {
            $script:CapturedFilters.Add($Filter)
            New-SignInRecord
        } -ModuleName $Mod
    }

    # -------------------------------------------------------------------
    Context 'service principal resolution' {

        It 'uses an explicitly passed -ServicePrincipalObject' {
            Get-IRTEntraSPSignInLog -ServicePrincipalObject $script:TestSP -Excel $false -Xml $false
            Should -Invoke Get-GlobalServicePrincipalObject -Times 0 -ModuleName $script:Mod
            $F = { $Filter -match "servicePrincipalId eq '$($script:TestSP.Id)'" }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Get-MgBetaAuditLogSignIn @IA
        }

        It 'falls back to Get-GlobalServicePrincipalObject when none is passed' {
            Get-IRTEntraSPSignInLog -Excel $false -Xml $false
            Should -Invoke Get-GlobalServicePrincipalObject -Times 1 -ModuleName $script:Mod
        }

        It 'writes an error and runs no query when none are found' {
            Mock Get-GlobalServicePrincipalObject { } -ModuleName $script:Mod
            Get-IRTEntraSPSignInLog -Excel $false -Xml $false
            $F = { $Level -eq 'Error' -and $Message -match 'No service principal objects' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 0 -ModuleName $script:Mod
        }

        It 'queries once per service principal for multiple values' {
            $SP2 = [pscustomobject]@{
                Id          = 'ffffffff-0000-1111-2222-333333333333'
                DisplayName = 'Fabrikam App'
            }
            $SPs = @($script:TestSP, $SP2)
            Get-IRTEntraSPSignInLog -ServicePrincipalObject $SPs -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 2 -Exactly @IA
        }

        It 'adds no service principal filter in the AllServicePrincipals set' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $false -Xml $false
            $script:CapturedFilters[0] | Should -Not -Match 'servicePrincipalId eq'
        }
    }

    # -------------------------------------------------------------------
    Context 'filter construction' {

        It 'always restricts to servicePrincipal sign-in events' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $false -Xml $false
            $Filter = $script:CapturedFilters[0]
            $Filter | Should -Match "signInEventTypes/any\(t: t eq 'servicePrincipal'\)"
        }

        It 'filters by servicePrincipalId for a specific SP' {
            $P = @{ ServicePrincipalObject = $script:TestSP; ChunkDays = 30 }
            Get-IRTEntraSPSignInLog @P -Excel $false -Xml $false
            $Filter = $script:CapturedFilters[0]
            $Filter | Should -Match "servicePrincipalId eq '$($script:TestSP.Id)'"
        }

        It 'every chunk filter carries explicit createdDateTime bounds' {
            $P = @{ AllServicePrincipals = $true; ChunkDays = 7 }
            Get-IRTEntraSPSignInLog @P -Excel $false -Xml $false
            foreach ($f in $script:CapturedFilters) {
                $f | Should -Match 'createdDateTime ge '
                $f | Should -Match 'createdDateTime le '
            }
        }
    }

    # -------------------------------------------------------------------
    Context 'date chunking (gained from the shared engine)' {

        It 'runs a single query when ChunkDays covers the whole range' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 1 -Exactly @IA
        }

        It 'splits a 30-day range into 3 chunks with -ChunkDays 10' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 10 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 3 -Exactly @IA
        }
    }

    # -------------------------------------------------------------------
    Context 'output' {

        It 'dispatches to Show-IRTEntraSPSignInLog when logs are found' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $true -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Show-IRTEntraSPSignInLog -Times 1 -Exactly @IA
        }

        It 'does not dispatch to Show when -Excel is off' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $false -Xml $false
            Should -Invoke Show-IRTEntraSPSignInLog -Times 0 -ModuleName $script:Mod
        }

        It 'inserts SP-style metadata at the head of the results' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $true -Xml $false
            $script:CapturedLogs[0].Metadata | Should -BeTrue
            $script:CapturedLogs[0].FileNamePrefix | Should -Be 'SPSignInLogs'
            $script:CapturedLogs[0].FileName | Should -Match '^SPSignInLogs_'
            $script:CapturedLogs[0].Title | Should -Match '^Service principal sign-in logs for '
        }

        It 'writes a no-logs error and skips export when nothing is returned' {
            Mock Get-MgBetaAuditLogSignIn { @() } -ModuleName $script:Mod
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $true -Xml $false
            $F = { $Level -eq 'Error' -and $Message -match 'No logs found' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Show-IRTEntraSPSignInLog -Times 0 -ModuleName $script:Mod
        }

        It 'exports XML when -Xml is on' {
            Get-IRTEntraSPSignInLog -AllServicePrincipals -ChunkDays 30 -Excel $false -Xml $true
            Should -Invoke Export-Clixml -ModuleName $script:Mod
        }
    }
}
