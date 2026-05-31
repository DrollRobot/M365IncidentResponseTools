function New-RoleMemberObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', ''
    )]
    param(
        [string] $Id,
        [Alias('Roles')] [string] $Role,
        [string] $RoleSource,
        $GraphObject
    )

    switch ( $GraphObject.ObjectType ) {
        'User' {
            return [pscustomobject]@{
                ObjectType        = 'User'
                Id                = $Id
                Enabled           = $GraphObject.AccountEnabled
                DisplayName       = $GraphObject.DisplayName
                UserPrincipalName = $GraphObject.UserPrincipalName
                RoleSource        = $RoleSource
                Roles             = $Role
            }
        }
        'ServicePrincipal' {
            return [pscustomobject]@{
                ObjectType           = 'ServicePrincipal'
                Id                   = $Id
                Enabled              = $GraphObject.AccountEnabled
                DisplayName          = $GraphObject.DisplayName
                ServicePrincipalType = $GraphObject.ServicePrincipalType
                Description          = $GraphObject.Description
                RoleSource           = $RoleSource
                Roles             = $Role
            }
        }
        'Group' {
            return [pscustomobject]@{
                ObjectType  = 'Group'
                Id          = $Id
                DisplayName = $GraphObject.DisplayName
                Description = $GraphObject.Description
                RoleSource  = $RoleSource
                Roles             = $Role
            }
        }
        default {
            Write-Error "Unknown object type '$($GraphObject.ObjectType)' for Id: ${Id}"
        }
    }
}