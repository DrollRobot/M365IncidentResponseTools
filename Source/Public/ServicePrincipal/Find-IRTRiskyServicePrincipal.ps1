function Find-IRTRiskyServicePrincipal {
    <#
    .SYNOPSIS
    Identifies potentially malicious OAuth applications registered in the tenant.

    .DESCRIPTION
    Checks all service principals in the tenant against a configurable list of threat
    intelligence feeds to find known malicious OAuth app IDs. For each match, displays
    app details, the source feed, and the users who have granted consent to the app.

    Also reports on tenant-level app registration and user consent policies.

    New feeds can be added to the $ThreatFeeds array in the begin block.
    Each feed requires: Name, Url, Parser (scriptblock), AppIdField, and DisplayProperties.

    Requires the PSToml module for feeds that use TOML format.

    .PARAMETER Cached
    Use pre-cached Graph service principal and OAuth grant data instead of making new
    API calls. Speeds up repeated runs during the same session.

    .EXAMPLE
    Find-IRTRiskyServicePrincipal
    Queries all threat intelligence feeds and reports any matches in the tenant.

    .EXAMPLE
    Find-IRTRiskyServicePrincipal -Cached
    Same as above but uses cached Graph data from the current session.

    .OUTPUTS
    None. Results are written to the console.

    .NOTES
    Requires an active Graph connection with appropriate permissions.
    Threat intelligence feeds are fetched live from GitHub at runtime.
    #>
    [Alias('RiskyApps', 'RiskySPs',
        'FindRiskySP', 'FindRiskySPs',
        'FindRiskyApp', 'FindRiskyApps',
        'FindRiskyApplication', 'FindRiskyApplications',
        'FindRiskyServicePrincipal', 'FindRiskyServicePrincipals',
        'FindRiskyEnterpriseApp', 'FindRiskyEnterpriseApps',
        'Find-RiskyApplication')]
    param (
        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # variables
        $UserDisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'UserPrincipalName'
            'Id'
        )
        $ThreatFeeds = @(
            @{
                Name              = 'Huntress RogueApps'
                Url               = 'https://raw.githubusercontent.com/' +
                'huntresslabs/rogueapps/refs/heads/main/data/rogueapps.toml'
                Parser            = {
                    param($r)
                    ($r | ConvertFrom-Toml).apps | ForEach-Object { [PSCustomObject]$_ }
                }
                AppIdField        = 'appId'
                DisplayProperties = @('appDisplayName', 'description', 'tags', 'references')
                Apps              = $null
            }
            @{
                Name              = 'Syne/randomaccess3'
                Url               = 'https://raw.githubusercontent.com/' +
                'randomaccess3/detections/refs/heads/main/' +
                'M365_Oauth_Apps/MaliciousOauthAppDetections.json'
                Parser            = { param($r) ($r | ConvertFrom-Json).Applications }
                AppIdField        = 'AppId'
                DisplayProperties = @('Name', 'Description', 'Categories', 'References')
                Apps              = $null
            }
        )
        $FoundApps = $false

        $ServicePrincipals = Request-GraphServicePrincipal -Cached:$Cached
        $PermissionGrants = Request-GraphOauth2Grant -Cached:$Cached
        $Users = Request-GraphUser -Cached:$Cached
    }

    process {
        ### show settings
        Write-IRT "Tenant App settings:"
        $AuthPolicy = Get-MgPolicyAuthorizationPolicy
        $DefaultRolePermissions = $AuthPolicy.DefaultUserRolePermissions
        $PoliciesAssigned = $DefaultRolePermissions.PermissionGrantPoliciesAssigned |
            Where-Object { $_ -match 'ManagePermissionGrantsForSelf' }
        $Output = [PSCustomObject]@{
            UsersAllowedToCreateApps     = $DefaultRolePermissions.AllowedToCreateApps
            UsersAllowedToConsentForApps = [bool]$PoliciesAssigned
        }
        $Output | Format-List | Out-Host


        # fetch threat feeds
        foreach ($Feed in $ThreatFeeds) {
            $Feed.Apps = & $Feed.Parser (Invoke-WebRequest -Uri $Feed.Url).Content
        }

        # build combined list
        $SusAppIds = @(foreach ($Feed in $ThreatFeeds) {
                $Feed.Apps | ForEach-Object { $_.$($Feed.AppIdField) }
            }) | Sort-Object -Unique

        # find risky apps
        $RiskyApps = $ServicePrincipals | Where-Object { $_.AppId -in $SusAppIds }

        foreach ($RiskyApp in $RiskyApps) {

            $FoundApps = $true

            # find permission grants for the app
            $AppGrants = $PermissionGrants | Where-Object { $_.ClientId -eq $RiskyApp.Id }

            # show app information
            Write-IRT "App Information:"
            foreach ($Feed in $ThreatFeeds) {
                $FeedInfo = $Feed.Apps | Where-Object { $_.$($Feed.AppIdField) -eq $RiskyApp.AppId }
                if ($FeedInfo) {
                    $ExprHash = @{
                        Name       = 'Source'
                        Expression = { $Feed.Name }
                    }
                    $Properties = $Feed.DisplayProperties + @($ExprHash)
                    $FeedInfo | Select-Object $Properties | Format-List | Out-Host
                    break
                }
            }

            # show users who have the app
            Write-IRT "Users who have this app:"
            $Users |
                Where-Object { $_.Id -in $AppGrants.PrincipalId } |
                Format-Table $UserDisplayProperties |
                Out-Host
        }

        if ($FoundApps -eq $false) {
            Write-IRT "No risky apps found."
        }
    }
}
