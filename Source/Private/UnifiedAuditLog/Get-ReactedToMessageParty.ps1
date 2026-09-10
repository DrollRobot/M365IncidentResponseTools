function Get-ReactedToMessageParty {
    <#
    .SYNOPSIS
    Returns the parties named in a ReactedToMessage audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. ReactedToMessage records a reaction to a
    message. The conversation is summarised under ParticipantInfo, which for this
    operation usually lists tenant IDs but no domains. A domain appears only when the
    person reacting is from outside, as UserId paired with UserTenantId.
    ResourceTenantId is the tenant that hosts the chat.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-ReactedToMessageParty -AuditData ($Record.AuditData | ConvertFrom-Json)
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

    Write-PSFMessage -Level 9 -Message "Get-ReactedToMessageParty: $($AuditData.Id)"

    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ConvertTo-TeamsParty -Upn $AuditData.UserId -TenantId $AuditData.UserTenantId
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
}
