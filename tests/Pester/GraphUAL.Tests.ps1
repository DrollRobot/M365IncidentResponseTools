#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the Graph audit search helpers.

.DESCRIPTION
    All tests are offline. These cover the private helpers that do the thinking:
    name encoding, record mapping, retry timing, error parsing and record type
    validation. Nothing here touches Graph.

    InModuleScope is used so the private functions are reachable. Where a helper
    reads module state it is set and torn down inside the test.

-- name round trip ------------------------------------------------------

    The display name is the only place the API will hold metadata, so encode and
    decode have to agree exactly. Read-GraphUALName must also reject names it
    did not write, since a tenant will hold searches created by the portal and by
    other tools, and acting on those would be wrong.

-- record mapping -------------------------------------------------------

    ConvertTo-UalRecord has to produce the shape Show-IRTUnifiedAuditLog and the
    sheet builders already expect: Identity, CreationDate as a DateTime,
    RecordType, Operations, UserIds, and AuditData as a JSON string rather than an
    object, because Show runs ConvertFrom-Json over it.

    OData annotation keys must not survive. Graph adds them at every level of
    auditData and they would otherwise land in the workbook's Raw column.

-- retry timing ---------------------------------------------------------

    Get-GraphUALRetryDelay prefers the server's Retry-After and falls back to
    exponential backoff. Getting this wrong either hammers a throttled endpoint or
    parks an investigation for an hour.

-- error status parsing -------------------------------------------------

    The Graph SDK folds its internal retries into one very long message carrying
    several copies of the same JSON error. Get-GraphUALErrorStatus reduces both
    known shapes to one token so callers can branch on it.

-- record type validation -----------------------------------------------

    Test-GraphUALRecordType warns and never blocks. The operations sheet only
    records what has been witnessed, so an absent value is not proof of an invalid
    one, and blocking would reject legitimate searches for record types Microsoft
    has shipped but this tenant has not yet logged.
#>

BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'
}

