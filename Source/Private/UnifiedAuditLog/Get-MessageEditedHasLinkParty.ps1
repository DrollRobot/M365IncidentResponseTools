function Get-MessageEditedHasLinkParty {
    <#
    .SYNOPSIS
    Returns the parties named in a MessageEditedHasLink audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. MessageEditedHasLink records an edit to a
    message containing a link, image, or file. Everyone in the conversation is listed
    under ParticipantInfo, the editor is UserId (paired with UserTenantId when the
    record carries it), and ResourceTenantId is the tenant that hosts the chat.

    The URLs in MessageURLs and MessageLinks are message content, not participants,
    so addresses inside them (such as mailto: links) are not read.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-MessageEditedHasLinkParty -AuditData ($Record.AuditData | ConvertFrom-Json)
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

    Write-PSFMessage -Level 9 -Message "Get-MessageEditedHasLinkParty: $($AuditData.Id)"

    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ConvertTo-TeamsParty -Upn $AuditData.UserId -TenantId $AuditData.UserTenantId
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
}
