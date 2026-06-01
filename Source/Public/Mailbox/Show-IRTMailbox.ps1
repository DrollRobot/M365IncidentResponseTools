function Show-IRTMailbox {
    <#
    .SYNOPSIS
    Displays mailbox properties.

    .DESCRIPTION
    Retrieves Exchange Online mailbox configuration and permissions for one or more users
    and displays the results in the console. Includes quota settings, forwarding rules,
    litigation hold status, and current mailbox permissions.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed. Requires an active
    Exchange Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Cached
    Use pre-cached Exchange data where available instead of making new API calls.

    .EXAMPLE
    Show-IRTMailbox
    Displays mailbox details for the user in the global session.

    .EXAMPLE
    Show-IRTMailbox -UserObject $User
    Displays mailbox details for a specific user.

    .OUTPUTS
    None. Results are displayed in the console.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('ShowMailbox')]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [switch] $Cached
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $GuidPattern = '\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b'

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }
    }

    process {
        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # get user mailbox info
            $UserPrincipalName = $ScriptUserObject.UserPrincipalName
            try {
                $Params = @{
                    UserPrincipalName = $UserPrincipalName
                    PropertySets = 'All'
                    ErrorAction = 'Stop'
                }
                $Mailbox = Get-EXOMailbox @Params
            }
            catch {}
            if ( -not $Mailbox ) {
                Write-IRT "No mailbox for ${UserPrincipalName}" -Level Warn
                continue
            }

            # if forwarding address is GUID, look up user
            if ( $Mailbox.ForwardingAddress -match $GuidPattern ) {

                $UserGuid = $Mailbox.ForwardingAddress

                # get user object
                $Users = Request-GraphUser -Cached:$Cached
                $MatchingUser = $Users | Where-Object { $_.Id -eq $UserGuid }

                $ForwardingAddress = $MatchingUser.Mail
            }
            else {
                $ForwardingAddress = $Mailbox.ForwardingAddress
            }

            # convert dates to local
            try {
                $WhenCreatedLocal = $Mailbox.WhenCreatedUTC.ToLocalTime()
                $WhenChangedLocal = $Mailbox.WhenChangedUTC.ToLocalTime()
            }
            catch {}

            Write-IRT "Showing Mailbox information for: ${UserPrincipalName}"
            $OutputTable = [PSCustomObject]@{
                IsMailboxEnabled      = $Mailbox.IsMailboxEnabled
                AuditEnabled          = $Mailbox.AuditEnabled
                AuditLogAgeLimit      = $Mailbox.AuditLogAgeLimit
                DisplayName           = $Mailbox.DisplayName
                PrimarySmtpAddress    = $Mailbox.PrimarySmtpAddress
                EmailAddresses        = $Mailbox.EmailAddresses
                WhenCreated           = $WhenCreatedLocal
                WhenChanged           = $WhenChangedLocal
                ForwardingAddress     = $ForwardingAddress
                ForwardingSmtpAddress = $Mailbox.ForwardingSmtpAddress
                DeliverToMailboxAndForward = $Mailbox.DeliverToMailboxAndForward
                LitigationHoldEnabled = $Mailbox.LitigationHoldEnabled
                RetentionHoldEnabled = $Mailbox.RetentionHoldEnabled
                UsageLocation = $Mailbox.UsageLocation
            }
            $OutputTable | Format-List | Out-Host

            Write-IRT "Showing users who have delegated access to: ${UserPrincipalName}"
            $PermissionDisplayProperties = @(
                "User"
                "AccessRights"
                "IsInherited"
                "Deny"
                "InheritanceType"
            )
            $Permissions = Get-EXOMailboxPermission -Identity $UserPrincipalName
            $Permissions | Format-Table $PermissionDisplayProperties -AutoSize | Out-Host
        }
    }
}
