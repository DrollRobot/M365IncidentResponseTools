function ConvertTo-TeamsParty {
    <#
    .SYNOPSIS
    Normalizes a UPN, domain, and/or tenant ID from a Teams audit record into one
    party object.

    .DESCRIPTION
    Internal helper for the Teams external contact parsers. Each parser describes the
    people in an event as parties: a domain, a tenant ID, or both when the record pairs
    them (a member's UPN next to their OrganizationId, or a SIP domain entry). This
    function does the cleanup every parser needs:

        - Takes the domain from the part of a UPN after the last '@'.
        - Decodes guest UPNs. A B2B guest account lives in the resource tenant, so its
          UPN ends in that tenant's onmicrosoft.com domain and its OrganizationId is
          that tenant's ID. The guest's real domain is encoded before '#EXT#'
          (jane_contoso.com#EXT#@tenant.onmicrosoft.com), so the domain is read from
          there and the tenant ID is dropped.
        - Lowercases domains and drops values that are not domain names, such as 'n/a'
          or a PSTN phone number in place of a UPN.
        - Drops tenant IDs that are not GUIDs, and the all-zero GUID Teams records for
          PSTN calls.

    Nothing is output when neither a domain nor a tenant ID survives.

    .PARAMETER Upn
    User principal name or email address. Ignored when it has no '@'.

    .PARAMETER Domain
    Domain name. Used only when -Upn does not supply one.

    .PARAMETER TenantId
    Entra tenant ID paired with the UPN or domain.

    .EXAMPLE
    ```powershell
    ConvertTo-TeamsParty -Upn $Member.UPN -TenantId $Member.OrganizationId
    ```
    Returns the member's domain paired with their tenant ID.

    .EXAMPLE
    ```powershell
    ConvertTo-TeamsParty -Upn 'jane_contoso.com#EXT#@fabrikam.onmicrosoft.com'
    ```
    Returns the guest's home domain, contoso.com, with no tenant ID.

    .OUTPUTS
    [pscustomobject] with Domain and TenantId properties, either of which may be $null.
    Nothing when both are empty.

    .NOTES
    Version: 1.0.0

    Logs through Write-PSFMessage from PSFramework, which Show-IRTTeamsExternalDomain
    imports once. Import-IRTModule is not called here because this runs for every
    record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Upn,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Domain,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $TenantId
    )

    $DomainPattern = '^[a-z0-9-]+(\.[a-z0-9-]+)+$'
    $GuestMarker = '#EXT#'
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase

    $Candidate = $Domain
    $IsGuest = $false
    if ($Upn -and $Upn.Contains('@')) {
        $GuestIndex = $Upn.IndexOf($GuestMarker, $Comparison)
        if ($GuestIndex -ge 0) {
            # the guest's own domain follows the last underscore before #EXT#; the
            # OrganizationId next to it belongs to the resource tenant, not the guest
            $IsGuest = $true
            $LocalPart = $Upn.Substring(0, $GuestIndex)
            $Candidate = $LocalPart.Substring($LocalPart.LastIndexOf('_') + 1)
        }
        else {
            $Candidate = $Upn.Substring($Upn.LastIndexOf('@') + 1)
        }
    }

    $PartyDomain = $null
    if ($Candidate) {
        $Candidate = $Candidate.Trim().ToLowerInvariant()
        if ($Candidate -match $DomainPattern) {
            $PartyDomain = $Candidate
        }
    }

    $PartyTenantId = $null
    $ParsedGuid = [guid]::Empty
    if (-not $IsGuest -and $TenantId -and [guid]::TryParse($TenantId, [ref] $ParsedGuid)) {
        if ($ParsedGuid -ne [guid]::Empty) {
            $PartyTenantId = $ParsedGuid.ToString()
        }
    }

    if (-not $PartyDomain -and -not $PartyTenantId) {
        Write-PSFMessage -Level 9 -Message (
            "ConvertTo-TeamsParty: nothing usable in Upn='${Upn}', Domain='${Domain}', " +
            "TenantId='${TenantId}'")
        return
    }

    [pscustomobject]@{
        Domain   = $PartyDomain
        TenantId = $PartyTenantId
    }
}
