function Get-MeetingParticipantDetailParty {
    <#
    .SYNOPSIS
    Returns the parties named in a MeetingParticipantDetail audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. MeetingParticipantDetail records one
    attendee's time in a meeting. The attendee is listed under Attendees with their
    UPN and OrganizationId, and whoever let them in is under Attendees.InviterInfo in
    the same form. Guest attendees appear with a #EXT# guest UPN, which
    ConvertTo-TeamsParty decodes. Organizer.OrganizationId is the organiser's tenant,
    which is an outside organisation when a tenant user joins someone else's meeting.
    ResourceTenantId is the tenant that hosts the meeting, and UserId is the attendee's
    UPN without a tenant ID.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-MeetingParticipantDetailParty -AuditData ($Record.AuditData | ConvertFrom-Json)
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

    Write-PSFMessage -Level 9 -Message "Get-MeetingParticipantDetailParty: $($AuditData.Id)"

    foreach ($Attendee in @($AuditData.Attendees)) {
        if ($null -eq $Attendee) { continue }
        ConvertTo-TeamsParty -Upn $Attendee.UPN -TenantId $Attendee.OrganizationId
        $Inviter = $Attendee.InviterInfo
        if ($Inviter) {
            ConvertTo-TeamsParty -Upn $Inviter.UPN -TenantId $Inviter.OrganizationId
        }
    }
    if ($AuditData.Organizer) {
        ConvertTo-TeamsParty -TenantId $AuditData.Organizer.OrganizationId
    }
    ConvertTo-TeamsParty -TenantId $AuditData.ResourceTenantId
    ConvertTo-TeamsParty -Upn $AuditData.UserId
}