Describe 'Start-IRTGraphUAL job matrix' -Tag 'unit' {

    BeforeEach {
        InModuleScope $script:Mod {
            Mock Write-IRT { }
            Mock Write-PSFMessage { }
            Mock Update-IRTToken { }
            Mock Test-GraphUALRecordType { [string[]]@() }
            Mock Get-GraphUALOpenUnfilteredJob { $null }
            Mock Get-DefaultDomain { 'contoso' }
            Mock Wait-IRTGraphUAL { }
            Mock Resolve-DateRange {
                [pscustomobject]@{
                    Days        = 30
                    StartUtc    = [datetime]'2026-08-10T00:00:00Z'
                    EndUtc      = [datetime]'2026-09-09T00:00:00Z'
                    StartString = '2026-08-10T00:00:00Z'
                    EndString   = '2026-09-09T00:00:00Z'
                }
            }
            # capture every submitted body so the job matrix can be asserted on
            $script:Submitted = [System.Collections.Generic.List[hashtable]]::new()
            Mock Invoke-GraphUALRequest {
                # Pester binds the caller's arguments into the mock's scope, so $Body
                # is available without declaring a param block
                $script:Submitted.Add($Body)
                [pscustomobject]@{
                    Ok     = $true
                    Result = @{ id = [guid]::NewGuid().ToString(); status = 'notStarted' }
                    Error  = $null
                    Status = 'OK'
                }
            }
        }
    }

    It 'submits three keyword jobs for a user: address, object id, dashless object id' {
        InModuleScope $script:Mod {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'jdoe@contoso.com'
            }
            $null = Start-IRTGraphUAL -UserObject $User -NoWait -Excel $false -Xml $false

            $script:Submitted.Count | Should -Be 3
            $Keywords = @($script:Submitted | ForEach-Object { $_.keywordFilter })
            $Keywords | Should -Contain 'jdoe@contoso.com'
            $Keywords | Should -Contain 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            $Keywords | Should -Contain 'aaaaaaaabbbbccccddddeeeeeeeeeeee'
        }
    }

    It 'never uses the actor filter, which cannot match a GUID' {
        InModuleScope $script:Mod {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'jdoe@contoso.com'
            }
            $null = Start-IRTGraphUAL -UserObject $User -NoWait -Excel $false -Xml $false
            @($script:Submitted | Where-Object { $_.ContainsKey('userPrincipalNameFilters') }) |
                Should -BeNullOrEmpty
        }
    }

    It 'submits four keyword jobs for a service principal, both ids in both forms' {
        InModuleScope $script:Mod {
            $Sp = [pscustomobject]@{
                Id          = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                AppId       = '11111111-2222-3333-4444-555555555555'
                DisplayName = 'Some App'
            }
            $null = Start-IRTGraphUAL -ServicePrincipal $Sp -NoWait -Excel $false -Xml $false

            $script:Submitted.Count | Should -Be 4
            $Keywords = @($script:Submitted | ForEach-Object { $_.keywordFilter })
            $Keywords | Should -Contain 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            $Keywords | Should -Contain 'aaaaaaaabbbbccccddddeeeeeeeeeeee'
            $Keywords | Should -Contain '11111111-2222-3333-4444-555555555555'
            $Keywords | Should -Contain '11111111222233334444555555555555'
        }
    }

    It 'submits a single unfiltered job for -AllUsers' {
        InModuleScope $script:Mod {
            $null = Start-IRTGraphUAL -AllUsers -NoWait -Excel $false -Xml $false
            $script:Submitted.Count | Should -Be 1
            $script:Submitted[0].ContainsKey('keywordFilter') | Should -BeFalse
        }
    }

    It 'refuses -AllUsers while another unfiltered job is open' {
        InModuleScope $script:Mod {
            Mock Get-GraphUALOpenUnfilteredJob {
                @{ displayName = 'IRT: UAL|other'; status = 'running' }
            }
            $null = Start-IRTGraphUAL -AllUsers -NoWait -Excel $false -Xml $false
            $script:Submitted.Count | Should -Be 0
            $Filter = { $Level -eq 'Error' -and $Message -match 'only one at a time' }
            Should -Invoke Write-IRT -ParameterFilter $Filter
        }
    }

    It 'adds one extra job per FreeText string' {
        InModuleScope $script:Mod {
            $Params = @{
                AllUsers = $true
                FreeText = 'evil.com', '1.2.3.4'
                NoWait   = $true
                Excel    = $false
                Xml      = $false
            }
            $null = Start-IRTGraphUAL @Params
            $script:Submitted.Count | Should -Be 3
        }
    }

    It 'puts shared filters on every job in the group' {
        InModuleScope $script:Mod {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'jdoe@contoso.com'
            }
            $Params = @{
                UserObject = $User
                RecordType = 'MicrosoftTeams'
                NoWait     = $true
                Excel      = $false
                Xml        = $false
            }
            $null = Start-IRTGraphUAL @Params
            foreach ($Body in $script:Submitted) {
                $Body.recordTypeFilters | Should -Be @('MicrosoftTeams')
                $Body.filterStartDateTime | Should -Be '2026-08-10T00:00:00Z'
            }
        }
    }

    It 'gives every job in a group the same group id and a distinct index' {
        InModuleScope $script:Mod {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'jdoe@contoso.com'
            }
            $null = Start-IRTGraphUAL -UserObject $User -NoWait -Excel $false -Xml $false
            $Parsed = @($script:Submitted | ForEach-Object {
                    Read-GraphUALName -Name $_.displayName -Prefix 'IRT: '
                })
            @($Parsed.GroupId | Sort-Object -Unique).Count | Should -Be 1
            @($Parsed.Index | Sort-Object -Unique).Count | Should -Be 3
        }
    }
}

