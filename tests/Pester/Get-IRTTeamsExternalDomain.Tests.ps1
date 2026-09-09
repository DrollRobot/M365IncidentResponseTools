#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTTeamsExternalDomain week chunking, file naming,
    resume behaviour, and metadata.

.DESCRIPTION
    All tests are offline. Get-IRTUnifiedAuditLog is mocked so no UAL query is
    ever issued, and Get-DefaultDomain is mocked so no Graph call is made.
    Resolve-DateRange is deliberately NOT mocked: the week-boundary maths is the
    thing under test, so it runs against the real date resolver with absolute
    -Start / -End values.

    Files are written into Pester's TestDrive.

-- week chunking --------------------------------------------------------

    The range is split on calendar weeks running Sunday through Saturday. An
    exact three-week Sunday-to-Sunday range produces three files, one per week.

-- file naming ----------------------------------------------------------

    Each file is named for the Sunday that begins its week, formatted yy-MM-dd,
    regardless of where inside the week the queried window actually starts.

-- partial weeks --------------------------------------------------------

    A range starting mid-week is clamped to the caller's range rather than
    widened back to Sunday. The first file is still named for that Sunday and
    its metadata carries PartialWeek = $true.

-- newest first ---------------------------------------------------------

    Weeks are queried newest first so the most recent activity lands on disk
    soonest. The mock records the -Start value of every call in order, so the
    recorded sequence must run backwards through the range.

-- empty weeks ----------------------------------------------------------

    A week with no matching records still gets a file, containing only the
    metadata row. A missing file means "not queried"; an empty file means
    "queried, nothing found".

-- resume ---------------------------------------------------------------

    Weeks that already have a file are skipped unless -Force is passed, so an
    interrupted run can be resumed without repeating completed work.

-- metadata -------------------------------------------------------------

    The child function's own metadata row is stripped and replaced with one
    describing the week. The operation list is passed through to the child.
#>

BeforeAll {
    # Builds a result set shaped like Get-IRTUnifiedAuditLog -PassThru output:
    # a metadata row at index 0 followed by UAL records. Global so it is
    # reachable from inside Mock body scriptblocks.
    function global:New-TedUALResult {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param([int] $Count)
        $List = [System.Collections.Generic.List[psobject]]::new()
        $List.Add([pscustomobject]@{
                Metadata       = $true
                FileNamePrefix = 'UnifiedAuditLogs'
                FileName       = 'child-metadata-should-be-stripped'
            })
        if ($Count -gt 0) {
            1..$Count | ForEach-Object {
                $List.Add([pscustomobject]@{
                        Identity     = [string][guid]::NewGuid()
                        Operations   = 'MessageSent'
                        CreationDate = [datetime]'2026-01-05'
                    })
            }
        }
        , $List
    }
}

AfterAll {
    Remove-Item -Path 'Function:\New-TedUALResult' -ErrorAction SilentlyContinue
}

