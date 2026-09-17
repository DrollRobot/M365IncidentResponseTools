function Get-ChatCreatedParty {
    <#
    .SYNOPSIS
    Returns the parties named in a ChatCreated audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. ChatCreated records a new chat thread.
    Each chat member is listed under Members with their UPN and OrganizationId, the
    conversation is summarised under ParticipantInfo, the creator is UserId (paired
    with UserTenantId when the record carries it), and ResourceTenantId is the tenant
    that hosts the chat.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-ChatCreatedParty -AuditData ($Record.AuditData | ConvertFrom-Json)
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

    Write-PSFMessage -Level 9 -Message "Get-ChatCreatedParty: $($AuditData.Id)"

    foreach ($Member in @($AuditData.Members)) {
        if ($null -eq $Member) { continue }
        ConvertTo-TeamsParty -Upn $Member.UPN -TenantId $Member.OrganizationId
    }
    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ConvertTo-TeamsParty -Upn $AuditData.UserId -TenantId $AuditData.UserTenantId
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
}
