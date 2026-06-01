function Show-IRTAdUser {
    <#
    .SYNOPSIS
    Displays AD user properties.

    .DESCRIPTION
    Retrieves all properties of an on-premises AD user object, converts every DateTime
    value to local time, and displays the result with Format-Tree. Falls back to
    $Global:IRT_UserObject (via Get-AdGlobalUserObject) if no -UserObjects is passed.

    .PARAMETER UserObjects
    One or more AD user objects to display. Falls back to global session objects if omitted.

    .EXAMPLE
    Show-IRTAdUser
    Displays info for the user(s) in the global session.

    .EXAMPLE
    Show-IRTAdUser -UserObjects $AdUser
    Displays info for a specific AD user object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Switched to Format-Tree with dynamic DateTime conversion.
    1.1.2 - Added pwdLastSet
    #>
    [Alias(
        'Show-IRTAdUsers',
        'Show-AdUser', 'Show-AdUsers',
        'ShowIRTAdUser', 'ShowIRTAdUsers',
        'ShowAdUser', 'ShowAdUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects
    )

    begin {

        # if not passed directly, find global
        if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-AdGlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObjects
        }
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        $ExcludeProperty = @(
            'c'
            'co'
            'codePage'
            'countryCode'
            'createTimeStamp'
            'dSCorePropagationData'
            'DoesNotRequirePreAuth'
            'extensionName'
            'HomedirRequired'
            'instanceType'
            'l'
            'lastLogon'
            'lastLogonTimestamp'
            'localPolicyFlags'
            'MNSLogonAccount'
            'modifyTimeStamp'
            'msExchALObjectVersion'
            'msDS-SupportedEncryptionTypes'
            'msDS-User-Account-Control-Computed'
            'nTSecurityDescriptor'
            'objectSid'
            'primaryGroupID'
            'PropertyCount'
            'PropertyNames'
            'sAMAccountType'
            'sDRightsEffective'
            'SID'
            'TrustedForDelegation'
            'TrustedToAuthForDelegation'
            'userAccountControl'
            'userParameters'
            'uSNChanged'
            'uSNCreated'
        )

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # get user object with all properties
            $FullObject = $ScriptUserObject | Get-AdUser -Property *

            $FileTimeProperties = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@(
                    'accountExpires'
                    'badPasswordTime'
                    'lastLogon'
                    'lastLogonTimestamp'
                    'lockoutTime'
                    'msExchLastExchangeChangedTime'
                    'msDS-UserPasswordExpiryTimeComputed'
                    'pwdLastSet'
                ),
                [System.StringComparer]::OrdinalIgnoreCase
            )

            $Props = [ordered]@{}
            foreach ($Prop in ($FullObject.PSObject.Properties | Sort-Object Name)) {
                # convert DateTime objects to local time
                if ($Prop.Value -is [DateTime]) {
                    $Props[$Prop.Name] = $Prop.Value.ToLocalTime()
                }
                # Convert Int64 objects to human readable time
                elseif ($Prop.Value -is [long] -and $FileTimeProperties.Contains($Prop.Name)) {
                    if ($Prop.Value -eq 0 -or $Prop.Value -eq [Int64]::MaxValue) {
                        $Props[$Prop.Name] = 'Never'
                    }
                    else {
                        $Props[$Prop.Name] = [DateTime]::FromFileTime($Prop.Value).ToLocalTime()
                    }
                }
                else {
                    $Props[$Prop.Name] = $Prop.Value
                }
            }

            $FormatParams = @{
                Depth           = 5
                OmitNullOrEmpty = $true
                ExcludeProperty = $ExcludeProperty
            }
            [PSCustomObject]$Props | Format-Tree @FormatParams
            Write-IRT 'Note: all dates are displayed in local time.'
        }
    }
}
