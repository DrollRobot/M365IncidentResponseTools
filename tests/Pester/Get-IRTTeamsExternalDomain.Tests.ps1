#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTTeamsExternalDomain week chunking, file naming,
    resume behaviour, week retry, and metadata.

.DESCRIPTION
    All tests are offline. In the unit block Get-IRTUnifiedAuditLog is mocked so
    no UAL query is ever issued, and Get-DefaultDomain is mocked so no Graph call
    is made. Resolve-DateRange is deliberately NOT mocked: the week-boundary maths
    is the thing under test, so it runs against the real date resolver with
    absolute -Start / -End values.

    The integration block runs the real Get-IRTUnifiedAuditLog and stubs only the
    Exchange cmdlets beneath it, so a -Week selection is checked all the way down
    to the window sent to Search-UnifiedAuditLog, and a week cut short by
    -ResultLimit is checked to carry the child's DATA MISSING marker into its file.

    Files are written into Pester's TestDrive. The function emits nothing to the
    pipeline, so tests find the files it wrote by listing -Path.

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

-- week retry -----------------------------------------------------------

    -Week limits the run to the named weeks, numbered newest first to match the
    "Week N of M" console label, so week 1 is the most recent. Named weeks are
    re-queried even when their file already exists, because a failed query
    still writes a file holding DATA MISSING markers. A week number beyond the
    range throws before any query runs.

-- metadata -------------------------------------------------------------

    The child function's own metadata row is stripped and replaced with one
    describing the week. The operation list is passed through to the child.

-- output ---------------------------------------------------------------

    Nothing is emitted to the pipeline; the files on disk are the output.
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

    # EXO proxy cmdlets only exist after Connect-ExchangeOnline. Thin global
    # stubs let the integration block Mock them via Get-Command. Parameter
    # names mirror the real cmdlet so the Mock body can read them by name.
    function global:Get-AcceptedDomain { }
    function global:Search-UnifiedAuditLog {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Stub exists only so Mock can bind parameters by name.')]
        param(
            $ResultSize,
            $SessionCommand,
            $Formatted,
            $StartDate,
            $EndDate,
            $UserIds,
            $FreeText,
            $Operations,
            $RecordType,
            $SessionId,
            [switch] $HighCompleteness
        )
    }
}

AfterAll {
    @('New-TedUALResult', 'Get-AcceptedDomain', 'Search-UnifiedAuditLog') | ForEach-Object {
        Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue
    }
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
            $null = Get-IRTTeamsExternalDomain @Params
            $Files = @(Get-ChildItem -Path $TestPath -Filter '*.xml')
            $Files.Count | Should -Be 3
        }

        It 'names each file for the Sunday that begins its week' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $Files = @(Get-ChildItem -Path $TestPath -Filter '*.xml')
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
            $null = Get-IRTTeamsExternalDomain @Params
            $Files = @(Get-ChildItem -Path $TestPath -Filter '*.xml')
            $Files.Name | Should -Be 'TeamsExternalDomains_contoso_26-01-04.xml'
            $script:TedStarts | Should -Be @('2026-01-07 00:00:00')
        }

        It 'marks a clamped week as partial in the file metadata' {
            $Params = @{
                Start = '2026-01-07'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].PartialWeek | Should -BeTrue
        }

        It 'marks a whole week as not partial' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
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
            $null = Get-IRTTeamsExternalDomain @Params
            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
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
    Context 'week retry' {

        It 'queries only the named week, counting week 1 as the newest' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
                Week  = 2
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $script:TedStarts | Should -Be @('2026-01-11 00:00:00')
        }

        It 'queries several named weeks newest first, whatever order they are given in' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
                Week  = 3, 1
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $Expected = @(
                '2026-01-18 00:00:00'
                '2026-01-04 00:00:00'
            )
            $script:TedStarts | Should -Be $Expected
        }

        It 'labels a named week with its number in the full range' {
            $script:TedMessages = [System.Collections.Generic.List[string]]::new()
            Mock Write-IRT {
                $script:TedMessages.Add($Message)
            } -ModuleName M365IncidentResponseTools
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
                Week  = 2
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $Filter = { $_ -like 'Week 2 of 3 (*): querying.' }
            @($script:TedMessages | Where-Object $Filter).Count | Should -Be 1
        }

        It 're-queries a named week whose file already exists without -Force' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $null = Get-IRTTeamsExternalDomain @Params -Week 2
            # three weeks on the first run, then the one named week
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Get-IRTUnifiedAuditLog -Times 4 -Exactly @InvokeArgs
        }

        It 'replaces a week file that came back with DATA MISSING markers' {
            $Mod = 'M365IncidentResponseTools'
            Mock Get-IRTUnifiedAuditLog {
                $Result = New-TedUALResult -Count 1
                $Result.Add([pscustomobject]@{
                        Identity   = 'IRT-DATA-GAP-test'
                        IRTDataGap = $true
                    })
                , $Result
            } -ModuleName $Mod
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params

            Mock Get-IRTUnifiedAuditLog { New-TedUALResult -Count 2 } -ModuleName $Mod
            $null = Get-IRTTeamsExternalDomain @Params -Week 1

            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].DataGapCount | Should -Be 0
        }

        It 'throws before querying when -Week is beyond the weeks in the range' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-25'
                Path  = $TestPath
                Week  = 4
            }
            $Run = { Get-IRTTeamsExternalDomain @Params }
            $Run | Should -Throw -ExpectedMessage '*out of range*'
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Get-IRTUnifiedAuditLog -Times 0 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'operations and metadata' {

        It 'queries all eleven external-contact operations' {
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
                'MeetingParticipantDetail'
                'CallParticipantDetail'
                'ReactedToMessage'
                'UserAccepted'
                'UserBlocked'
            )
            $script:TedOperations | Should -Be $Expected
        }

        It 'replaces the child metadata row with its own' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $null = Get-IRTTeamsExternalDomain @Params
            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
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
            $null = Get-IRTTeamsExternalDomain @Params
            $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
            $Content = Import-Clixml -Path $File.FullName
            $Content[0].WeekStart | Should -Be ([datetime]'2026-01-04')
            $ExpectedOps = @('ReactedToMessage', 'UserAccepted', 'UserBlocked')
            $Content[0].TenantIdOnlyOps | Should -Be $ExpectedOps
        }
    }

    # -------------------------------------------------------------------
    Context 'output' {

        It 'emits nothing to the pipeline' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
            }
            $Output = @(Get-IRTTeamsExternalDomain @Params)
            $Output.Count | Should -Be 0
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

        It 'throws when -Week is zero' {
            $Params = @{
                Start = '2026-01-04'
                End   = '2026-01-11'
                Path  = $TestPath
                Week  = 0
            }
            { Get-IRTTeamsExternalDomain @Params } | Should -Throw
        }
    }
}

