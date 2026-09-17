function Push-IRTAdSync {
    <#
    .SYNOPSIS
    Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle.

    .DESCRIPTION
    Triggers an AD-to-Entra delta sync as quickly as possible. The execution path is:

    1. If Active Directory is available from this device, pushes intra-AD replication
       from a writable DC via repadmin (this computer if it is one, otherwise a
       discovered DC). Skipped with a warning otherwise.
    2. If the ADSync service is running locally, invokes Start-ADSyncSyncCycle directly
       and exits.
    3. Otherwise, checks candidate servers in parallel using a runspace pool (opening a
       PSSession and looking for the service) and invokes the sync cycle remotely on the
       first server to report the service. Each check is handled as soon as it finishes,
       so slow or unreachable servers don't delay the push, and checks still running
       afterward are stopped. Candidates are the -SyncServer names if given, or else
       discovered from AD (DCs first, then other enabled servers by last logon).

    The ActiveDirectory module is only required for AD discovery. It is not needed when
    the ADSync service is on this device or when -SyncServer is given; without it, only
    the replication push is skipped.

    Domain admin credentials are cached in $Global:Storage for the session.
    Use -ResetCredentials to force a re-prompt.

    .PARAMETER ResetCredentials
    Clear the cached domain admin credentials and prompt again before connecting.

    .PARAMETER SyncServer
    Target one or more specific server names directly, bypassing AD discovery. The
    ActiveDirectory module is not required when this is used.

    .PARAMETER ThrottleLimit
    Maximum number of parallel runspaces used for server discovery. Default: 20.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync
    ```
    Automatically discovers and triggers a delta sync.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync -SyncServer 'sync01.contoso.com'
    ```
    Triggers sync on a known server without discovery.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync -ResetCredentials
    ```
    Re-prompts for domain admin credentials before syncing.

    .OUTPUTS
    None. Progress is written to the console.

    .NOTES
    Version: 2.1.0
    2.1.0 - ActiveDirectory module only required for AD discovery.
            Removed ping check; session and service check errors are reported per server.
            Server checks are handled as they finish instead of in query order.
            AD replication is pushed from this computer if it is a writable DC, otherwise
            from a discovered DC, so it no longer requires running on a DC.
            Fixed single-DC domains merging all discovered server names into one hostname.
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

        # push AD replication first when AD is available. optional: the sync server may not
        # have the ActiveDirectory module, and a failure here must not block the sync
        $AdAvailable = Test-AdAvailable
        if ($AdAvailable) {
            Import-IRTModule -Name 'ActiveDirectory'
            try {
                $DomainController = Get-TargetDomainController
                Push-AdReplication -Server $DomainController
            }
            catch {
                $Msg = "Finding a domain controller failed. Skipping AD replication push: $_"
                Write-IRT $Msg -Level Warn
            }
        }
        else {
            $Msg = "Active Directory not available on this device. Skipping AD replication push."
            Write-IRT $Msg -Level Warn
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
            # user supplied explicit targets - skip AD query and RSAT check entirely
            $ServerNamesInQueryOrder = $SyncServer
        }
        else {
            # require AD RSAT for discovery
            if (-not $AdAvailable) {
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
            # @() on both: with a single DC, .Name is a string, and string + array
            # concatenates every name into one bogus hostname
            $DomainControllerNames = @((Get-ADDomainController -Filter *).Name)
            $NonDCServerNames = @(
                $ServerNames | Where-Object { $_ -notin $DomainControllerNames }
            )
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
        # parallel discovery: open session + check adsync service
        # no ping first: hosts may block ICMP but still accept PS remoting, so session
        # errors are the reachability check

        $DiscoveryScriptBlock = {
            param(
                [string] $ComputerName,
                [System.Management.Automation.PSCredential] $Credentials
            )

            $Result = [PSCustomObject]@{
                ComputerName  = $ComputerName
                SessionOpened = $false
                AdsyncPresent = $false
                Session       = $null
                Error         = $null
            }

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
                $Result.Error = "$_"
                return $Result
            }

            # check for adsync service
            try {
                $CheckParams = @{
                    Session     = $Result.Session
                    ScriptBlock = { [bool](Get-Service 'adsync' -ErrorAction SilentlyContinue) }
                    ErrorAction = 'Stop'
                }
                $Result.AdsyncPresent = Invoke-Command @CheckParams
            }
            catch {
                $Result.Error = "$_"
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
            $Pending = [System.Collections.Generic.List[hashtable]]::new($Runspaces)

            # handle each check as soon as it finishes, so a slow or unreachable server
            # never delays the push; checks still running after a push are stopped in finally
            while ($Pending.Count -gt 0 -and -not $Synced) {

                $ProgressParams = @{
                    Activity        = 'Discovering sync server'
                    Status          = "$Done of $Total servers checked"
                    PercentComplete = [math]::Floor( ( $Done / $Total ) * 100 )
                }
                Write-Progress @ProgressParams

                $Finished = @($Pending | Where-Object { $_.Handle.IsCompleted })
                if ($Finished.Count -eq 0) {
                    Start-Sleep -Milliseconds 100
                    continue
                }

                foreach ($RS in $Finished) {

                    $null = $Pending.Remove($RS)
                    $DiscoveryResult = ($RS.PS.EndInvoke($RS.Handle))[0]
                    $RS.PS.Dispose()
                    $RS.PS = $null
                    $Done++

                    $CN = $RS.ComputerName

                    if (-not $DiscoveryResult.SessionOpened) {
                        $Msg = "Opening session on ${CN} failed: $($DiscoveryResult.Error)"
                        Write-IRT $Msg -Level Warn
                        continue
                    }

                    if ($DiscoveryResult.Error) {
                        $Msg = "Checking adsync service on ${CN} failed: " +
                        "$($DiscoveryResult.Error)"
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
                        $SyncParams = @{
                            Session     = $DiscoveryResult.Session
                            ScriptBlock = {
                                [string]( Start-ADSyncSyncCycle -PolicyType Delta ).Result
                            }
                        }
                        $SyncResult = Invoke-Command @SyncParams

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
                        $RemoveParams = @{
                            Session     = $DiscoveryResult.Session
                            ErrorAction = 'SilentlyContinue'
                        }
                        Remove-PSSession @RemoveParams
                    }

                    if ($Synced) { break }
                }
            }

            if (-not $Synced) {
                $Msg = 'No adsync server was found or sync could not be pushed on any server.'
                Write-IRT $Msg -Level Error
            }
        }
        finally {
            Write-Progress -Activity 'Discovering sync server' -Completed

            # stop and dispose any runspaces not yet processed (e.g. still checking after a push)
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
