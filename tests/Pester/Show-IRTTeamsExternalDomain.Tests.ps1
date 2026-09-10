#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Show-IRTTeamsExternalDomain: the file loop, home tenant
    filtering, tenant lookup, counting, and the workbook it writes.

.DESCRIPTION
    All tests are offline. Fixture files in the shape Get-IRTTeamsExternalDomain writes
    are saved to Pester's TestDrive with Export-Clixml. Get-IRTTenantOwner and
    Update-IRTToken are mocked so no Graph call is made. The fixtures use made-up
    tenants:

        11111111-... contoso.com    the investigated tenant
        22222222-... fabrikam.com   outside; the lookup mock resolves it
        33333333-... (no domain)    outside; the lookup mock cannot resolve it
        tailspin.com                outside; appears only as a guest UPN

    The unit block mocks Export-Excel, so nothing is written and post-export
    formatting is skipped. It checks warnings and lookup behaviour. The integration
    block lets the real parsers and Export-Excel run, then reads the workbook back with
    Import-Excel.

-- warnings -------------------------------------------------------------

    Missing data must never pass silently: DATA MISSING markers, records from
    operations with no parser, a missing Graph connection, and tenant IDs that could
    not be resolved each produce a warning.

-- tenant lookup --------------------------------------------------------

    Only tenant IDs that a record names without a domain are looked up. With no Graph
    connection nothing is looked up and tenant IDs are listed instead.

-- workbook -------------------------------------------------------------

    Four columns: Domain, Count, LastDate, and allow_TRUE_FALSE. allow_TRUE_FALSE
    starts as a native Excel boolean FALSE on every row, for a reviewer to change; a
    text "FALSE" would not filter or evaluate as a boolean. The title gives the date
    range of the records read.

    The investigated tenant's domains are left out, even where one appears without its
    tenant ID. A resolved tenant ID is counted with records that name the same domain
    directly. A record found in two files counts once. Rows are sorted by count,
    highest first.
#>

BeforeAll {
    # Builds a record shaped like Search-UnifiedAuditLog output. AuditData is a JSON
    # string, as it is in the files Get-IRTTeamsExternalDomain writes. Global so it is
    # reachable from every block.
    function global:New-SteRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [string] $Operation,
            [hashtable] $AuditData,
            [datetime] $CreationDate = ([datetime]'2026-01-05T12:00:00'),
            [string] $Identity = ([guid]::NewGuid().ToString())
        )
        $AuditData['Operation'] = $Operation
        $AuditData['OrganizationId'] = '11111111-1111-1111-1111-111111111111'
        [pscustomobject]@{
            RecordType   = 'MicrosoftTeams'
            CreationDate = $CreationDate
            UserIds      = 'amy@contoso.com'
            Operations   = $Operation
            AuditData    = $AuditData | ConvertTo-Json -Depth 10
            Identity     = $Identity
        }
    }

    # Writes records behind a metadata row, like the weekly files.
    function global:Save-SteFile {
        param(
            [string] $FilePath,
            [object[]] $Record
        )
        $Rows = [System.Collections.Generic.List[psobject]]::new()
        $Rows.Add([pscustomobject]@{
                Metadata       = $true
                FileNamePrefix = 'TeamsExternalDomains'
            })
        foreach ($Item in $Record) { $Rows.Add($Item) }
        $Rows | Export-Clixml -Depth 10 -Path $FilePath
    }

    # Import-Excel can hand a date cell back as a DateTime or as an OLE date number.
    function global:ConvertTo-SteDate {
        param($Value)
        if ($Value -is [double]) { return [datetime]::FromOADate($Value) }
        [datetime]$Value
    }
}

AfterAll {
    @('New-SteRecord', 'Save-SteFile', 'ConvertTo-SteDate') | ForEach-Object {
        Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue
    }
}

