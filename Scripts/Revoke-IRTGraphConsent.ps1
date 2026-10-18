function Revoke-IRTGraphConsent {
    <#
    .SYNOPSIS
    Removes all tenant-wide oauth2PermissionGrants for the specified app.

    .DESCRIPTION
    Used in tests to reset admin consent state before exercising the
    Connect-IRT admin consent workflow. Queries oauth2PermissionGrants
    for the given app's service principal and deletes each grant.

    Requires an active IRT Graph connection. Deleting grants needs
    DelegatedPermissionGrant.ReadWrite.All, which Connect-IRT's default set leaves
    out, so this helper requests a token with that scope itself. The first run in a
    tenant may open a browser to approve it.

    Entra can briefly reject changes to a grant that was just modified, such as by
    approving that scope, so each delete is retried for up to two minutes. If a
    delete still fails, the error includes Graph's status code and message.

    .PARAMETER AppId
    The application (client) ID whose grants will be removed. Defaults to the
    Microsoft Graph CLI Tools first-party app used by Connect-IRT.

    .OUTPUTS
    The number of grants removed.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [string] $AppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',  # Graph CLI Tools
        [switch] $Trace
    )

    if ($Trace) { $InformationPreference = 'Continue' }
    function Write-Trace {
        param([Parameter(Mandatory)][string] $Message)
        Write-Information $Message -Tags 'Trace'
    }

    # Resolve the service principal object ID for this app in the tenant.
    $SpRequest = @{
        Method      = 'GET'
        Uri         = "v1.0/servicePrincipals(appId='$AppId')?`$select=id,displayName"
        ErrorAction = 'Stop'
    }
    $SpResult = Invoke-MgGraphRequest @SpRequest
    $SpId = $SpResult.id

    # The session's Graph connection can only read grants. Mint a separate token
    # with the write scope, so only this test helper ever requests it. Do this
    # before listing grants: approving the scope in the browser can create a new
    # grant, and the list must include it.
    $TokenParams = @{
        Service         = 'Graph'
        AdditionalScope = 'DelegatedPermissionGrant.ReadWrite.All'
    }
    $Token = (Get-IRTAccessToken @TokenParams).AccessToken
    $GraphBaseUrl = $Global:IRT_Session.CloudConfig.Graph
    Write-Trace "Acquired a grant write token for $GraphBaseUrl."

    # Pull all grants where this SP is the client.
    $GrantListRequest = @{
        Method      = 'GET'
        Uri         = "v1.0/oauth2PermissionGrants?`$filter=clientId eq '$SpId'"
        ErrorAction = 'Stop'
    }
    $GrantsResult = Invoke-MgGraphRequest @GrantListRequest
    $Grants = $GrantsResult.value

    if (-not $Grants) {
        Write-Trace "No consent grants found for '$($SpResult.displayName)' ($AppId)."
        return 0
    }

    $MaxAttempts = 6
    $RetryDelaySeconds = 20

    $Removed = 0
    foreach ($Grant in $Grants) {
        $DeleteGrantRequest = @{
            Method      = 'DELETE'
            Uri         = "$GraphBaseUrl/v1.0/oauth2PermissionGrants/$($Grant.id)"
            Headers     = @{ Authorization = "Bearer $Token" }
            ErrorAction = 'Stop'
        }
        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            try {
                $null = Invoke-RestMethod @DeleteGrantRequest
                Write-Trace "Deleted grant $($Grant.id) (attempt $Attempt)."
                break
            }
            catch {
                # Invoke-RestMethod's message is only the status line; Graph's reason
                # is in the response body.
                $Status = $_.Exception.Response.StatusCode.value__
                $Body = $_.ErrorDetails.Message
                $GraphError = if ($Body) {
                    try { ($Body | ConvertFrom-Json).error } catch { $null }
                }
                $Detail = if ($GraphError) {
                    "HTTP ${Status} $($GraphError.code): $($GraphError.message)"
                } else {
                    "HTTP ${Status} $Body"
                }
                if ($Attempt -eq $MaxAttempts) {
                    throw ("Failed to delete grant $($Grant.id) after $MaxAttempts " +
                        "attempts. $Detail")
                }
                Write-Host ("Delete of grant $($Grant.id) failed (attempt $Attempt of " +
                    "$MaxAttempts): $Detail Retrying in $RetryDelaySeconds seconds.")
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
        $Removed++
    }

    Write-Trace "Removed $Removed consent grant(s) for '$($SpResult.displayName)'."
    return $Removed
}
