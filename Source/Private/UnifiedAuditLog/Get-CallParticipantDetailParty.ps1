function Get-CallParticipantDetailParty {
    <#
    .SYNOPSIS
    Returns the parties named in a CallParticipantDetail audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. CallParticipantDetail records one
    participant's time on a call. The participant is listed under Attendees with their
    UPN and OrganizationId, ParticipantInfo lists the tenant IDs on the call, and
    ResourceTenantId is the tenant that hosts it. UserId is the participant's UPN
    without a tenant ID.

    PSTN callers have a phone number in place of a UPN and the all-zero GUID as
    ResourceTenantId. ConvertTo-TeamsParty drops both, so a phone call adds nothing.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-CallParticipantDetailParty -AuditData ($Record.AuditData | ConvertFrom-Json)
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

    Write-PSFMessage -Level 9 -Message "Get-CallParticipantDetailParty: $($AuditData.Id)"

    foreach ($Attendee in @($AuditData.Attendees)) {
        if ($null -eq $Attendee) { continue }
        ConvertTo-TeamsParty -Upn $Attendee.UPN -TenantId $Attendee.OrganizationId
    }
    Get-TeamsParticipantInfoParty -ParticipantInfo $AuditData.ParticipantInfo
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
    ConvertTo-TeamsParty -Upn $AuditData.UserId
}
