function Revoke-IRTGraphConsent {
    <#
    .SYNOPSIS
    Removes all tenant-wide oauth2PermissionGrants for the specified app.

    .DESCRIPTION
    Used in tests to reset admin consent state before exercising the
    Connect-IRT admin consent workflow. Queries oauth2PermissionGrants
    for the given app's service principal and deletes each grant. Uses
    Invoke-MgGraphRequest so the only dependency is Microsoft.Graph.Authentication
    (already loaded by the IRT module).

    Requires an active Graph connection with DelegatedPermissionGrant.ReadWrite.All.
    That scope is in Connect-IRT's default set, so a normal IRT connection suffices.

    .PARAMETER AppId
    The application (client) ID whose grants will be removed. Defaults to the
    Microsoft Graph CLI Tools first-party app used by Connect-IRT.

    .OUTPUTS
    The number of grants removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param (
        [string] $AppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Graph CLI Tools
    )

    # Resolve the service principal object ID for this app in the tenant.
    $SpResult = Invoke-MgGraphRequest -Method GET `
        -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=id,displayName" `
        -ErrorAction Stop
    $SpId = $SpResult.id

    # Pull all grants where this SP is the client.
    $GrantsResult = Invoke-MgGraphRequest -Method GET `
        -Uri "v1.0/oauth2PermissionGrants?`$filter=clientId eq '$SpId'" `
        -ErrorAction Stop
    $Grants = $GrantsResult.value

    if (-not $Grants) {
        Write-Verbose "No consent grants found for '$($SpResult.displayName)' ($AppId)."
        return 0
    }

    $Removed = 0
    foreach ($Grant in $Grants) {
        if ($PSCmdlet.ShouldProcess("Grant $($Grant.id) ($($Grant.scope -replace '\s+', ', '))", 'Remove')) {
            Invoke-MgGraphRequest -Method DELETE `
                -Uri "v1.0/oauth2PermissionGrants/$($Grant.id)" `
                -ErrorAction Stop
            $Removed++
        }
    }

    Write-Verbose "Removed $Removed consent grant(s) for '$($SpResult.displayName)'."
    return $Removed
}