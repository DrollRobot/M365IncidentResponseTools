#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the Teams external contact parsers behind
    Show-IRTTeamsExternalDomain.

.DESCRIPTION
    All tests are offline. InModuleScope is used so the private parsers are reachable.
    Fixture records use made-up domains and tenant IDs in the shape of real Teams audit
    data:

        11111111-... contoso.com    the investigated tenant
        22222222-... fabrikam.com   an outside tenant
        33333333-... northwind.com  another outside tenant

-- party normalization ----------------------------------------------------

    ConvertTo-TeamsParty does the cleanup every parser relies on. Domains come from the
    part of a UPN after '@'. Guest UPNs are decoded to the guest's home domain, with the
    resource tenant's ID dropped, because that ID belongs to the investigated tenant and
    would otherwise hide the guest. Junk values (n/a, phone numbers, the all-zero GUID
    on PSTN calls) never become parties.

-- participant info -------------------------------------------------------

    Get-TeamsParticipantInfoParty turns all three ParticipantInfo lists into parties.

-- per-operation parsers --------------------------------------------------

    Each parser must read every field its operation carries. A parser that misses a
    field silently hides an outside organisation from the summary, which is the failure
    this tooling exists to prevent.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Teams external contact parsers' -Tag 'unit' {

        BeforeDiscovery {
            $HomeTid = '11111111-1111-1111-1111-111111111111'
            $FabTid = '22222222-2222-2222-2222-222222222222'
            $NwTid = '33333333-3333-3333-3333-333333333333'
            $GuestUpn = 'jane_fabrikam.com#EXT#@contoso.onmicrosoft.com'

            # one case per field each parser must read
            $script:ParserCases = @(
                @{
                    Parser   = 'Get-MessageSentParty'
                    Field    = 'ParticipantInfo SIP domains'
                    Record   = @{
                        ParticipantInfo = @{
                            ParticipatingSIPDomains = @(
                                @{ DomainName = 'fabrikam.com'; TenantId = $FabTid }
                            )
                        }
                    }
                    Domain   = 'fabrikam.com'
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-MessageSentParty'
                    Field    = 'UserId and UserTenantId'
                    Record   = @{ UserId = 'kyra@northwind.com'; UserTenantId = $NwTid }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-MessageCreatedHasLinkParty'
                    Field    = 'ParticipantInfo domains'
                    Record   = @{
                        ParticipantInfo = @{ ParticipatingDomains = @('fabrikam.com') }
                    }
                    Domain   = 'fabrikam.com'
                    TenantId = $null
                }
                @{
                    Parser   = 'Get-MessageUpdatedParty'
                    Field    = 'ParticipantInfo tenant IDs'
                    Record   = @{
                        ParticipantInfo = @{ ParticipatingTenantIds = @($HomeTid, $FabTid) }
                    }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-MessageEditedHasLinkParty'
                    Field    = 'ResourceTenantId'
                    Record   = @{ ResourceTenantId = $FabTid }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-ChatCreatedParty'
                    Field    = 'Members'
                    Record   = @{
                        Members = @(
                            @{ UPN = 'kyra@northwind.com'; OrganizationId = $NwTid }
                        )
                    }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-MemberAddedParty'
                    Field    = 'a guest member'
                    Record   = @{
                        Members = @(
                            @{ UPN = $GuestUpn; OrganizationId = $HomeTid }
                        )
                    }
                    Domain   = 'fabrikam.com'
                    TenantId = $null
                }
                @{
                    Parser   = 'Get-MeetingParticipantDetailParty'
                    Field    = 'Attendees'
                    Record   = @{
                        Attendees = @(
                            @{ UPN = 'kyra@northwind.com'; OrganizationId = $NwTid }
                        )
                    }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-MeetingParticipantDetailParty'
                    Field    = 'InviterInfo'
                    Record   = @{
                        Attendees = @(
                            @{
                                UPN            = 'amy@contoso.com'
                                OrganizationId = $HomeTid
                                InviterInfo    = @{
                                    UPN            = 'kyra@northwind.com'
                                    OrganizationId = $NwTid
                                }
                            }
                        )
                    }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-MeetingParticipantDetailParty'
                    Field    = 'Organizer'
                    Record   = @{ Organizer = @{ OrganizationId = $FabTid } }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-CallParticipantDetailParty'
                    Field    = 'Attendees'
                    Record   = @{
                        Attendees = @(
                            @{ UPN = 'kyra@northwind.com'; OrganizationId = $NwTid }
                        )
                    }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-CallParticipantDetailParty'
                    Field    = 'ParticipantInfo tenant IDs'
                    Record   = @{
                        ParticipantInfo = @{ ParticipatingTenantIds = @($FabTid) }
                    }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-ReactedToMessageParty'
                    Field    = 'UserId and UserTenantId'
                    Record   = @{ UserId = 'kyra@northwind.com'; UserTenantId = $NwTid }
                    Domain   = 'northwind.com'
                    TenantId = $NwTid
                }
                @{
                    Parser   = 'Get-ReactedToMessageParty'
                    Field    = 'ParticipantInfo tenant IDs'
                    Record   = @{
                        ParticipantInfo = @{ ParticipatingTenantIds = @($FabTid) }
                    }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-UserAcceptedParty'
                    Field    = 'Members'
                    Record   = @{
                        Members = @(
                            @{ MRI = 'orgid:x'; OrganizationId = $FabTid; Role = 1 }
                        )
                    }
                    Domain   = $null
                    TenantId = $FabTid
                }
                @{
                    Parser   = 'Get-UserBlockedParty'
                    Field    = 'Members'
                    Record   = @{
                        Members = @(
                            @{ MRI = 'orgid:y'; OrganizationId = $NwTid; Role = 1 }
                        )
                    }
                    Domain   = $null
                    TenantId = $NwTid
                }
            )
        }

        BeforeEach {
            Mock Write-PSFMessage { }
        }

        # -------------------------------------------------------------------
        Context 'ConvertTo-TeamsParty' {

            It 'pairs the UPN domain with the tenant ID, lowercased' {
                $Params = @{
                    Upn      = 'Kyra@Fabrikam.COM'
                    TenantId = '22222222-2222-2222-2222-22222222222A'
                }
                $Party = ConvertTo-TeamsParty @Params
                $Party.Domain | Should -Be 'fabrikam.com'
                $Party.TenantId | Should -Be '22222222-2222-2222-2222-22222222222a'
            }

            It 'decodes a guest UPN to the home domain and drops the tenant ID' {
                $Params = @{
                    Upn      = 'jane_fabrikam.com#EXT#@contoso.onmicrosoft.com'
                    TenantId = '11111111-1111-1111-1111-111111111111'
                }
                $Party = ConvertTo-TeamsParty @Params
                $Party.Domain | Should -Be 'fabrikam.com'
                $Party.TenantId | Should -BeNullOrEmpty
            }

            It 'reads the guest domain after the last underscore' {
                $Upn = 'j.van_alfen_northwind.com#EXT#@contoso.onmicrosoft.com'
                $Party = ConvertTo-TeamsParty -Upn $Upn
                $Party.Domain | Should -Be 'northwind.com'
            }

            It 'uses -Domain when there is no UPN' {
                $Party = ConvertTo-TeamsParty -Domain 'Northwind.com'
                $Party.Domain | Should -Be 'northwind.com'
                $Party.TenantId | Should -BeNullOrEmpty
            }

            It 'ignores a phone number in place of a UPN but keeps the tenant ID' {
                $Params = @{
                    Upn      = '+15555550100'
                    TenantId = '22222222-2222-2222-2222-222222222222'
                }
                $Party = ConvertTo-TeamsParty @Params
                $Party.Domain | Should -BeNullOrEmpty
                $Party.TenantId | Should -Be '22222222-2222-2222-2222-222222222222'
            }

            It 'returns nothing for an n/a domain with no tenant ID' {
                @(ConvertTo-TeamsParty -Domain 'n/a').Count | Should -Be 0
            }

            It 'drops the all-zero GUID' {
                $Params = @{ TenantId = '00000000-0000-0000-0000-000000000000' }
                @(ConvertTo-TeamsParty @Params).Count | Should -Be 0
            }

            It 'drops a tenant ID that is not a GUID' {
                @(ConvertTo-TeamsParty -TenantId 'not-a-guid').Count | Should -Be 0
            }

            It 'returns nothing when every input is empty' {
                @(ConvertTo-TeamsParty -Upn '' -Domain $null).Count | Should -Be 0
            }
        }

        # -------------------------------------------------------------------
        Context 'Get-TeamsParticipantInfoParty' {

            It 'returns SIP domain pairs, lone domains, and lone tenant IDs' {
                $Info = [pscustomobject]@{
                    ParticipatingSIPDomains = @(
                        [pscustomobject]@{
                            DomainName = 'fabrikam.com'
                            TenantId   = '22222222-2222-2222-2222-222222222222'
                        }
                    )
                    ParticipatingDomains    = @('northwind.com')
                    ParticipatingTenantIds  = @('33333333-3333-3333-3333-333333333333')
                }
                $Parties = @(Get-TeamsParticipantInfoParty -ParticipantInfo $Info)
                $Parties.Count | Should -Be 3
                $Pair = $Parties | Where-Object { $_.Domain -eq 'fabrikam.com' }
                $Pair.TenantId | Should -Be '22222222-2222-2222-2222-222222222222'
                $Parties.Domain | Should -Contain 'northwind.com'
                $Parties.TenantId | Should -Contain '33333333-3333-3333-3333-333333333333'
            }

            It 'returns nothing when ParticipantInfo is missing' {
                @(Get-TeamsParticipantInfoParty -ParticipantInfo $null).Count |
                    Should -Be 0
            }
        }

        # -------------------------------------------------------------------
        Context 'per-operation parsers' {

            It '<Parser> reads <Field>' -ForEach $script:ParserCases {
                # round-trip through JSON so the parser sees the same object shape
                # ConvertFrom-Json produces from real AuditData
                $AuditData = $Record | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $Parties = @(& $Parser -AuditData $AuditData)
                $Filter = { $_.Domain -eq $Domain -and $_.TenantId -eq $TenantId }
                @($Parties | Where-Object $Filter).Count | Should -BeGreaterThan 0
            }

            It 'Get-CallParticipantDetailParty returns nothing for a PSTN call' {
                $Record = @{
                    UserId           = '+15555550100'
                    Attendees        = @(
                        @{ DisplayName = '+15555550100'; UserIdType = 'PstnNumber' }
                    )
                    ResourceTenantId = '00000000-0000-0000-0000-000000000000'
                }
                $AuditData = $Record | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                @(Get-CallParticipantDetailParty -AuditData $AuditData).Count |
                    Should -Be 0
            }
        }
    }
}
