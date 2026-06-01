function Disable-IRTAdUser {
    <#
    .SYNOPSIS
    Disable on-premises AD user account(s).

    .DESCRIPTION
    Thin wrapper around Set-AdUserEnabled that sets Enabled = $false. Disables one or
    more AD user accounts, re-fetches each account to confirm the change, then triggers
    AD replication and an Azure AD delta sync if the relevant services are available.

    Falls back to $Global:UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more AD user objects to disable. Falls back to global session objects if omitted.

    .EXAMPLE
    Disable-IRTAdUser
    Disables the user(s) in the global session.

    .EXAMPLE
    Disable-IRTAdUser -UserObject $AdUser
    Disables a specific user.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 2.0.0
    #>
    [Alias(
        'Disable-IRTAdUsers',
        'Disable-AdUser', 'Disable-AdUsers',
        'DisableIRTAdUser', 'DisableIRTAdUsers',
        'DisableAdUser', 'DisableAdUsers',
        'Lock-IRTAdUser', 'Lock-IRTAdUsers',
        'Lock-AdUser', 'Lock-AdUsers',
        'LockIRTAdUser', 'LockIRTAdUsers',
        'LockAdUser', 'LockAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject
    )

    $Params = @{
        Enabled = $false
    }
    if ( $UserObject ) {
        $Params['UserObject'] = $UserObject
    }

    Set-AdUserEnabled @Params
}
