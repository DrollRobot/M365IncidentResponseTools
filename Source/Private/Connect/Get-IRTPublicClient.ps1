function Get-IRTPublicClient {
    <#
    .SYNOPSIS
    Returns the session's MSAL public client app for a client ID, building it if needed.

    .DESCRIPTION
    Internal helper. Maintains one PublicClientApplication per client ID in
    $Global:IRT_Session.Apps, so every service that shares a client ID (Exchange
    and IPPS share the EXO first-party app) deterministically shares one token
    cache. Apps are built with the session's cloud authority and, when
    EnableTokenCache is set, the persistent on-disk cache is registered at build
    time - exactly once per client ID per session.

    Cache registration failures are surfaced loudly (error-level) because the
    operator consequence is concrete: every new PowerShell session will require
    full interactive re-authentication.

    .PARAMETER ClientId
    The application (client) ID to return an MSAL app for.

    .PARAMETER MsalCachePath
    Override the path for the persistent MSAL token cache file. Defaults to
    $Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

    .EXAMPLE
    Get-IRTPublicClient -ClientId 'fb78d390-0c51-40cd-8e17-fdbfab77341b'

    .OUTPUTS
    Microsoft.Identity.Client.IPublicClientApplication

    .NOTES
    Version: 1.0.0
    #>
    [OutputType('Microsoft.Identity.Client.IPublicClientApplication')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ClientId,

        [string] $MsalCachePath = $Global:IRT_Config.MsalCachePath
    )

    Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'PSFramework'

    if (-not $Global:IRT_Session -or
        -not $Global:IRT_Session.TenantId -or
        -not $Global:IRT_Session.CloudConfig) {
        throw 'No active IRT session. Run Connect-IRT first.'
    }
    if ($null -eq $Global:IRT_Session.Apps) {
        throw 'IRT session has no Apps store. Run Connect-IRT to initialize the session.'
    }

    $Existing = $Global:IRT_Session.Apps[$ClientId]
    if ($Existing) {
        Write-PSFMessage -Level 8 -Message (
            "Get-IRTPublicClient: Reusing MSAL app for ClientId $ClientId.")
        return $Existing
    }

    $null = Import-MsalAssembly

    $TenantId = $Global:IRT_Session.TenantId
    $Authority = "$($Global:IRT_Session.CloudConfig.LoginHost)/$TenantId"
    Write-PSFMessage -Level 8 -Message (
        "Get-IRTPublicClient: Building new MSAL public client app " +
        "(ClientId: $ClientId, Authority: $Authority).")

    $PcaBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]
    $NewApp = $PcaBuilder::Create($ClientId).
    WithAuthority($Authority).
    WithRedirectUri('http://localhost').
    Build()

    if ($Global:IRT_Config.EnableTokenCache) {
        try {
            Register-MsalCache -App $NewApp -CachePath $MsalCachePath
            Write-PSFMessage -Level 8 -Message (
                "Get-IRTPublicClient: Persistent token cache " +
                "registered at: $MsalCachePath")
        } catch {
            Write-IRT ("Persistent token cache could NOT be attached for client " +
                "${ClientId}: $_") -Level Error
            Write-IRT ('You WILL be prompted to sign in again in every new PowerShell ' +
                "session. Check write access to '$MsalCachePath', or set " +
                'EnableTokenCache to false in config.json to silence this error.') -Level Error
        }
    }

    $Global:IRT_Session.Apps[$ClientId] = $NewApp
    return $NewApp
}
