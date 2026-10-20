function Push-RemoteAdSync {
    <#
    .SYNOPSIS
    Pushes a delta sync on the first of the given servers that runs the ADSync service.

    .DESCRIPTION
    Internal helper for Push-IRTAdSync. Checks the servers in parallel using a runspace
    pool (opening a PSSession and looking for the ADSync service) and invokes
    Start-ADSyncSyncCycle on the first server to report the service. Each check is
    handled as soon as it finishes, so slow or unreachable servers don't delay the push,
    and checks still running afterward are stopped. Session and service check errors are
    reported per server.

    Names are cut to the host name, and blank names are skipped. Every PSSession in this
    session is closed before and after.

    Uses no PSFramework, like the other on-prem AD functions, so it still works when
    Copy-IRTFunction pastes it onto a server without that module.

    .PARAMETER ComputerName
    The servers to check, in the order the checks are started.

    .PARAMETER Credential
    The credentials used to open the PSSessions, usually a domain admin.

    .PARAMETER ThrottleLimit
    Maximum number of servers checked at once. Default: 20.

    .EXAMPLE
    ```powershell
    Push-RemoteAdSync -ComputerName 'dc01', 'sync01' -Credential (Get-Credential)
    ```
    Pushes a sync on whichever of dc01 and sync01 runs the ADSync service.

    .OUTPUTS
    System.String. The host name of the server that synced, or nothing when no server
    synced.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string[]] $ComputerName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential] $Credential,

        [ValidateRange(1, 50)]
        [int] $ThrottleLimit = 20
    )

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
    $SyncedServer = $null

    try {
        foreach ($Server in $ComputerName) {
            $Server = ($Server -split '\.')[0]
            if ([string]::IsNullOrWhiteSpace($Server)) { continue }

            $PS = [System.Management.Automation.PowerShell]::Create()
            $PS.RunspacePool = $Pool
            $null = $PS.AddScript($DiscoveryScriptBlock)
            $null = $PS.AddArgument($Server).AddArgument($Credential)
            $RSEntry = @{
                ComputerName = $Server
                PS           = $PS
                Handle       = $PS.BeginInvoke()
            }
            $Runspaces.Add($RSEntry)
        }

        $Total = $Runspaces.Count
        $Done = 0
        $Pending = [System.Collections.Generic.List[hashtable]]::new($Runspaces)

        # handle each check as soon as it finishes, so a slow or unreachable server
        # never delays the push; checks still running after a push are stopped in finally
        while ($Pending.Count -gt 0 -and -not $SyncedServer) {

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
                        $SyncedServer = $CN
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

                if ($SyncedServer) { break }
            }
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

    if ($SyncedServer) { $SyncedServer }
}
