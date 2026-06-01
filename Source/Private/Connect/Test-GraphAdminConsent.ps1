function Test-GraphAdminConsent {
    <#
    .SYNOPSIS
    Returns the set of requested scopes that are NOT already admin-consented
    tenant-wide for the Microsoft Graph Command Line Tools app.

    .DESCRIPTION
    Queries oauth2PermissionGrants for AllPrincipals (admin) grants and
    compares the consented scopes against the requested set. Returns an
    empty array if all scopes are admin-consented.

    Requires an existing Graph connection with at least
    DelegatedPermissionGrant.Read.All or Directory.Read.All.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias('RequestedScopes')]
        [string[]] $RequestedScope,

        [string] $ClientAppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',  # Graph CLI Tools
        [string] $ResourceAppId = '00000003-0000-0000-c000-000000000000' # Microsoft Graph
    )

    # Resolve SPs (these are tenant-scoped object IDs, not the app IDs)
    $ClientSpParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/servicePrincipals(appId='$ClientAppId')"
        ErrorAction = 'Stop'
    }
    $ClientSp = Invoke-MgGraphRequest @ClientSpParams
    $ResourceSpParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/servicePrincipals(appId='$ResourceAppId')"
        ErrorAction = 'Stop'
    }
    $ResourceSp = Invoke-MgGraphRequest @ResourceSpParams

    # Pull all AllPrincipals grants for this client/resource pair.
    # In practice there's usually one, but multiple are possible if
    # admins consented in batches.
    $Filter = "clientId eq '$($ClientSp.id)' and " +
    "resourceId eq '$($ResourceSp.id)' and " +
    "consentType eq 'AllPrincipals'"
    $Encoded = [uri]::EscapeDataString($Filter)
    $GrantsParams = @{
        Method      = 'GET'
        Uri         = "/v1.0/oauth2PermissionGrants?`$filter=$Encoded"
        ErrorAction = 'Stop'
    }
    $Grants = Invoke-MgGraphRequest @GrantsParams

    # scope is a space-delimited string per grant; flatten across grants
    $Granted = @($Grants.value | ForEach-Object { $_.scope -split '\s+' } |
            Where-Object { $_ } | Select-Object -Unique)

    # Return the missing ones (case-insensitive compare)
    $RequestedScope | Where-Object { $Granted -notcontains $_ }
}
