function Get-TeamsParticipantInfoParty {
    <#
    .SYNOPSIS
    Returns the parties listed in a Teams audit record's ParticipantInfo block.

    .DESCRIPTION
    Internal helper for the Teams external contact parsers. Chat, message, and call
    records summarise everyone in the conversation under ParticipantInfo:

        ParticipatingSIPDomains - domain and tenant ID pairs
        ParticipatingDomains    - domains on their own
        ParticipatingTenantIds  - tenant IDs on their own

    Every entry is returned as a party. The three lists overlap, so one organisation
    usually appears several times; the caller de-duplicates.

    .PARAMETER ParticipantInfo
    The ParticipantInfo object from parsed AuditData. $null returns nothing.

    .EXAMPLE
    ```powershell
    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ```
    Returns a party for each domain, tenant ID, and SIP domain pair in the record.

    .OUTPUTS
    [pscustomobject] party objects from ConvertTo-TeamsParty.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [AllowNull()]
        [psobject] $ParticipantInfo
    )

    if ($null -eq $ParticipantInfo) { return }

    foreach ($Entry in @($ParticipantInfo.ParticipatingSIPDomains)) {
        if ($null -eq $Entry) { continue }
        ConvertTo-TeamsParty -Domain $Entry.DomainName -TenantId $Entry.TenantId
    }
    foreach ($Name in @($ParticipantInfo.ParticipatingDomains)) {
        ConvertTo-TeamsParty -Domain $Name
    }
    foreach ($Id in @($ParticipantInfo.ParticipatingTenantIds)) {
        ConvertTo-TeamsParty -TenantId $Id
    }
}
