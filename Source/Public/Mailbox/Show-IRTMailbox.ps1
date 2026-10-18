function Show-IRTMailbox {
    <#
    .SYNOPSIS
    Displays mailbox properties.

    .DESCRIPTION
    Retrieves Exchange Online mailbox configuration and permissions for one or more users
    and displays the results in the console. Includes quota settings, forwarding rules,
    litigation hold status, automatic replies, and current mailbox permissions.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed. Requires an active
    Exchange Online connection.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Cached
    Use pre-cached Exchange data where available instead of making new API calls.

    .EXAMPLE
    ```powershell
    Show-IRTMailbox
    ```
    Displays mailbox details for the user in the global session.

    .EXAMPLE
    ```powershell
    Show-IRTMailbox -UserObject $User
    ```
    Displays mailbox details for a specific user.

    .OUTPUTS
    None. Results are displayed in the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Shows the mailbox's automatic reply settings.
    1.1.2 - FIXME temporary workaround: a failed mailbox lookup is reported during live
    test runs. See Write-IRTSuppressedError.
    1.1.1 - A failed mailbox lookup no longer shows the previous user's mailbox.
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
        Import-IRTModule -Name 'ExchangeOnlineManagement'
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

            # get user mailbox info. Cleared first: a failed lookup leaves $Mailbox as it
            # was, which would show the previous user's mailbox under this user's name.
            $UserPrincipalName = $ScriptUserObject.UserPrincipalName
            $Mailbox = $null
            try {
                $Params = @{
                    UserPrincipalName = $UserPrincipalName
                    PropertySets = 'All'
                    ErrorAction = 'Stop'
                }
                $Mailbox = Get-EXOMailbox @Params
            }
            catch {
                # FIXME: temporary workaround until a user without a mailbox, which is
                # normal and reported as a warning below, can be told apart from a
                # failed lookup.
                $SuppressParams = @{
                    ErrorRecord = $_
                    Message     = "Get-EXOMailbox failed for ${UserPrincipalName}"
                }
                Write-IRTSuppressedError @SuppressParams
            }
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

            # automatic replies. The messages are HTML; show them as plain text.
            Write-IRT "Showing automatic replies for: ${UserPrincipalName}"
            $ToText = {
                param([string] $Html)
                $Text = [System.Net.WebUtility]::HtmlDecode(($Html -replace '<[^>]+>', ' '))
                ($Text -replace '\s+', ' ').Trim()
            }
            try {
                $AutoReplyParams = @{
                    Identity    = $UserPrincipalName
                    ErrorAction = 'Stop'
                }
                $AutoReply = Get-MailboxAutoReplyConfiguration @AutoReplyParams
                [PSCustomObject]@{
                    AutoReplyState   = $AutoReply.AutoReplyState
                    StartTime        = $AutoReply.StartTime
                    EndTime          = $AutoReply.EndTime
                    ExternalAudience = $AutoReply.ExternalAudience
                    InternalMessage  = & $ToText $AutoReply.InternalMessage
                    ExternalMessage  = & $ToText $AutoReply.ExternalMessage
                } | Format-List | Out-Host
            }
            catch {
                # the mailbox exists, so a failure here is not a normal condition
                $Msg = "Failed to get automatic replies for ${UserPrincipalName}: " +
                $_.Exception.Message
                Write-IRT $Msg -Level Error
            }

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
