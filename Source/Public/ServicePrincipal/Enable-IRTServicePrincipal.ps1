function Enable-IRTServicePrincipal {
    <#
    .SYNOPSIS
    Enables service principals (enterprise apps) that Disable-IRTServicePrincipal disabled.

    .DESCRIPTION
    Sets accountEnabled to true on each service principal, so Entra issues tokens for it
    again.

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
    Enable-IRTServicePrincipal
    ```
    Two-step workflow: find then enable.

    .EXAMPLE
    ```powershell
    Enable-IRTServicePrincipal -ServicePrincipalObject $SP
    ```
    Enable a specific service principal object passed directly.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        # ServicePrincipal
        'Enable-IRTServicePrincipals',
        'Enable-ServicePrincipal', 'Enable-ServicePrincipals',
        'EnableIRTServicePrincipal', 'EnableIRTServicePrincipals',
        'EnableServicePrincipal', 'EnableServicePrincipals',
        # SP
        'Enable-IRTSP', 'Enable-IRTSPs',
        'Enable-SP', 'Enable-SPs',
        'EnableIRTSP', 'EnableIRTSPs',
        'EnableSP', 'EnableSPs',
        # EnterpriseApplication
        'Enable-IRTEnterpriseApplication', 'Enable-IRTEnterpriseApplications',
        'Enable-EnterpriseApplication', 'Enable-EnterpriseApplications',
        'EnableIRTEnterpriseApplication', 'EnableIRTEnterpriseApplications',
        'EnableEnterpriseApplication', 'EnableEnterpriseApplications'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $ServicePrincipalObject ) {
        $Params['ServicePrincipalObject'] = $ServicePrincipalObject
    }

    Set-ServicePrincipalEnabled @Params
}
