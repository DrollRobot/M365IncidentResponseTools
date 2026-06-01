function Get-IRTNonInteractiveSignIn {
    <#
    .SYNOPSIS
    Downloads non-interactive Entra ID sign-in logs for one or more users.

    .DESCRIPTION
    A convenience wrapper around Get-IRTEntraSignInLog that sets -NonInteractive automatically.
    Non-interactive sign-ins include token refresh events, legacy protocol logins, and
    service-to-service calls - often missed during investigations that focus only on
    interactive sign-ins.

    Date range and output behavior are identical to Get-IRTEntraSignInLog.
    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Days
    Number of days back to search.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Script
    Return raw objects instead of exporting to Excel. Default: $false.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .EXAMPLE
    Get-IRTNonInteractiveSignIn
    Downloads non-interactive sign-in logs for the user in the global session.

    .EXAMPLE
    Get-IRTNonInteractiveSignIn -UserObject $User -Days 30
    Downloads 30 days of non-interactive sign-ins for a specific user.

    .OUTPUTS
    None by default. PSCustomObject[] when -Script is $true.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('GetNILog', 'GetNILogs', 'NILog', 'NILogs')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObjects' )]
        [psobject[]] $UserObject,

        [int] $Days,
        [boolean] $Beta = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [boolean] $Script = $false,
        [boolean] $Open = $true
    )

    begin {
        Update-IRTToken -Service 'Graph'

        # variables
        $Params = @{
            UserObjects = $UserObject
            NonInteractive = $true
            Days = $Days
            Xml = $Xml
            Beta = $Beta
            Open = $Open
        }
        if ( $Script ) {
            $Params['Script'] = $true
        }
    }

    process {

        # run command
        Get-IRTEntraSignInLog @Params
    }
}
