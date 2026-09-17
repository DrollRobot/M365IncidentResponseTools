function Get-UserAcceptedParty {
    <#
    .SYNOPSIS
    Returns the parties named in a UserAccepted audit record.

    .DESCRIPTION
    Parser for Show-IRTTeamsExternalDomain. UserAccepted records a tenant user
    accepting an external user. The external user is listed under Members with their
    OrganizationId but no UPN, so this operation yields tenant IDs only.

    Parties from the tenant being investigated are returned too; the caller removes
    them.

    .PARAMETER AuditData
    The record's AuditData, already converted from JSON.

    .EXAMPLE
    ```powershell
    Get-UserAcceptedParty -AuditData ($Record.AuditData | ConvertFrom-Json)
    ```
    Returns a party for each tenant ID in the record.

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

    Write-PSFMessage -Level 9 -Message "Get-UserAcceptedParty: $($AuditData.Id)"

    foreach ($Member in @($AuditData.Members)) {
        if ($null -eq $Member) { continue }
        ConvertTo-TeamsParty -Upn $Member.UPN -TenantId $Member.OrganizationId
    }
}