Describe 'Show-IRTTeamsExternalDomain' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'
        # each test gets its own folder so earlier fixtures are never read again
        $TestPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $TestPath -ItemType 'Directory'

        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Export-Excel { } -ModuleName $Mod
        Mock Update-IRTToken { @{ Graph = $true } } -ModuleName $Mod
        Mock Get-IRTTenantOwner {
            foreach ($Id in $TenantId) {
                [pscustomobject]@{ TenantId = $Id; Exists = $false }
            }
        } -ModuleName $Mod

        # $script: scope carries these from BeforeEach into each It
        $script:WeekFile = Join-Path -Path $TestPath -ChildPath 'week.xml'
        $script:HomeTid = '11111111-1111-1111-1111-111111111111'
        $script:FabTid = '22222222-2222-2222-2222-222222222222'

        # a blocked user from a tenant named only by ID
        $script:BlockRecord = New-SteRecord -Operation 'UserBlocked' -AuditData @{
            Members = @(@{ OrganizationId = '33333333-3333-3333-3333-333333333333' })
        }
    }

    # -------------------------------------------------------------------
    Context 'input' {

        It 'throws when -Path is not an existing directory' {
            $Missing = Join-Path -Path $TestPath -ChildPath 'does-not-exist'
            { Show-IRTTeamsExternalDomain -Path $Missing -Open $false } | Should -Throw
        }

        It 'warns and writes nothing when the folder has no .xml files' {
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $Level -eq 'Warn' -and $Message -match 'No \.xml files' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
            Should -Invoke Export-Excel -Times 0 -ModuleName $Mod
        }
    }

    # -------------------------------------------------------------------
    Context 'warnings' {

        It 'warns about DATA MISSING markers' {
            $Gap = [pscustomobject]@{ Identity = 'IRT-DATA-GAP-test'; IRTDataGap = $true }
            Save-SteFile -FilePath $script:WeekFile -Record @($script:BlockRecord, $Gap)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $Level -eq 'Warn' -and $Message -match 'DATA MISSING' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
        }

        It 'warns about records from operations with no parser' {
            $Session = New-SteRecord -Operation 'TeamsSessionStarted' -AuditData @{}
            Save-SteFile -FilePath $script:WeekFile -Record @($Session, $script:BlockRecord)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $Level -eq 'Warn' -and $Message -match 'TeamsSessionStarted \(1\)' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
        }

        It 'warns and exports nothing when no outside domain is found' {
            $Internal = New-SteRecord -Operation 'ChatCreated' -AuditData @{
                Members = @(@{ UPN = 'amy@contoso.com'; OrganizationId = $script:HomeTid })
            }
            Save-SteFile -FilePath $script:WeekFile -Record @($Internal)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $Level -eq 'Warn' -and $Message -match 'No outside domains' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
            Should -Invoke Export-Excel -Times 0 -ModuleName $Mod
        }
    }

    # -------------------------------------------------------------------
    Context 'tenant lookup' {

        It 'looks up a tenant ID named without a domain' {
            Save-SteFile -FilePath $script:WeekFile -Record @($script:BlockRecord)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $TenantId -contains '33333333-3333-3333-3333-333333333333' }
            Should -Invoke Get-IRTTenantOwner -ModuleName $Mod -ParameterFilter $F
        }

        It 'does not look up a tenant ID the record already pairs with a domain' {
            $Chat = New-SteRecord -Operation 'ChatCreated' -AuditData @{
                Members         = @(
                    @{ UPN = 'kyra@fabrikam.com'; OrganizationId = $script:FabTid }
                )
                ParticipantInfo = @{ ParticipatingTenantIds = @($script:FabTid) }
            }
            Save-SteFile -FilePath $script:WeekFile -Record @($Chat)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            Should -Invoke Get-IRTTenantOwner -Times 0 -ModuleName $Mod
        }

        It 'warns when a tenant ID cannot be resolved' {
            Save-SteFile -FilePath $script:WeekFile -Record @($script:BlockRecord)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            $F = { $Level -eq 'Warn' -and $Message -match 'Could not find a domain' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
        }

        It 'skips the lookup and warns when not connected to Graph' {
            Mock Update-IRTToken { } -ModuleName $Mod
            Save-SteFile -FilePath $script:WeekFile -Record @($script:BlockRecord)
            Show-IRTTeamsExternalDomain -Path $TestPath -Open $false
            Should -Invoke Get-IRTTenantOwner -Times 0 -ModuleName $Mod
            $F = { $Level -eq 'Warn' -and $Message -match 'Not connected to Graph' }
            Should -Invoke Write-IRT -ModuleName $Mod -ParameterFilter $F
        }
    }
}

