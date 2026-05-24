#region Show-IRTServicePrincipalInfo
function Show-IRTServicePrincipalInfo {
    <#
    .SYNOPSIS
    Displays detailed service principal properties for objects produced by Find-ServicePrincipal.

    .DESCRIPTION
    Retrieves the full Graph service principal object using a curated property list and
    displays it as a formatted tree in the console via Show-GraphServicePrincipalTree.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. This lets you run Find-ServicePrincipal first to select a target, then run
    Show-IRTServicePrincipalInfo with no arguments to display it.

    Properties retrieved include credentials (key and password certificates), OAuth2
    permission scopes, app roles, reply URLs, SSO settings, publisher verification,
    and all standard identity fields.

    After the property tree, four additional tables are displayed:
    - OAuth2 Permission Grants: delegated permissions the SP has been granted (user or
      admin consent), with the resource display name resolved from the resource ID.
    - App Role Assignments: application permissions (admin-consented app roles) assigned
      to the SP, with the role GUID resolved to the human-readable permission value.
    - Directory Role Memberships: Entra admin roles (e.g. Cloud Application Administrator)
      the SP has been assigned to. Uses the IRT_DirectoryRoles cache if populated.
    - App Role Assigned To: users, groups, and SPs that have been granted access to this app.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects to display. Falls back to
    $Global:IRT_ServicePrincipalObjects if omitted.

    .PARAMETER Cached
    Pass -Cached to all Request-* calls so previously fetched Graph data is reused
    instead of making new API calls. Without this switch, each Request-* call fetches
    fresh data from Graph.

    .EXAMPLE
    Find-ServicePrincipal MyApp
    Show-IRTServicePrincipalInfo
    Two-step workflow: find then display.

    .EXAMPLE
    Show-IRTServicePrincipalInfo
    Display info for the service principal already stored in the global session.

    .EXAMPLE
    Show-IRTServicePrincipalInfo -ServicePrincipalObject $SP
    Display info for a specific service principal object passed directly.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.3.0
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
        [psobject[]] $ServicePrincipalObject,

        [switch] $Cached
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
                $GetSPParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    Property           = $SelectProps
                    ErrorAction        = 'Stop'
                }
                $FullSP = Get-MgServicePrincipal @GetSPParams

                Write-IRT "Showing service principal properties for: ${SpName}"
                $FullSP | Show-GraphServicePrincipalTree | Out-Host
            }
            catch {
                Write-IRT "Failed to get service principal object: $($_.Exception.Message)" -Level Error
            }

            # OAuth2 Permission Grants (delegated permissions)
            try {
                $GrantsByClientId = Request-GraphOauth2Grant -Cached:$Cached -Return 'tablebyclientid'
                $OAuth2Grants     = @( $GrantsByClientId[$ScriptServicePrincipalObject.Id] )
                $SPsById          = Request-GraphServicePrincipal -Cached:$Cached -Return 'tablebyid'
                $UsersById        = Request-GraphUser -Cached:$Cached -Return 'tablebyid'

                Write-IRT "OAuth2 Permission Grants (delegated) for: ${SpName}"
                if ($OAuth2Grants.Count -gt 0) {
                    $OAuth2Grants | ForEach-Object {
                        $User = if ($_.ConsentType -eq 'Principal') { $UsersById[$_.PrincipalId] } else { $null }
                        [PSCustomObject]@{
                            Resource          = ($SPsById[$_.ResourceId] ? $SPsById[$_.ResourceId].DisplayName : $null) ?? $_.ResourceId
                            ConsentType       = $_.ConsentType
                            DisplayName       = $User ? $User.DisplayName : $null
                            UserPrincipalName = $User ? $User.UserPrincipalName : $null
                            Scope             = $_.Scope
                            ExpiryTime        = $_.ExpiryTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No OAuth2 permission grants found." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get OAuth2 permission grants: $($_.Exception.Message)" -Level Error
            }

            # App Role Assignments (application permissions)
            try {
                $GetAssignmentParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    All                = $true
                    ErrorAction        = 'Stop'
                }
                $AppRoleAssignments = Get-MgServicePrincipalAppRoleAssignment @GetAssignmentParams

                Write-IRT "App Role Assignments (application permissions) for: ${SpName}"
                if ($AppRoleAssignments.Count -gt 0) {
                    $RoleLookup = @{}
                    foreach ($Assignment in $AppRoleAssignments) {
                        if (-not $RoleLookup.ContainsKey($Assignment.ResourceId)) {
                            $GetRoleResourceParams = @{
                                ServicePrincipalId = $Assignment.ResourceId
                                Property           = 'appRoles'
                                ErrorAction        = 'SilentlyContinue'
                            }
                            $ResourceSP = Get-MgServicePrincipal @GetRoleResourceParams
                            $RoleLookup[$Assignment.ResourceId] = @{}
                            if ($ResourceSP) {
                                foreach ($Role in $ResourceSP.AppRoles) {
                                    $RoleLookup[$Assignment.ResourceId][$Role.Id.ToString()] = $Role.Value
                                }
                            }
                        }
                    }

                    $AppRoleAssignments | ForEach-Object {
                        $RoleName = $RoleLookup[$_.ResourceId][$_.AppRoleId.ToString()]
                        [PSCustomObject]@{
                            Resource        = $_.ResourceDisplayName
                            Permission      = if ($RoleName) { $RoleName } else { $_.AppRoleId.ToString() }
                            CreatedDateTime = $_.CreatedDateTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No app role assignments found." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get app role assignments: $($_.Exception.Message)" -Level Error
            }

            # Directory Role Memberships (Entra admin roles assigned to this SP)
            try {
                $GetRoleAssignmentParams = @{
                    Filter      = "principalId eq '$($ScriptServicePrincipalObject.Id)'"
                    All         = $true
                    ErrorAction = 'Stop'
                }
                $RoleAssignments   = Get-MgRoleManagementDirectoryRoleAssignment @GetRoleAssignmentParams
                $RoleTemplatesById = Request-DirectoryRoleTemplate -Cached:$Cached -Return 'tablebyid'

                Write-IRT "Directory Role Memberships (Entra admin roles) for: ${SpName}"
                if ($RoleAssignments.Count -gt 0) {
                    $RoleAssignments | ForEach-Object {
                        [PSCustomObject]@{
                            DisplayName      = ($RoleTemplatesById[$_.RoleDefinitionId] ? $RoleTemplatesById[$_.RoleDefinitionId].DisplayName : $null) ?? $_.RoleDefinitionId
                            DirectoryScopeId = $_.DirectoryScopeId
                        }
                    } | Format-Table -AutoSize | Out-Host
                } else {
                    Write-IRT "No directory role memberships found." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get directory role memberships: $($_.Exception.Message)" -Level Error
            }

            # App Role Assigned To (users/groups/SPs that have been given access to this app)
            try {
                $GetAssignedToParams = @{
                    ServicePrincipalId = $ScriptServicePrincipalObject.Id
                    All                = $true
                    ErrorAction        = 'Stop'
                }
                $AssignedTo = Get-MgServicePrincipalAppRoleAssignedTo @GetAssignedToParams

                Write-IRT "App Role Assigned To (principals with access) for: ${SpName}"
                if ($AssignedTo.Count -gt 0) {
                    $AppRoleLookup = @{ '00000000-0000-0000-0000-000000000000' = 'Default Access' }
                    if ($FullSP) {
                        foreach ($Role in $FullSP.AppRoles) {
                            $AppRoleLookup[$Role.Id.ToString()] = $Role.DisplayName
                        }
                    }

                    $AssignedTo | ForEach-Object {
                        $RoleName = $AppRoleLookup[$_.AppRoleId.ToString()]
                        [PSCustomObject]@{
                            PrincipalDisplayName = $_.PrincipalDisplayName
                            PrincipalType        = $_.PrincipalType
                            AppRole              = if ($RoleName) { $RoleName } else { $_.AppRoleId.ToString() }
                            CreatedDateTime      = $_.CreatedDateTime
                        }
                    } | Format-Table -AutoSize | Out-Host
                }
                else {
                    Write-IRT "No principals assigned to this app." -Level Warn
                }
            }
            catch {
                Write-IRT "Failed to get app role assigned to: $($_.Exception.Message)" -Level Error
            }
        }
    }
}


#region Show-GraphServicePrincipalTree
function Show-GraphServicePrincipalTree {
    <#
    .SYNOPSIS
    Renders a Graph service principal object as a compact property tree.

    .DESCRIPTION
    Projects the service principal object, excluding the noisy AdditionalProperties
    collection, then passes the result to Format-Tree for console display. Intended
    to be called via pipeline from Show-IRTServicePrincipalInfo.

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
