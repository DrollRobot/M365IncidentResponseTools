#region Show-ServicePrincipalInfo
function Show-ServicePrincipalInfo {
    <#
    .SYNOPSIS
    Displays detailed service principal properties for objects produced by Find-ServicePrincipal.

    .DESCRIPTION
    Retrieves the full Graph service principal object using a curated property list and
    displays it as a formatted tree in the console via Show-GraphServicePrincipalTree.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. This lets you run Find-ServicePrincipal first to select a target, then run
    Show-ServicePrincipalInfo with no arguments to display it.

    Properties retrieved include credentials (key and password certificates), OAuth2
    permission scopes, app roles, reply URLs, SSO settings, publisher verification,
    and all standard identity fields.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects to display. Falls back to
    $Global:IRT_ServicePrincipalObjects if omitted.

    .EXAMPLE
    Find-ServicePrincipal MyApp
    Show-ServicePrincipalInfo
    Two-step workflow: find then display.

    .EXAMPLE
    Show-ServicePrincipalInfo
    Display info for the service principal already stored in the global session.

    .EXAMPLE
    Show-ServicePrincipalInfo -ServicePrincipalObject $SP
    Display info for a specific service principal object passed directly.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ShowServicePrincipal', 'ShowServicePrincipals',
           'ShowSP', 'ShowSPs',
           'ShowApp', 'ShowApps',
           'ShowApplication', 'ShowApplications',
           'ShowEnterpriseApp', 'ShowEnterpriseApps',
           'ShowEnterpriseApplication', 'ShowEnterpriseApplications')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject
    )

    begin {
        if ( -not $ServicePrincipalObject -or $ServicePrincipalObject.Count -eq 0 ) {
            $ScriptServicePrincipalObjects = @( $Global:IRT_ServicePrincipalObjects )
            if ( -not $ScriptServicePrincipalObjects -or $ScriptServicePrincipalObjects.Count -eq 0 ) {
                throw "No service principal objects passed or found in global variables."
            }
        }
        else {
            $ScriptServicePrincipalObjects = $ServicePrincipalObject
        }

        $SelectProps = @(
            'accountEnabled'
            'alternativeNames'
            'appDescription'
            'appDisplayName'
            'appId'
            'appOwnerOrganizationId'
            'appRoles'
            'createdDateTime'
            'deletedDateTime'
            'description'
            'disabledByMicrosoftStatus'
            'displayName'
            'errorUrl'
            'homepage'
            'id'
            'info'
            'keyCredentials'
            'loginUrl'
            'logoutUrl'
            'notes'
            'notificationEmailAddresses'
            'oauth2PermissionScopes'
            'passwordCredentials'
            'preferredSingleSignOnMode'
            'preferredTokenSigningKeyThumbprint'
            'publisherName'
            'replyUrls'
            'samlSingleSignOnSettings'
            'servicePrincipalNames'
            'servicePrincipalType'
            'signInAudience'
            'tags'
            'tokenEncryptionKeyId'
            'verifiedPublisher'
        )
    }

    process {

        foreach ($ScriptServicePrincipalObject in $ScriptServicePrincipalObjects) {

            $SpName = if ($ScriptServicePrincipalObject.AppDisplayName) {
                $ScriptServicePrincipalObject.AppDisplayName
            }
            else {
                $ScriptServicePrincipalObject.DisplayName
            }

            try {
                $FullSP = Get-MgServicePrincipal -ServicePrincipalId $ScriptServicePrincipalObject.Id `
                    -Property $SelectProps -ErrorAction Stop

                Write-IRT "Showing service principal properties for: ${SpName}"
                $FullSP | Show-GraphServicePrincipalTree | Out-Host
            }
            catch {
                Write-IRT "Failed to get service principal object: $($_.Exception.Message)" -Level Error
            }
        }
    }
}
#endregion


#region Show-GraphServicePrincipalTree
function Show-GraphServicePrincipalTree {
    <#
    .SYNOPSIS
    Renders a Graph service principal object as a compact property tree.

    .DESCRIPTION
    Projects the service principal object, excluding the noisy AdditionalProperties
    collection, then passes the result to Format-Tree for console display. Intended
    to be called via pipeline from Show-ServicePrincipalInfo.

    .PARAMETER ServicePrincipalObject
    The service principal object(s) to render. Accepts pipeline input.

    .PARAMETER Depth
    Maximum recursion depth for nested objects. Default: 10.

    .OUTPUTS
    None. Output is written to the console via Format-Tree.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [int] $Depth = 10
    )

    begin {
        $Exclude = @(
            'AdditionalProperties'
        )
    }

    process {
        foreach ($ServicePrincipalObjectItem in $ServicePrincipalObject) {
            if ($null -eq $ServicePrincipalObjectItem) { continue }

            $Projected = $ServicePrincipalObjectItem | Select-Object -Property * -ExcludeProperty $Exclude

            $Params = @{
                Depth           = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
#endregion