Describe 'Show-IRTTeamsExternalDomain workbook' -Tag 'integration' {

    BeforeAll {
        $Mod = 'M365IncidentResponseTools'
        $HomeTid = '11111111-1111-1111-1111-111111111111'
        $FabTid = '22222222-2222-2222-2222-222222222222'
        $NwTid = '33333333-3333-3333-3333-333333333333'
        $script:NwTid = $NwTid

        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Update-IRTToken { @{ Graph = $true } } -ModuleName $Mod
        Mock Get-IRTTenantOwner {
            foreach ($Id in $TenantId) {
                if ($Id -eq '22222222-2222-2222-2222-222222222222') {
                    [pscustomobject]@{
                        TenantId      = $Id
                        Exists        = $true
                        DefaultDomain = 'Fabrikam.com'
                    }
                }
                else {
                    [pscustomobject]@{ TenantId = $Id; Exists = $false }
                }
            }
        } -ModuleName $Mod

        $script:OutPath = Join-Path -Path $TestDrive -ChildPath 'workbook'
        $null = New-Item -Path $script:OutPath -ItemType 'Directory'

        # a chat with fabrikam; contoso.com is learned as a home domain from its SIP pair
        $ChatParams = @{
            Operation    = 'ChatCreated'
            Identity     = 'rec-chat'
            CreationDate = [datetime]'2026-01-05T12:00:00'
            AuditData    = @{
                Members         = @(
                    @{ UPN = 'amy@contoso.com'; OrganizationId = $HomeTid }
                    @{ UPN = 'kyra@fabrikam.com'; OrganizationId = $FabTid }
                )
                ParticipantInfo = @{
                    ParticipatingSIPDomains = @(
                        @{ DomainName = 'contoso.com'; TenantId = $HomeTid }
                        @{ DomainName = 'fabrikam.com'; TenantId = $FabTid }
                    )
                    ParticipatingDomains    = @('contoso.com', 'fabrikam.com')
                    ParticipatingTenantIds  = @($HomeTid, $FabTid)
                }
            }
        }
        $Chat = New-SteRecord @ChatParams

        # a reaction naming fabrikam only by tenant ID
        $ReactParams = @{
            Operation    = 'ReactedToMessage'
            Identity     = 'rec-react'
            CreationDate = [datetime]'2026-01-06T12:00:00'
            AuditData    = @{
                ParticipantInfo = @{ ParticipatingTenantIds = @($HomeTid, $FabTid) }
            }
        }
        $React = New-SteRecord @ReactParams

        # a blocked user from a tenant the lookup cannot resolve
        $BlockParams = @{
            Operation    = 'UserBlocked'
            Identity     = 'rec-block'
            CreationDate = [datetime]'2026-01-07T09:00:00'
            AuditData    = @{ Members = @(@{ OrganizationId = $NwTid }) }
        }
        $Block = New-SteRecord @BlockParams

        # a guest attendee in a meeting the investigated tenant hosts
        $GuestParams = @{
            Operation    = 'MeetingParticipantDetail'
            Identity     = 'rec-guest'
            CreationDate = [datetime]'2026-01-04T08:00:00'
            AuditData    = @{
                Attendees        = @(
                    @{
                        UPN            = 'jane_tailspin.com#EXT#@contoso.onmicrosoft.com'
                        OrganizationId = $HomeTid
                    }
                )
                Organizer        = @{ OrganizationId = $HomeTid }
                ResourceTenantId = $HomeTid
            }
        }
        $Guest = New-SteRecord @GuestParams

        # the home domain alone, next to fabrikam, with no SIP pairs to identify it
        $MessageParams = @{
            Operation    = 'MessageSent'
            Identity     = 'rec-msg'
            CreationDate = [datetime]'2026-01-08T15:30:00'
            AuditData    = @{
                ParticipantInfo = @{
                    ParticipatingDomains = @('contoso.com', 'fabrikam.com')
                }
            }
        }
        $Message = New-SteRecord @MessageParams

        $Week1 = Join-Path -Path $script:OutPath -ChildPath 'week1.xml'
        Save-SteFile -FilePath $Week1 -Record @($Chat, $React, $Block, $Guest)
        # the second file repeats the reaction, which must be counted once
        $Week2 = Join-Path -Path $script:OutPath -ChildPath 'week2.xml'
        Save-SteFile -FilePath $Week2 -Record @($React, $Message)

        Show-IRTTeamsExternalDomain -Path $script:OutPath -Open $false

        $script:Workbook = @(Get-ChildItem -Path $script:OutPath -Filter '*.xlsx')
        $ImportParams = @{
            Path          = $script:Workbook[0].FullName
            WorksheetName = 'TeamsExternalDomains'
            StartRow      = 2
        }
        $script:Rows = @(Import-Excel @ImportParams)

        $Package = Open-ExcelPackage -Path $script:Workbook[0].FullName
        $script:Title = $Package.Workbook.Worksheets['TeamsExternalDomains'].Cells['A1'].Value
        Close-ExcelPackage -ExcelPackage $Package -NoSave
    }

    It 'writes one workbook into -Path' {
        $script:Workbook.Count | Should -Be 1
        $script:Workbook[0].Name | Should -BeLike 'TeamsExternalDomainSummary_*.xlsx'
    }

    It 'writes the Domain, Count, LastDate, and allow_TRUE_FALSE columns in order' {
        $Columns = $script:Rows[0].PSObject.Properties.Name
        $Columns | Should -Be @('Domain', 'Count', 'LastDate', 'allow_TRUE_FALSE')
    }

    It 'starts allow_TRUE_FALSE as a native boolean FALSE on every row' {
        foreach ($Row in $script:Rows) {
            $Row.allow_TRUE_FALSE | Should -BeOfType ([bool])
            $Row.allow_TRUE_FALSE | Should -BeFalse
        }
    }

    It 'titles the sheet with the date range of the records read' {
        $Format = 'M/d/yy h:mmtt'
        $First = ([datetime]'2026-01-04T08:00:00').ToLocalTime().ToString($Format).ToLower()
        $Last = ([datetime]'2026-01-08T15:30:00').ToLocalTime().ToString($Format).ToLower()
        $script:Title | Should -Be "Teams external communication from ${First} to ${Last}"
    }

    It 'leaves out the investigated tenant, even where its domain appears alone' {
        $script:Rows.Domain | Should -Not -Contain 'contoso.com'
        $script:Rows.Domain | Should -Not -Contain '11111111-1111-1111-1111-111111111111'
    }

    It 'counts a resolved tenant ID with records that name the domain directly' {
        $Row = $script:Rows | Where-Object { $_.Domain -eq 'fabrikam.com' }
        # chat, reaction (once, despite two files), and message
        $Row.Count | Should -Be 3
    }

    It 'lists a tenant ID that could not be resolved' {
        $Row = $script:Rows | Where-Object { $_.Domain -eq $script:NwTid }
        $Row.Count | Should -Be 1
    }

    It 'counts a guest under their home domain' {
        $Row = $script:Rows | Where-Object { $_.Domain -eq 'tailspin.com' }
        $Row.Count | Should -Be 1
    }

    It 'records the latest date for each domain in local time' {
        $Row = $script:Rows | Where-Object { $_.Domain -eq 'fabrikam.com' }
        $Expected = ([datetime]'2026-01-08T15:30:00').ToLocalTime()
        ConvertTo-SteDate $Row.LastDate | Should -Be $Expected
    }

    It 'sorts rows by count, highest first' {
        $script:Rows[0].Domain | Should -Be 'fabrikam.com'
        $script:Rows.Count | Should -Be 3
    }
}