Describe 'Get-IRTJobNamePrefix' -Tag 'unit' {

    It 'prefers the current key' {
        InModuleScope $script:Mod {
            $Global:IRT_Config = [pscustomobject]@{
                JobNamePrefix         = 'CASE: '
                EmailSearchNamePrefix = 'OLD: '
            }
            Get-IRTJobNamePrefix | Should -Be 'CASE: '
        }
    }

    It 'falls back to the pre-rename key so an existing config keeps working' {
        InModuleScope $script:Mod {
            $Global:IRT_Config = [pscustomobject]@{ EmailSearchNamePrefix = 'OLD: ' }
            Get-IRTJobNamePrefix | Should -Be 'OLD: '
        }
    }

    It 'defaults when neither key is set' {
        InModuleScope $script:Mod {
            $Global:IRT_Config = [pscustomobject]@{}
            Get-IRTJobNamePrefix | Should -Be 'IRT: '
        }
    }

    AfterAll {
        InModuleScope $script:Mod {
            $RemoveParams = @{
                Name        = 'IRT_Config'
                Scope       = 'Global'
                ErrorAction = 'SilentlyContinue'
            }
            Remove-Variable @RemoveParams
        }
    }
}

Describe 'Search names are unique and traceable to their export' -Tag 'unit' {

    It 'gives two searches of the same user in the same minute different names' {
        InModuleScope $script:Mod {
            # jobs cannot be deleted from the tenant, so a repeated search must not
            # produce a name that collides with the earlier one still listed there
            $Common = @{
                ObjectName = 'jdoe'
                ProfileTag = 'Default'
                Days       = 30
                Index      = 1
                Stamp      = '260909-1412'
                Prefix     = 'IRT: '
            }
            $A = New-GraphUALName @Common -GroupId '3f9a1c2b'
            $B = New-GraphUALName @Common -GroupId '7d4e8f01'
            $A | Should -Not -Be $B
        }
    }

    It 'encodes the stamp and group id that the exported file name also carries' {
        InModuleScope $script:Mod {
            $Params = @{
                ObjectName = 'jdoe'
                ProfileTag = 'Default'
                Days       = 30
                GroupId    = '3f9a1c2b'
                Index      = 1
                Stamp      = '260909-1412'
                Prefix     = 'IRT: '
            }
            $Name = New-GraphUALName @Params
            $Parsed = Read-GraphUALName -Name $Name -Prefix 'IRT: '

            # Receive-IRTGraphUAL builds the file base from exactly these fields, so a
            # file on disk can be matched by eye to a search still listed on the tenant
            $FileBase = "UnifiedAuditLogs_$($Parsed.Days)Days_contoso" +
            "_$($Parsed.ObjectName)_$($Parsed.Stamp)_g$($Parsed.GroupId)"
            $FileBase | Should -Be 'UnifiedAuditLogs_30Days_contoso_jdoe_260909-1412_g3f9a1c2b'
            $Name | Should -Match ([regex]::Escape($Parsed.Stamp))
            $Name | Should -Match ([regex]::Escape($Parsed.GroupId))
        }
    }
}

