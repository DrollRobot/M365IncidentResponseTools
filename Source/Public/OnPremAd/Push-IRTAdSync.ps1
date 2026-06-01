function Push-IRTAdSync {
    <#
    .SYNOPSIS
    Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle.

    .DESCRIPTION
    Triggers an AD-to-Entra delta sync as quickly as possible. The execution path is:

    1. If running on a domain controller, fires 'repadmin /syncall /AdeP' to force
       intra-AD replication first.
    2. If the ADSync service is running locally, invokes Start-ADSyncSyncCycle directly
       and exits.
    3. Otherwise, discovers candidate servers (DCs first, then other enabled AD computers
       by last logon) in parallel using a runspace pool and invokes the sync cycle
       remotely on the first server found to have the service.

    Domain admin credentials are cached in $Global:Storage for the session.
    Use -ResetCredentials to force a re-prompt.

    .PARAMETER ResetCredentials
    Clear the cached domain admin credentials and prompt again before connecting.

    .PARAMETER SyncServer
    Target one or more specific server names directly, bypassing AD discovery.

    .PARAMETER ThrottleLimit
    Maximum number of parallel runspaces used for server discovery. Default: 20.

    .EXAMPLE
    Push-IRTAdSync
    Automatically discovers and triggers a delta sync.

    .EXAMPLE
    Push-IRTAdSync -SyncServer 'sync01.contoso.com'
    Triggers sync on a known server without discovery.

    .EXAMPLE
    Push-IRTAdSync -ResetCredentials
    Re-prompts for domain admin credentials before syncing.

    .OUTPUTS
    None. Progress is written to the console.

    .NOTES
    Version: 2.0.0
    2.0.0 - Parallel server discovery via runspace pool (ping, open session, service check).
            Added -SyncServer parameter to target specific servers directly, bypassing AD query.
            Added -ThrottleLimit parameter.
    #>
    [Alias(
        'Push-IRTAdSyncs',
        'Push-AdSync', 'Push-AdSyncs',
        'PushIRTAdSync', 'PushIRTAdSyncs',
        'PushAdSync', 'PushAdSyncs',
        'AdSync', 'SyncAd'
    )]
    [CmdletBinding()]
    param(
        [Alias('Reset', 'ResetPassword')]
        [switch] $ResetCredentials,

        [Alias('SyncServers')]
        [string[]] $SyncServer,

        [ValidateRange(1, 50)]
        [int] $ThrottleLimit = 20
    )

    process {

        if (Test-RunningOnDomainController) {
            Write-IRT "Pushing AD replication..."
            $null = repadmin /syncall /AdeP
        }
        else {
            Write-IRT "Not running on a domain controller. Skipping AD replication." -Level Warn
        }

        # if sync service is running on this server, push sync locally
        $SyncService = Get-Service -Name 'adsync' -ErrorAction SilentlyContinue
        if ($SyncService) {
            Write-IRT "Pushing sync."
            Start-ADSyncSyncCycle -PolicyType Delta
            return
        }
        Write-IRT "Adsync service not running on this device."

        if (-not (Get-YesNo "Search for server running adsync?")) {
            return
        }

        # build the ordered candidate server list
        if ($SyncServer) {
            # user supplied explicit targets - skip AD query, RSAT check, and DC check entirely
            $ServerNamesInQueryOrder = $SyncServer
        }
        else {
            # require AD RSAT for discovery
            if (-not (Test-AdAvailable)) {
                $Msg = "Active Directory can't be reached from this device. " +
                "Specify hostnames with -SyncServer."
                Write-IRT $Msg -Level Error
                return
            }

            # query AD for all enabled servers
            $QueryParams = @{
                Filter     = "OperatingSystem -like '*server*' -and Enabled -eq 'true'"
                Properties = 'Name', 'OperatingSystem', 'LastLogOnDate'
            }
            $ServerNames = (
                Get-AdComputer @QueryParams | Sort-Object LastLogOnDate -Descending
            ).Name

            # domain controllers first, then remaining servers by last logon date
            $DomainControllerNames = (Get-ADDomainController -Filter *).Name
            $NonDCServerNames = $ServerNames |
                Where-Object { $_ -notin $DomainControllerNames }
            $ServerNamesInQueryOrder = $DomainControllerNames + $NonDCServerNames
        }

        # request credentials from user
        if (-not $Global:Storage -or $ResetCredentials) {

            $UserName = Read-Host "Enter domain admin username"
            $Password = Read-Host -AsSecureString "Enter domain admin password"

            $CredParams = @{
                TypeName     = 'System.Management.Automation.PSCredential'
                ArgumentList = @($UserName, $Password)
            }
            try {
                $Global:Storage = New-Object @CredParams -ErrorAction Stop
            }
            catch {
                $_
                throw "Unable to build credential object."
            }
        }
        $Credentials = $Global:Storage

        # close any existing sessions
        Get-PSSession | Remove-PSSession

        ########################################################################
        # parallel discovery: ping + open session + check adsync service

        $DiscoveryScriptBlock = {
            param(
                [string] $ComputerName,
                [System.Management.Automation.PSCredential] $Credentials
            )

            $Result = [PSCustomObject]@{
                ComputerName  = $ComputerName
                Reachable     = $false
                SessionOpened = $false
                AdsyncPresent = $false
                Session       = $null
                Error         = $null
            }

            # ping
            try {
                $Reply = ([System.Net.NetworkInformation.Ping]::new()).Send($ComputerName, 1000)
                $Result.Reachable = $Reply.Status -eq 'Success'
            }
            catch {
                $Result.Reachable = $false
            }

            if (-not $Result.Reachable) { return $Result }

            # open session
            try {
                $SessionParams = @{
                    ComputerName = $ComputerName
                    Credential   = $Credentials
                    ErrorAction  = 'Stop'
                }
                $Result.Session = New-PSSession @SessionParams
                $Result.SessionOpened = $true
            }
            catch {
                $Result.Error = "Session failed: $_"
                return $Result
            }

            # check for adsync service
            try {
                $Result.AdsyncPresent = Invoke-Command -Session $Result.Session -ScriptBlock {
                    [bool](Get-Service 'adsync' -ErrorAction SilentlyContinue)
                }
            }
            catch {
                $Result.Error = "Service check failed: $_"
            }

            # close session now if adsync is not present - only keep sessions where adsync was found
            if (-not $Result.AdsyncPresent) {
                Remove-PSSession -Session $Result.Session -ErrorAction SilentlyContinue
                $Result.Session = $null
            }

            return $Result
        }

        $Pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
            1, $ThrottleLimit
        )
        $Runspaces = [System.Collections.Generic.List[hashtable]]::new()
        $Pool.Open()

        try {
            foreach ($ComputerName in $ServerNamesInQueryOrder) {
                $ComputerName = ($ComputerName -split '\.')[0]
                if ([string]::IsNullOrWhiteSpace($ComputerName)) { continue }

                $PS = [System.Management.Automation.PowerShell]::Create()
                $PS.RunspacePool = $Pool
                $null = $PS.AddScript($DiscoveryScriptBlock)
                $null = $PS.AddArgument($ComputerName).AddArgument($Credentials)
                $RSEntry = @{
                    ComputerName = $ComputerName
                    PS           = $PS
                    Handle       = $PS.BeginInvoke()
                }
                $Runspaces.Add($RSEntry)
            }

            $Total = $Runspaces.Count
            $Done = 0
            $Synced = $false

            # process runspaces in priority order;
            # EndInvoke blocks per entry while others keep running
            foreach ($RS in $Runspaces) {

                $ProgressParams = @{
                    Activity        = 'Discovering sync server'
                    Status          = "$Done of $Total servers checked"
                    PercentComplete = [math]::Floor( ( $Done / $Total ) * 100 )
                }
                Write-Progress @ProgressParams

                $DiscoveryResult = ($RS.PS.EndInvoke($RS.Handle))[0]
                $RS.PS.Dispose()
                $RS.PS = $null
                $Done++

                $CN = $RS.ComputerName

                if (-not $DiscoveryResult.Reachable) {
                    Write-IRT "Pinging ${CN}: FAILED." -Level Warn
                    continue
                }

                if (-not $DiscoveryResult.SessionOpened) {
                    $Msg = "Opening session on ${CN} failed: $($DiscoveryResult.Error)"
                    Write-IRT $Msg -Level Warn
                    continue
                }

                if (-not $DiscoveryResult.AdsyncPresent) {
                    Write-IRT "Adsync service not present on ${CN}."
                    continue
                }

                # adsync found - attempt push
                Write-IRT "Adsync service found on ${CN}. Pushing sync..."
                try {
                    $SyncResult = Invoke-Command -Session $DiscoveryResult.Session -ScriptBlock {
                        [string]( Start-ADSyncSyncCycle -PolicyType Delta ).Result
                    }

                    if ($SyncResult -eq 'Success') {
                        Write-IRT "Sync pushed successfully on ${CN}."
                        $Synced = $true
                    }
                    else {
                        Write-IRT "Sync failed on ${CN} (result: $SyncResult)." -Level Error
                    }
                }
                catch {
                    Write-IRT "Sync failed on ${CN}: $_" -Level Error
                }
                finally {
                    Remove-PSSession -Session $DiscoveryResult.Session -ErrorAction SilentlyContinue
                }

                if ($Synced) { break }
            }

            if (-not $Synced) {
                $Msg = 'No adsync server was found or sync could not be pushed on any server.'
                Write-IRT $Msg -Level Error
            }
        }
        finally {
            Write-Progress -Activity 'Discovering sync server' -Completed

            # stop and dispose any runspaces not yet processed (e.g. after an early break)
            foreach ($RS in $Runspaces) {
                if ($null -ne $RS.PS) {
                    try { $RS.PS.Stop() } catch {}
                    $RS.PS.Dispose()
                }
            }

            $Pool.Close()
            $Pool.Dispose()

            # remove any sessions that leaked from unprocessed runspaces
            Get-PSSession | Remove-PSSession
        }
    }
}
