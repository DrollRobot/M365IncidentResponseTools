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
    3. If an earlier run in this session synced on a server, pushes the sync there
       without asking or searching. If that fails, the saved server is forgotten and the
       search below runs.
    4. Otherwise, checks candidate servers in parallel using a runspace pool (opening a
       PSSession and looking for the service) and invokes the sync cycle remotely on the
       first server to report the service. Each check is handled as soon as it finishes,
       so slow or unreachable servers don't delay the push, and checks still running
       afterward are stopped. Candidates are the -SyncServer names if given, or else
       discovered from AD (DCs first, then other enabled servers by last logon).

    The server that synced is saved in $Global:IRT_AdSyncServer for the session. Use
    -ResetSyncServer to search again, or -SyncServer to target other servers.

    The ActiveDirectory module is only required for AD discovery. It is not needed when
    the ADSync service is on this device, when a saved server syncs, or when -SyncServer
    is given; without it, only the replication push is skipped.

    Domain admin credentials are cached in $Global:Storage for the session.
    Use -ResetCredentials to force a re-prompt.

    .PARAMETER ResetCredentials
    Clear the cached domain admin credentials and prompt again before connecting.

    .PARAMETER ResetSyncServer
    Forget the sync server saved by an earlier run, and search for it again.

    .PARAMETER SyncServer
    Target one or more specific server names directly, bypassing the saved server and AD
    discovery. The ActiveDirectory module is not required when this is used.

    .PARAMETER ThrottleLimit
    Maximum number of parallel runspaces used for server discovery. Default: 20.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync
    ```
    Automatically discovers and triggers a delta sync. Run again, it syncs on the same
    server without searching.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync -SyncServer 'sync01.contoso.com'
    ```
    Triggers sync on a known server without discovery.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync -ResetSyncServer
    ```
    Ignores the saved sync server and searches for it again.

    .EXAMPLE
    ```powershell
    Push-IRTAdSync -ResetCredentials
    ```
    Re-prompts for domain admin credentials before syncing.

    .OUTPUTS
    None. Progress is written to the console.

    .NOTES
    Version: 2.2.0
    2.2.0 - Saves the server that synced, and syncs there next time without searching.
            Added -ResetSyncServer parameter.
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

        [switch] $ResetSyncServer,

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
        $SyncService = Get-LocalAdSyncService
        if ($SyncService) {
            Write-IRT "Pushing sync."
            Start-ADSyncSyncCycle -PolicyType Delta
            return
        }
        Write-IRT "Adsync service not running on this device."

        if ($ResetSyncServer) {
            Remove-Variable -Name 'IRT_AdSyncServer' -Scope Global -ErrorAction Ignore
        }

        # the server that synced last time is used without asking, unless -SyncServer
        # names other targets
        $SavedServer = if (-not $SyncServer) { $Global:IRT_AdSyncServer }
        if (-not $SavedServer -and -not (Get-YesNo "Search for server running adsync?")) {
            return
        }

        # require AD RSAT for discovery. checked before the credential prompt
        $NoAdMsg = "Active Directory can't be reached from this device. " +
        "Specify hostnames with -SyncServer."
        if (-not $SavedServer -and -not $SyncServer -and -not $AdAvailable) {
            Write-IRT $NoAdMsg -Level Error
            return
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
        $PushParams = @{
            Credential    = $Global:Storage
            ThrottleLimit = $ThrottleLimit
        }

        if ($SavedServer) {
            Write-IRT "Using saved sync server ${SavedServer}. Use -ResetSyncServer to search."
            if (Push-RemoteAdSync -ComputerName $SavedServer @PushParams) {
                return
            }

            # forget it, so the next run doesn't wait on it again
            Remove-Variable -Name 'IRT_AdSyncServer' -Scope Global -ErrorAction Ignore
            $Msg = "Sync failed on saved server ${SavedServer}. " +
            "Searching for server running adsync."
            Write-IRT $Msg -Level Warn
            if (-not $AdAvailable) {
                Write-IRT $NoAdMsg -Level Error
                return
            }
        }

        # build the ordered candidate server list
        if ($SyncServer) {
            # user supplied explicit targets - skip AD query and RSAT check entirely
            $ServerNamesInQueryOrder = $SyncServer
        }
        else {
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

        $SyncedServer = Push-RemoteAdSync -ComputerName $ServerNamesInQueryOrder @PushParams
        if (-not $SyncedServer) {
            $Msg = 'No adsync server was found or sync could not be pushed on any server.'
            Write-IRT $Msg -Level Error
            return
        }
        $Global:IRT_AdSyncServer = $SyncedServer
    }
}
