function Get-MemberAddedParty {
    <#
    .SYNOPSIS
    Returns the parties named in a MemberAdded audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. MemberAdded records people joining a chat,
    team, or channel. Each added member is listed under Members with their UPN and,
    for chats, their OrganizationId. Guest members appear with a #EXT# guest UPN,
    which ConvertTo-TeamsParty decodes. Chat records also carry ParticipantInfo, the
    person who added them is UserId (paired with UserTenantId when the record carries
    it), and ResourceTenantId is the tenant that hosts the chat.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-MemberAddedParty -AuditData ($Record.AuditData | ConvertFrom-Json)
    ```
    Returns a party for each domain and tenant ID in the record.

    .OUTPUTS
    [pscustomobject] party objects with Domain and TenantId properties.

    .NOTES
    Version: 1.0.0

    Logs through Write-PSFMessage from PSFramework, which Show-IRTTeamsExternalDomain
    imports once. Import-IRTModule is not called here because this runs for every
    record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [psobject] $AuditData
    )

    Write-PSFMessage -Level 9 -Message "Get-MemberAddedParty: $($AuditData.Id)"

    foreach ($Member in @($AuditData.Members)) {
        if ($null -eq $Member) { continue }
        ConvertTo-TeamsParty -Upn $Member.UPN -TenantId $Member.OrganizationId
    }
    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ConvertTo-TeamsParty -Upn $AuditData.UserId -TenantId $AuditData.UserTenantId
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
}
