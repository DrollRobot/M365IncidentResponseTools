function Enable-IRTAdUser {
    <#
    .SYNOPSIS
    Enable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $true. Re-enables one or
    more disabled AD user accounts, re-fetches each to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to enable. Falls back to global session objects if omitted.

    .EXAMPLE
    Enable-IRTAdUser
    Re-enables the user(s) in the global session.

    .EXAMPLE
    Enable-IRTAdUser -UserObject $AdUser
    Re-enables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias(
        'Enable-IRTAdUsers',
        'Enable-AdUser', 'Enable-AdUsers',
        'EnableIRTAdUser', 'EnableIRTAdUsers',
        'EnableAdUser', 'EnableAdUsers',
        'Unlock-IRTAdUser', 'Unlock-IRTAdUsers',
        'Unlock-AdUser', 'Unlock-AdUsers',
        'UnlockIRTAdUser', 'UnlockIRTAdUsers',
        'UnlockAdUser', 'UnlockAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $true
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-AdUserEnabled @Params
}