Describe 'Get-IRTTeamsExternalDomain with Get-IRTUnifiedAuditLog' -Tag 'integration' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'
        $TestPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $TestPath -ItemType 'Directory'
        $script:TedSearchStarts = [System.Collections.Generic.List[datetime]]::new()
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Update-IRTToken { } -ModuleName $Mod
        Mock Start-Sleep { } -ModuleName $Mod
        Mock Get-DefaultDomain { 'contoso' } -ModuleName $Mod
        Mock Get-AcceptedDomain {
            [pscustomobject]@{ Default = $true; DomainName = 'contoso.com' }
        } -ModuleName $Mod
        # three records per window, recording the window start in local time so
        # it can be compared with the -Start / -End the caller passed
        Mock Search-UnifiedAuditLog {
            $script:TedSearchStarts.Add($StartDate.ToLocalTime())
            1..3 | ForEach-Object {
                [pscustomobject]@{
                    Identity     = [string][guid]::NewGuid()
                    SessionId    = 'ted-session'
                    CreationDate = $StartDate
                }
            }
        } -ModuleName $Mod
    }

    It 'sends only the named week to Search-UnifiedAuditLog' {
        $Params = @{
            Start = '2026-01-04'
            End   = '2026-01-25'
            Path  = $TestPath
            Week  = 2
        }
        $null = Get-IRTTeamsExternalDomain @Params
        $script:TedSearchStarts | Should -Be @([datetime]'2026-01-11')
    }

    It 'writes the records returned for the named week to that week''s file' {
        $Params = @{
            Start = '2026-01-04'
            End   = '2026-01-25'
            Path  = $TestPath
            Week  = 2
        }
        $null = Get-IRTTeamsExternalDomain @Params
        $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
        $File.Name | Should -Be 'TeamsExternalDomains_contoso_26-01-11.xml'
        $Content = Import-Clixml -Path $File.FullName
        $Content[0].RecordCount | Should -Be 3
    }

    It 'marks a week cut short by -ResultLimit as incomplete' {
        # the stubbed search returns three records, so a limit of three is hit
        $Params = @{
            Start       = '2026-01-04'
            End         = '2026-01-11'
            Path        = $TestPath
            ResultLimit = 3
        }
        $null = Get-IRTTeamsExternalDomain @Params
        $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
        $Content = Import-Clixml -Path $File.FullName
        $Content[0].DataGapCount | Should -Be 1
    }

    It 'leaves a week that stays under -ResultLimit unmarked' {
        $Params = @{
            Start = '2026-01-04'
            End   = '2026-01-11'
            Path  = $TestPath
        }
        $null = Get-IRTTeamsExternalDomain @Params
        $File = Get-ChildItem -Path $TestPath -Filter '*.xml'
        $Content = Import-Clixml -Path $File.FullName
        $Content[0].DataGapCount | Should -Be 0
    }
}
