#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication
#Requires -Modules ExchangeOnlineManagement
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

function Invoke-RandomEmailTraffic {
    <#
    .SYNOPSIS
        Generates internal test email traffic for message-trace testing.

    .DESCRIPTION
        Grants the current user Send-As permissions to the selected pool of users.

        Sends N emails between randomly chosen users via the Graph /sendMail endpoint.
        Each email gets a unique subject "<Subject> - <n>" and an empty body.

        Removes Send-As permissions on exit.

        Send-As granting is the default mode of operation. Disable it with
        -GrantSendAs:$false (for example, if Send-As is already configured).

        # FIXME needs testing! never used!
        Doing this with app auth would be easier. Maybe app auth is okay for
        dev only scripts?

    .EXAMPLE
        . .\Scripts\Invoke-RandomEmailTraffic.ps1
        Invoke-RandomEmailTraffic -Users user1@contoso.com, user2@contoso.com -Count 20

        Dot-source the file, then call the function with an explicit user list.

    .EXAMPLE
        . .\Scripts\Invoke-RandomEmailTraffic.ps1
        Invoke-RandomEmailTraffic -AllUsers -Count 50 -GrantSendAs:$false

        Dot-source the file, then send between all enabled mail users without
        granting Send-As (assumes the permission already exists).
    #>
    [CmdletBinding(DefaultParameterSetName = 'UserList', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'UserList')]
        [object[]] $Users,

        [Parameter(Mandatory, ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [ValidateRange(1, 100000)]
        [int] $Count = 10,

        [string] $Subject = 'Test Email',

        [ValidateRange(0, 60000)]
        [int] $DelayMilliseconds = 250,

        [switch] $SaveToSentItems,

        # Temporarily grant the signed-in account Send-As on every pool mailbox,
        # then revoke it on exit. On by default; disable with -GrantSendAs:$false.
        # Requires ExchangeOnlineManagement + an Exchange admin role
        # (Recipient/Organization Management).
        [bool] $GrantSendAs = $true,

        [ValidateRange(0, 3600)]
        [int] $SendAsPropagationSeconds = 60,

        [switch] $Trace
    )

    if ($Trace) { $InformationPreference = 'Continue' }
    function Write-Trace {
        param([Parameter(Mandatory)][string] $Message)
        Write-Information $Message -Tags 'Trace'
    }

    # --- Helpers -----------------------------------------------------------------
    function Get-FirstValue {
        # Strict-mode-safe property probe across naming variants
        param($Object, [string[]] $Names)
        foreach ($n in $Names) {
            $p = $Object.PSObject.Properties[$n]
            if ($p -and $p.Value) { return $p.Value }
        }
        return $null
    }

    function Resolve-TestUser {
        param([Parameter(Mandatory)] $InputUser)
        if ($InputUser -is [string]) {
            return [pscustomobject]@{ Sender = $InputUser; Address = $InputUser }
        }
        $mailNames = @('Mail', 'mail', 'UserPrincipalName', 'userPrincipalName')
        $idNames = @('Id', 'id', 'UserPrincipalName', 'userPrincipalName')
        $address = Get-FirstValue $InputUser $mailNames
        $senderId = Get-FirstValue $InputUser $idNames
        if (-not $senderId -or -not $address) {
            $detail = $InputUser | Out-String
            throw "Could not resolve sender id/UPN and SMTP address from: $detail"
        }
        [pscustomobject]@{ Sender = $senderId; Address = $address }
    }

    function Get-AllMailUser {
        $list = [System.Collections.Generic.List[object]]::new()
        $uri = 'https://graph.microsoft.com/v1.0/users' +
        '?$select=id,mail,userPrincipalName' +
        '&$filter=accountEnabled eq true' +
        '&$top=999'
        do {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
            foreach ($u in $resp.value) {
                if ($u.mail) { $list.Add([pscustomobject]@{ Sender = $u.id; Address = $u.mail }) }
            }
            $uri = $resp.'@odata.nextLink'
        } while ($uri)
        return $list
    }

    function Invoke-SendWithRetry {
        # Sends one message, retrying on 429/503 throttling. Returns $true on success.
        param(
            [Parameter(Mandatory)] [hashtable] $RequestParams,
            [Parameter(Mandatory)] [string]    $Label,
            [Parameter(Mandatory)] [string]    $FromAddress
        )
        $attempt = 0
        $maxAttempts = 5
        while ($true) {
            $attempt++
            try {
                Invoke-MgGraphRequest @RequestParams | Out-Null
                return $true
            }
            catch {
                $errMsg = $_.Exception.Message
                $isTransient = $errMsg -match '429' -or $errMsg -match '503'
                if ($isTransient -and $attempt -lt $maxAttempts) {
                    $wait = [math]::Pow(2, $attempt)
                    Write-Warning "Throttled/transient (attempt $attempt). Waiting $wait s..."
                    Start-Sleep -Seconds $wait
                    continue
                }
                Write-Warning "Failed '$Label' as $($FromAddress): $errMsg"
                return $false
            }
        }
    }

    # --- Connection / scope handling ---------------------------------------------
    $requiredScopes = [System.Collections.Generic.List[string]]::new()
    $requiredScopes.Add('Mail.Send')          # send as self
    $requiredScopes.Add('Mail.Send.Shared')   # send-as / on-behalf of other mailboxes
    if ($AllUsers) { $requiredScopes.Add('User.Read.All') }   # enumerate the directory

    $context = Get-MgContext
    $have = if ($context) { $context.Scopes } else { @() }
    $missing = $requiredScopes | Where-Object { $_ -notin $have }

    if (-not $context -or $missing) {
        Write-Trace "Connecting to Graph with scopes: $($requiredScopes -join ', ')"
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome | Out-Null
    }

    # --- Build the user pool ------------------------------------------------------
    $pool = if ($AllUsers) {
        Write-Trace 'Enumerating enabled, mail-enabled users...'
        Get-AllMailUsers
    } else {
        $Users | ForEach-Object { Resolve-TestUser -InputUser $_ }
    }

    if ($pool.Count -lt 2) {
        throw "Need at least 2 mail-enabled users to send between. Found $($pool.Count)."
    }
    Write-Trace "User pool size: $($pool.Count)"

    # --- Optional: grant temporary Send-As --------------------------------------
    $trustee = (Get-MgContext).Account
    $grantedTo = [System.Collections.Generic.List[string]]::new()

    if ($GrantSendAs) {
        if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
            throw 'ExchangeOnlineManagement is required for -GrantSendAs but was not found.'
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        if (-not (Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
            Write-Trace 'Connecting to Exchange Online...'
            Connect-ExchangeOnline -ShowBanner:$false | Out-Null
        }

        Write-Trace "Granting Send-As on $($pool.Count) mailbox(es) to $trustee..."
        foreach ($u in $pool) {
            $permParams = @{
                Identity    = $u.Sender
                Trustee     = $trustee
                ErrorAction = 'SilentlyContinue'
            }
            $has = Get-RecipientPermission @permParams |
                Where-Object { $_.AccessRights -contains 'SendAs' }
            if ($has) { continue }

            $addParams = @{
                Identity     = $u.Sender
                Trustee      = $trustee
                AccessRights = 'SendAs'
                Confirm      = $false
                ErrorAction  = 'Stop'
            }
            try {
                Add-RecipientPermission @addParams | Out-Null
                $grantedTo.Add($u.Sender)   # track only what we add, so cleanup is non-destructive
            } catch {
                Write-Warning "Could not grant Send-As on $($u.Address): $($_.Exception.Message)"
            }
        }

        if ($grantedTo.Count -gt 0 -and $SendAsPropagationSeconds -gt 0) {
            $msg = "Granted Send-As on $($grantedTo.Count) mailbox(es). " +
            "Send-As can take several minutes to replicate; " +
            "waiting $($SendAsPropagationSeconds)s. " +
            "Early sends may still return ErrorAccessDenied -- " +
            "re-run or raise -SendAsPropagationSeconds if that happens."
            Write-Warning $msg
            Start-Sleep -Seconds $SendAsPropagationSeconds
        }
    }

    # --- Send loop ----------------------------------------------------------------
    $sent = 0; $failed = 0
    try {
        for ($i = 1; $i -le $Count; $i++) {

            $progressParams = @{
                Activity        = 'Generating test email traffic'
                Status          = "Sending $i of $Count  (sent: $sent, failed: $failed)"
                PercentComplete = ($i / $Count) * 100
            }
            Write-Progress @progressParams

            $fromUser = $pool | Get-Random
            $recipient = $pool | Where-Object { $_.Sender -ne $fromUser.Sender } | Get-Random

            $payload = @{
                message = @{
                    subject      = "$Subject - $i"
                    body         = @{ contentType = 'Text'; content = '' }
                    toRecipients = @( @{ emailAddress = @{ address = $recipient.Address } } )
                }
                saveToSentItems = [bool]$SaveToSentItems
            }
            $uri = "https://graph.microsoft.com/v1.0/users/$($fromUser.Sender)/sendMail"
            $body = $payload | ConvertTo-Json -Depth 6

            $sendParams = @{
                Method      = 'POST'
                Uri         = $uri
                Body        = $body
                ContentType = 'application/json'
            }

            $target = "$($fromUser.Address) -> $($recipient.Address)"
            $action = "Send '$Subject - $i'"
            if ($PSCmdlet.ShouldProcess($target, $action)) {
                $retryArgs = @{
                    RequestParams = $sendParams
                    Label         = "$Subject - $i"
                    FromAddress   = $fromUser.Address
                }
                if (Invoke-SendWithRetry @retryArgs) { $sent++ } else { $failed++ }
            }

            if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
        }
    }
    finally {
        if ($grantedTo.Count -gt 0) {
            Write-Trace "Removing $($grantedTo.Count) temporary Send-As grant(s)..."
            foreach ($id in $grantedTo) {
                $removeParams = @{
                    Identity     = $id
                    Trustee      = $trustee
                    AccessRights = 'SendAs'
                    Confirm      = $false
                    ErrorAction  = 'Stop'
                }
                try {
                    Remove-RecipientPermission @removeParams | Out-Null
                } catch {
                    $warn = "Failed to remove Send-As for $id (trustee $trustee): " +
                    "$($_.Exception.Message). Remove it manually."
                    Write-Warning $warn
                }
            }
        }
    }

    Write-Progress -Activity 'Generating test email traffic' -Completed
    Write-Host "Done. Sent: $sent  Failed: $failed  Pool: $($pool.Count)" -ForegroundColor Cyan
}
