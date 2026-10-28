function Disable-IRTServicePrincipal {
    <#
    .SYNOPSIS
    Disables service principals (enterprise apps), so Entra stops issuing tokens for them.

    .DESCRIPTION
    Sets accountEnabled to false on each service principal. Users can no longer sign in to
    the app, and the app can no longer get tokens of its own. Tokens already issued stay
    valid until they expire. Use Enable-IRTServicePrincipal to reverse.

    Falls back to the service principals selected with Find-IRTServicePrincipal, in
    $Global:IRT_ServicePrincipalObjects, when no -ServicePrincipalObject is passed.

    Needs the Application.ReadWrite.All Graph permission, which Connect-IRT requests, and
    the Application Administrator or Cloud Application Administrator role.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects, as returned by Find-IRTServicePrincipal. Falls
    back to $Global:IRT_ServicePrincipalObjects if omitted.

    .EXAMPLE
    ```powershell
    Find-IRTServicePrincipal MyApp
    Disable-IRTServicePrincipal
    ```
    Two-step workflow: find then disable.

    .EXAMPLE
    ```powershell
    Disable-IRTServicePrincipal -ServicePrincipalObject $SP
    ```
    Disable a specific service principal object passed directly.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        # ServicePrincipal
        'Disable-IRTServicePrincipals',
        'Disable-ServicePrincipal', 'Disable-ServicePrincipals',
        'DisableIRTServicePrincipal', 'DisableIRTServicePrincipals',
        'DisableServicePrincipal', 'DisableServicePrincipals',
        # SP
        'Disable-IRTSP', 'Disable-IRTSPs',
        'Disable-SP', 'Disable-SPs',
        'DisableIRTSP', 'DisableIRTSPs',
        'DisableSP', 'DisableSPs',
        # EnterpriseApplication
        'Disable-IRTEnterpriseApplication', 'Disable-IRTEnterpriseApplications',
        'Disable-EnterpriseApplication', 'Disable-EnterpriseApplications',
        'DisableIRTEnterpriseApplication', 'DisableIRTEnterpriseApplications',
        'DisableEnterpriseApplication', 'DisableEnterpriseApplications'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $ServicePrincipalObject ) {
        $Params['ServicePrincipalObject'] = $ServicePrincipalObject
    }

    Set-ServicePrincipalEnabled @Params
}