Describe 'Select-GraphUALFocus' -Tag 'unit' {

    BeforeEach {
        InModuleScope $script:Mod {
            Mock Write-PSFMessage { }
            Mock Test-IRTInteractiveHost { $true }
            Mock Build-Menu { 'Quit' }
        }
    }

    It 'returns an explicit group without prompting' {
        InModuleScope $script:Mod {
            $Jobs = @(
                [pscustomobject]@{ GroupId = 'aaa'; IsOurs = $true }
                [pscustomobject]@{ GroupId = 'bbb'; IsOurs = $true }
            )
            Select-GraphUALFocus -Jobs $Jobs -Group 'bbb' | Should -Be 'bbb'
            Should -Invoke Build-Menu -Times 0
        }
    }

    It 'picks a lone outstanding group without prompting' {
        InModuleScope $script:Mod {
            $Jobs = @([pscustomobject]@{ GroupId = 'aaa'; IsOurs = $true })
            Select-GraphUALFocus -Jobs $Jobs | Should -Be 'aaa'
            Should -Invoke Build-Menu -Times 0
        }
    }

    It 'prompts when there is a real choice' {
        InModuleScope $script:Mod {
            $Jobs = @(
                [pscustomobject]@{
                    GroupId = 'aaa'; IsOurs = $true; ObjectName = 'jdoe'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
                [pscustomobject]@{
                    GroupId = 'bbb'; IsOurs = $true; ObjectName = 'asmith'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
            )
            $null = Select-GraphUALFocus -Jobs $Jobs
            Should -Invoke Build-Menu -Times 1
        }
    }

    It 'returns every group when the menu picks all' {
        InModuleScope $script:Mod {
            Mock Build-Menu { 'All 2 searches' }
            $Jobs = @(
                [pscustomobject]@{
                    GroupId = 'aaa'; IsOurs = $true; ObjectName = 'jdoe'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
                [pscustomobject]@{
                    GroupId = 'bbb'; IsOurs = $true; ObjectName = 'asmith'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
            )
            $Focus = Select-GraphUALFocus -Jobs $Jobs
            $Focus.Count | Should -Be 2
        }
    }

    It 'returns nothing when the menu is quit' {
        InModuleScope $script:Mod {
            $Jobs = @(
                [pscustomobject]@{
                    GroupId = 'aaa'; IsOurs = $true; ObjectName = 'jdoe'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
                [pscustomobject]@{
                    GroupId = 'bbb'; IsOurs = $true; ObjectName = 'asmith'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
            )
            (Select-GraphUALFocus -Jobs $Jobs).Count | Should -Be 0
        }
    }

    It 'never prompts in a non-interactive host, and follows everything instead' {
        InModuleScope $script:Mod {
            Mock Test-IRTInteractiveHost { $false }
            $Jobs = @(
                [pscustomobject]@{
                    GroupId = 'aaa'; IsOurs = $true; ObjectName = 'jdoe'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
                [pscustomobject]@{
                    GroupId = 'bbb'; IsOurs = $true; ObjectName = 'asmith'
                    ProfileTag = 'Default'; Days = 30; Status = 'running'
                }
            )
            (Select-GraphUALFocus -Jobs $Jobs).Count | Should -Be 2
            Should -Invoke Build-Menu -Times 0
        }
    }

    It 'never offers a search this module did not create' {
        InModuleScope $script:Mod {
            $Jobs = @(
                [pscustomobject]@{ GroupId = 'aaa'; IsOurs = $true }
                [pscustomobject]@{ GroupId = $null; IsOurs = $false }
            )
            $Focus = Select-GraphUALFocus -Jobs $Jobs
            $Focus | Should -Be 'aaa'
        }
    }
}

Describe 'New-GraphUALName / Read-GraphUALName' -Tag 'unit' {

    It 'round trips every field' {
        InModuleScope $script:Mod {
            $Params = @{
                ObjectName = 'jdoe'
                ProfileTag = 'Default'
                Days       = 30
                GroupId    = '3f9a1c2b'
                Index      = 2
                Stamp      = '260909-1412'
                Prefix     = 'IRT: '
            }
            $Name = New-GraphUALName @Params
            $Name | Should -Be 'IRT: UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b|j2'

            $Parsed = Read-GraphUALName -Name $Name -Prefix 'IRT: '
            $Parsed.ObjectName | Should -Be 'jdoe'
            $Parsed.ProfileTag | Should -Be 'Default'
            $Parsed.Days | Should -Be 30
            $Parsed.GroupId | Should -Be '3f9a1c2b'
            $Parsed.Index | Should -Be 2
            $Parsed.Created | Should -Be ([datetime]'2026-09-09 14:12')
        }
    }

    It 'strips characters that would break the field separator' {
        InModuleScope $script:Mod {
            $Params = @{
                ObjectName = 'j|doe@contoso.com'
                ProfileTag = 'SignInLogs'
                Days       = 7
                GroupId    = 'abc12345'
                Index      = 1
                Stamp      = '260909-1412'
                Prefix     = 'IRT: '
            }
            $Name = New-GraphUALName @Params
            # the sanitized object name must not reintroduce a separator
            ($Name -split '\|').Count | Should -Be 7
            $Parsed = Read-GraphUALName -Name $Name -Prefix 'IRT: '
            $Parsed.ObjectName | Should -Be 'jdoecontosocom'
        }
    }

    It 'returns null for a name this module did not write' {
        InModuleScope $script:Mod {
            Read-GraphUALName -Name 'Analyst ad-hoc search' -Prefix 'IRT: ' |
                Should -BeNullOrEmpty
            Read-GraphUALName -Name 'IRT: something else' -Prefix 'IRT: ' |
                Should -BeNullOrEmpty
            Read-GraphUALName -Name '' -Prefix 'IRT: ' | Should -BeNullOrEmpty
        }
    }

    It 'returns null when the field count is wrong' {
        InModuleScope $script:Mod {
            $Short = 'IRT: UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b'
            Read-GraphUALName -Name $Short -Prefix 'IRT: ' | Should -BeNullOrEmpty
        }
    }

    It 'parses a name whose stamp is unreadable, leaving Created null' {
        InModuleScope $script:Mod {
            $Name = 'IRT: UAL|jdoe|Default|30d|notadate|g3f9a1c2b|j1'
            $Parsed = Read-GraphUALName -Name $Name -Prefix 'IRT: '
            $Parsed | Should -Not -BeNullOrEmpty
            $Parsed.GroupId | Should -Be '3f9a1c2b'
            $Parsed.Created | Should -BeNullOrEmpty
        }
    }
}

Describe 'ConvertTo-UalRecord' -Tag 'unit' {

    It 'maps Graph properties onto the legacy record shape' {
        InModuleScope $script:Mod {
            $Graph = @{
                id                 = 'abc-123'
                createdDateTime    = '2026-09-09T14:12:00Z'
                auditLogRecordType = 'AzureActiveDirectoryStsLogon'
                operation          = 'UserLoggedIn'
                userPrincipalName  = 'jdoe@contoso.com'
                userId             = 'user-guid'
                userType           = 'Regular'
                service            = 'AzureActiveDirectory'
                clientIp           = '203.0.113.5'
                auditData          = @{ Workload = 'AzureActiveDirectory'; RecordType = 15 }
            }
            $Record = ConvertTo-UalRecord -Record $Graph

            $Record.Identity | Should -Be 'abc-123'
            $Record.RecordType | Should -Be 'AzureActiveDirectoryStsLogon'
            $Record.Operations | Should -Be 'UserLoggedIn'
            $Record.UserIds | Should -Be 'jdoe@contoso.com'
            $Record.CreationDate | Should -BeOfType [datetime]
            $Record.ClientIp | Should -Be '203.0.113.5'
        }
    }

    It 'emits AuditData as a JSON string, because Show runs ConvertFrom-Json on it' {
        InModuleScope $script:Mod {
            $Graph = @{
                id        = 'abc-123'
                auditData = @{ Workload = 'Exchange'; Operation = 'MailItemsAccessed' }
            }
            $Record = ConvertTo-UalRecord -Record $Graph
            $Record.AuditData | Should -BeOfType [string]
            ($Record.AuditData | ConvertFrom-Json).Workload | Should -Be 'Exchange'
        }
    }

    It 'falls back to userId when there is no userPrincipalName' {
        InModuleScope $script:Mod {
            $Graph = @{ id = 'a'; userId = 'ServicePrincipal_1234' }
            (ConvertTo-UalRecord -Record $Graph).UserIds | Should -Be 'ServicePrincipal_1234'
        }
    }

    It 'survives a record with no createdDateTime' {
        InModuleScope $script:Mod {
            $Record = ConvertTo-UalRecord -Record @{ id = 'a' }
            $Record.CreationDate | Should -BeNullOrEmpty
            $Record.Identity | Should -Be 'a'
        }
    }
}

Describe 'Remove-ODataAnnotation' -Tag 'unit' {

    It 'drops bare and per-property annotation keys' {
        InModuleScope $script:Mod {
            $Payload = @{
                '@odata.type'        = '#microsoft.graph.security.auditData'
                'RecordType@odata.type' = '#int32'
                'Workload'           = 'Exchange'
                'RecordType'         = 2
            }
            $Clean = Remove-ODataAnnotation -InputObject $Payload
            $Clean.Keys | Should -Not -Contain '@odata.type'
            $Clean.Keys | Should -Not -Contain 'RecordType@odata.type'
            $Clean['Workload'] | Should -Be 'Exchange'
            $Clean['RecordType'] | Should -Be 2
        }
    }

    It 'cleans nested dictionaries and arrays' {
        InModuleScope $script:Mod {
            $Payload = @{
                'Actor@odata.type' = '#Collection'
                Actor              = @(
                    @{ '@odata.type' = '#x'; ID = 'jdoe@contoso.com'; Type = 5 }
                )
            }
            $Clean = Remove-ODataAnnotation -InputObject $Payload
            $Clean.Keys | Should -Not -Contain 'Actor@odata.type'
            $Clean['Actor'][0].Keys | Should -Not -Contain '@odata.type'
            $Clean['Actor'][0]['ID'] | Should -Be 'jdoe@contoso.com'
        }
    }

    It 'passes strings and nulls through unchanged' {
        InModuleScope $script:Mod {
            Remove-ODataAnnotation -InputObject 'plain' | Should -Be 'plain'
            Remove-ODataAnnotation -InputObject $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-GraphUALErrorStatus' -Tag 'unit' {

    It 'extracts the status from an SDK retry-folded throttling message' {
        InModuleScope $script:Mod {
            $Message = 'Too many retries performed. More than 3 retries encountered ' +
            'while sending the request. (HTTP request failed with status code: ' +
            'TooManyRequests.{"error":{"code":"TooManyRequests"}})'
            Get-GraphUALErrorStatus -Message $Message | Should -Be 'TooManyRequests'
        }
    }

    It 'extracts the status from the response-code message shape' {
        InModuleScope $script:Mod {
            $Message = 'Response status code does not indicate success: ' +
            'InternalServerError (Internal Server Error).'
            Get-GraphUALErrorStatus -Message $Message | Should -Be 'InternalServerError'
        }
    }

    It 'returns Unknown for an unrecognised message' {
        InModuleScope $script:Mod {
            Get-GraphUALErrorStatus -Message 'something else broke' | Should -Be 'Unknown'
            Get-GraphUALErrorStatus -Message '' | Should -Be 'Unknown'
        }
    }
}

Describe 'Get-GraphUALRetryDelay' -Tag 'unit' {

    It 'honours a Retry-After from the message text' {
        InModuleScope $script:Mod {
            $Error1 = $null
            try { throw 'Too many requests. Please try again in 42 seconds.' }
            catch { $Error1 = $_ }
            Get-GraphUALRetryDelay -ErrorRecord $Error1 -Attempt 1 -BaseSeconds 30 |
                Should -Be 42
        }
    }

    It 'backs off exponentially when no Retry-After is present' {
        InModuleScope $script:Mod {
            $Error1 = $null
            try { throw 'no hint here' } catch { $Error1 = $_ }
            Get-GraphUALRetryDelay -ErrorRecord $Error1 -Attempt 1 -BaseSeconds 30 |
                Should -Be 30
            Get-GraphUALRetryDelay -ErrorRecord $Error1 -Attempt 2 -BaseSeconds 30 |
                Should -Be 60
            Get-GraphUALRetryDelay -ErrorRecord $Error1 -Attempt 3 -BaseSeconds 30 |
                Should -Be 120
        }
    }

    It 'caps the wait at one hour so a bad value cannot park a session' {
        InModuleScope $script:Mod {
            $Error1 = $null
            try { throw 'no hint here' } catch { $Error1 = $_ }
            Get-GraphUALRetryDelay -ErrorRecord $Error1 -Attempt 20 -BaseSeconds 60 |
                Should -Be 3600
        }
    }
}

Describe 'Test-GraphUALRecordType' -Tag 'unit' {

    BeforeEach {
        InModuleScope $script:Mod {
            Mock Write-IRT { }
            Mock Write-PSFMessage { }
            # the set is built inside the mock body: a variable captured from this
            # scope is not in scope when Pester later invokes the scriptblock
            Mock Get-GraphUALKnownRecordType {
                $Comparer = [System.StringComparer]::OrdinalIgnoreCase
                $Set = [System.Collections.Generic.HashSet[string]]::new($Comparer)
                foreach ($T in 'MicrosoftTeams', 'ExchangeItem', 'AzureActiveDirectoryStsLogon') {
                    [void]$Set.Add($T)
                }
                return , $Set
            }
        }
    }

    It 'accepts a known record type without warning' {
        InModuleScope $script:Mod {
            $Unknown = Test-GraphUALRecordType -RecordType 'MicrosoftTeams'
            $Unknown.Count | Should -Be 0
            Should -Invoke Write-IRT -Times 0
        }
    }

    It 'matches without regard to casing' {
        InModuleScope $script:Mod {
            (Test-GraphUALRecordType -RecordType 'microsoftteams').Count | Should -Be 0
        }
    }

    It 'warns and returns the value for an unknown record type' {
        InModuleScope $script:Mod {
            $Unknown = Test-GraphUALRecordType -RecordType 'MicrosoftTeems'
            $Unknown | Should -Be 'MicrosoftTeems'
            $Filter = { $Level -eq 'Warn' -and $Message -match 'MicrosoftTeems' }
            Should -Invoke Write-IRT -ParameterFilter $Filter
        }
    }

    It 'suggests a close match in the warning' {
        InModuleScope $script:Mod {
            $null = Test-GraphUALRecordType -RecordType 'MicrosoftTeam'
            $Filter = { $Message -match 'MicrosoftTeams' }
            Should -Invoke Write-IRT -ParameterFilter $Filter
        }
    }

    It 'skips validation when the sheet yielded nothing' {
        InModuleScope $script:Mod {
            Mock Get-GraphUALKnownRecordType {
                $Comparer = [System.StringComparer]::OrdinalIgnoreCase
                return , ([System.Collections.Generic.HashSet[string]]::new($Comparer))
            }
            $Unknown = Test-GraphUALRecordType -RecordType 'AnythingAtAll'
            $Unknown.Count | Should -Be 0
            Should -Invoke Write-IRT -Times 0
        }
    }

    It 'returns empty when no record types were requested' {
        InModuleScope $script:Mod {
            (Test-GraphUALRecordType -RecordType @()).Count | Should -Be 0
        }
    }
}

Describe 'New-UalGapMarker' -Tag 'unit' {

    It 'produces a row the sheet builders will keep and display' {
        InModuleScope $script:Mod {
            $Marker = New-UalGapMarker -Reason 'job failed' -Label 'keyword jdoe'
            $Marker.IRTDataGap | Should -BeTrue
            $Marker.RecordType | Should -Be 'IRT_QUERY_FAILURE'
            $Marker.Operations | Should -Be 'DataMissing'
            $Marker.UserIds | Should -Match 'DATA MISSING'
            ($Marker.AuditData | ConvertFrom-Json).Error | Should -Be 'job failed'
        }
    }

    It 'gives each marker a unique identity so dedupe cannot collapse them' {
        InModuleScope $script:Mod {
            $A = New-UalGapMarker -Reason 'a' -Label 'x'
            $B = New-UalGapMarker -Reason 'b' -Label 'y'
            $A.Identity | Should -Not -Be $B.Identity
        }
    }
}

Describe 'Get-GraphUALJobLabel' -Tag 'unit' {

    It 'summarises a keyword filter' {
        InModuleScope $script:Mod {
            $Query = @{ keywordFilter = 'jdoe@contoso.com' }
            Get-GraphUALJobLabel -Query $Query | Should -Be 'keyword jdoe@contoso.com'
        }
    }

    It 'reports an unfiltered job plainly' {
        InModuleScope $script:Mod {
            $Query = @{ keywordFilter = $null; recordTypeFilters = @() }
            Get-GraphUALJobLabel -Query $Query | Should -Be 'unfiltered'
        }
    }

    It 'counts operation filters instead of listing them' {
        InModuleScope $script:Mod {
            $Query = @{ operationFilters = @('A', 'B', 'C') }
            Get-GraphUALJobLabel -Query $Query | Should -Be '3 operation(s)'
        }
    }

    It 'truncates a long label so a status table stays readable' {
        InModuleScope $script:Mod {
            $Query = @{ keywordFilter = ('x' * 200) }
            $Label = Get-GraphUALJobLabel -Query $Query
            $Label.Length | Should -BeLessOrEqual 40
            $Label | Should -Match '\.\.\.$'
        }
    }
}