Describe 'Get-IRTTeamsExternalDomain' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'
        # TestDrive lives for the whole container, so each test gets its own
        # subdirectory. Sharing one would leave earlier tests' files behind and
        # silently trip the resume/skip path.
        $TestPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $TestPath -ItemType 'Directory'
        # $script: scope persists across the BeforeEach/Mock boundary
        $script:TedStarts = [System.Collections.Generic.List[string]]::new()
        $script:TedOperations = $null
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Get-DefaultDomain { 'contoso' } -ModuleName $Mod
        Mock Get-IRTUnifiedAuditLog {
            $script:TedStarts.Add($Start)
            $script:TedOperations = $Operation
            New-TedUALResult -Count 3
        } -ModuleName $Mod
    }

    # -------------------------------------------------------------------
    Context 'week chunking' {

        It 'writes one file per Sunday-Saturday week' {
            # 2026-01-04 and 2026-01-25 are both Sundays: exactly three weeks.
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
            }
            $Files = @(Get-IRTTeamsExternalDomain @Params)
            $Files.Count | Should -Be 3
        }

        It 'names each file for the Sunday that begins its week' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
            }
            $Files = @(Get-IRTTeamsExternalDomain @Params)
            $Names = $Files.Name | Sort-Object
            $Expected = @(
                'TeamsExternalDomains_contoso_26-01-04.xml'
                'TeamsExternalDomains_contoso_26-01-11.xml'
                'TeamsExternalDomains_contoso_26-01-18.xml'
            )
            $Names | Should -Be $Expected
        }

        It 'queries weeks newest first' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $Expected = @(
                '2026-01-18 00:00:00'
                '2026-01-11 00:00:00'
                '2026-01-04 00:00:00'
            )
            $script:TedStarts | Should -Be $Expected
        }
    }

    # -------------------------------------------------------------------
    Context 'partial weeks' {

        It 'clamps a mid-week start but still names the file for the Sunday' {
            # 2026-01-07 is a Wednesday; its week begins Sunday 2026-01-04.
            $Params = @{
                Start = '2026-01-07'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $Files = @(Get-IRTTeamsExternalDomain @Params)
            $Files.Name | Should -Be 'TeamsExternalDomains_contoso_26-01-04.xml'
            $script:TedStarts | Should -Be @('2026-01-07 00:00:00')
        }

        It 'marks a clamped week as partial in the file metadata' {
            $Params = @{
                Start = '2026-01-07'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $File = Get-IRTTeamsExternalDomain @Params
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].PartialWeek | Should -BeTrue
        }

        It 'marks a whole week as not partial' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $File = Get-IRTTeamsExternalDomain @Params
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].PartialWeek | Should -BeFalse
        }
    }

    # -------------------------------------------------------------------
    Context 'empty weeks' {

        BeforeEach {
            Mock Get-IRTUnifiedAuditLog { } -ModuleName M365IncidentResponseTools
        }

        It 'still writes a file containing only the metadata row' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $File = Get-IRTTeamsExternalDomain @Params
            $Content = @(Import-Clixml -Path $File.FullName)
            $Content.Count | Should -Be 1
            $Content[0].Metadata | Should -BeTrue
            $Content[0].RecordCount | Should -Be 0
        }
    }

    # -------------------------------------------------------------------
    Context 'resume' {

        It 'skips a week whose file already exists' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $null = Get-IRTTeamsExternalDomain @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Get-IRTUnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }

        It 're-queries an existing week when -Force is passed' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $null = Get-IRTTeamsExternalDomain @Params -Force
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Get-IRTUnifiedAuditLog -Times 2 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'operations and metadata' {

        It 'queries all eight external-contact operations' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $Expected = @(
                'MessageSent'
                'MessageCreatedHasLink'
                'MessageUpdated'
                'MessageEditedHasLink'
                'ChatCreated'
                'MemberAdded'
                'ReactedToMessage'
                'CallParticipantDetail'
            )
            $script:TedOperations | Should -Be $Expected
        }

        It 'replaces the child metadata row with its own' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $File = Get-IRTTeamsExternalDomain @Params
            $Content = @(Import-Clixml -Path $File.FullName)
            # metadata row plus the three mocked records; the child's own
            # metadata row must not survive
            $Content.Count | Should -Be 4
            $Content[0].FileNamePrefix | Should -Be 'TeamsExternalDomains'
            $Content[0].RecordCount | Should -Be 3
            # StrictMode is active in the test scope, so probe for the property
            # rather than dereferencing it on records that do not carry it
            $Filter = { $_.PSObject.Properties['Metadata'] }
            @($Content | Where-Object $Filter).Count | Should -Be 1
        }

        It 'records the week start and tenant-ID-only operations in the metadata' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $File = Get-IRTTeamsExternalDomain @Params
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].WeekStart | Should -Be ([datetime]'2026-01-04')
            $ExpectedOps = @('ReactedToMessage', 'CallParticipantDetail')
            $Content[0].TenantIdOnlyOps | Should -Be $ExpectedOps
        }
    }

    # -------------------------------------------------------------------
    Context 'parameter validation' {

        It 'throws when -Path is not an existing directory' {
            $Missing = Join-Path -Path $TestPath -ChildPath 'does-not-exist'
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $Missing
            }
            { Get-IRTTeamsExternalDomain @Params } | Should -Throw
        }

        It 'throws when -Days is combined with -Start and -End' {
            $Params = @{
                Days  = 7
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            { Get-IRTTeamsExternalDomain @Params } | Should -Throw
        }
    }
}
