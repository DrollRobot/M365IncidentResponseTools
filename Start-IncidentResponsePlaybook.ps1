New-Alias -Name 'Playbook' -Value 'Start-IncidentResponsePlaybook' -Force
function Start-IncidentResponsePlaybook {
    <#
	.SYNOPSIS
    Runs multiple functions to assist in investigating a user's activity.
    
	.NOTES
	Version: 2.2.0
    2.2.0 - Added license report, added error handling to close runspaces when script exits.
    2.1.0 - Added ability to run parallel exchange runspaces using exchange access token.
    2.0.0 - Added ability to run mulitple operations in parallel using runspaces.
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,
        
        [string] $Ticket,
        [switch] $NoFolder,
        [int] $MaxRunspaces = 15,
        [switch] $Test
    )

    begin {

        #region BEGIN

        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        # if users passed via script argument:
        if (($UserObjects | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObjects
        }
        # if not, look for global objects
        else {
            
            # get from global variables
            $ScriptUserObjects = Get-IRTUserObjects
            
            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "No -UserObjects argument used, no `$Global:IRT_UserObjects present."
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        # verify connected to graph
        if (-not (Get-MgContext)) {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Graph. Run Connect-MgGraph."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # verify connected to exchange
        try {
            [void](Get-AcceptedDomain)
        }
        catch {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        } 
    }

    process {

        if (-not $NoFolder) {
            
            # make directory
            $DirParams = @{
                UserObjects = $ScriptUserObjects
            }
            if ( $Ticket ) {
                $DirParams['Ticket'] = $Ticket
            }
            else {
                $DirParams['Confirm'] = $true
            }
            New-InvestigationFolder @DirParams
        }

        $WorkingPath = Get-Location

        #region playbook steps
        $Steps = @(

            @{  Name   = 'Get-LicenseReport'
                Script = {
                    param( 
                        $WorkingPath
                    )
                    Set-Location -Path $WorkingPath
                    Get-LicenseReport
                }
                Args  = @(
                    $WorkingPath
                )
            }

            @{  Name   = 'Show-UserInfo'
                Script = {
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Show-UserInfo -UserObjects $RunspaceUserObjects 
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-UserApplications'
                Script = {
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Get-UserApplications -UserObjects $RunspaceUserObjects 
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Show-Mailbox'
                Script = {
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Show-Mailbox -UserObjects $RunspaceUserObjects 
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-AdminRoles'
                Script = { 
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Get-AdminRoles -Excel -Highlight $RunspaceUserObjects.UserPrincipalName
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Find-RiskyApplications'
                Script = { 
                    param( 
                        $WorkingPath
                    )
                    Set-Location -Path $WorkingPath
                    Find-RiskyApplications
                }
                Args  = @(
                    $WorkingPath
                )
            }

            @{  Name   = 'Show-UserMFA'
                Script = { 
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Show-UserMFA -UserObjects $RunspaceUserObjects
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-IRTMessageTrace'
                Script = { 
                    param( 
                        $WorkingPath,
                        $Exchange,
                        $RunspaceUserObjects
                    )
                    # set working path
                    Set-Location -Path $WorkingPath
                    # connect to exchange
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $Params = @{
                        UserObjects = $RunspaceUserObjects
                        Days = 90
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-IRTInboxRules'
                Script = { 
                    param( 
                        $WorkingPath,
                        $Exchange,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    Get-IRTInboxRules -UserObjects $RunspaceUserObjects
                }
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-EntraAuditLogs'
                Script = { 
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Get-EntraAuditLogs -UserObjects $RunspaceUserObjects
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-SignInLogs'
                Script = { 
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Get-SignInLogs -UserObjects $RunspaceUserObjects
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-UALogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $Exchange,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $RunspaceUserObjects
                        WaitOnMessageTrace = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'UALRiskyOperations'
                Script = {
                    param( 
                        $WorkingPath,
                        $Exchange,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $RunspaceUserObjects
                        RiskyOperations = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'UALSignInLogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $Exchange,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $RunspaceUserObjects
                        SignInLogs = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-NonInteractiveLogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $RunspaceUserObjects
                    )
                    Set-Location -Path $WorkingPath
                    Get-NonInteractiveLogs -UserObjects $RunspaceUserObjects
                }
                Args  = @(
                    $WorkingPath,
                    $ScriptUserObjects
                )
            }

            @{  Name   = 'Get-IRTMessageTrace -AllUsers'
                Script = {
                    param( 
                        $WorkingPath,
                        $Exchange
                    )
                    # set path
                    Set-Location -Path $WorkingPath
                    # connect to exchange
                    $ConnectParams = @{
                        AccessToken = $Exchange.Token
                        UserPrincipalName = $Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $Params = @{
                        AllUsers = $true
                        Days = 2
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                } 
                Args  = @(
                    $WorkingPath,
                    $Global:IRT_Session.Exchange
                )
            }
        )

        #region open runspaces
        try {

            $Global:IRT_Playbook_JobList = @()
            $Global:IRT_Playbook_RunspacePool = $null

            ### build a runspace pool
            $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $InitialSessionState.ImportPSModule(
                    'ExchangeOnlineManagement',
                    'IncidentResponseTools',
                    'Microsoft.Graph.Authentication',
                    'Microsoft.Graph.Applications',
                    'Microsoft.Graph.Beta.Reports',
                    'Microsoft.Graph.Users'
                )
            $Global:IRT_Playbook_RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxRunspaces, $InitialSessionState, $Host)
            $Global:IRT_Playbook_RunspacePool.Open()

            ### queue tasks
            $Global:IRT_Playbook_JobList = foreach ($Step in $Steps) {

                $PowerShell = [PowerShell]::Create()
                $PowerShell.RunspacePool = $Global:IRT_Playbook_RunspacePool

                $null = $PowerShell.AddScript($Step.Script)
                foreach ($Arg in $Step.Args) {
                    $null = $PowerShell.AddArgument($Arg) 
                }

                # loop output
                [pscustomobject]@{
                    Name       = $Step.Name
                    PowerShell = $PowerShell
                    Handle     = $PowerShell.BeginInvoke()
                    Completed  = $false
                }
            }

            #region wait on runspaces
            while ($Global:IRT_Playbook_JobList.Completed -contains $false) {
                foreach ($Job in $Global:IRT_Playbook_JobList) {
                    if ( -not $Job.Completed -and $Job.Handle.IsCompleted ) {
                        try {
                            $Job.PowerShell.EndInvoke( $Job.Handle )

                            # output errors, if any
                            if ( $Job.PowerShell.Streams.Error.Count -gt 0 ) {
                                Write-Warning "Errors:"
                                $Job.PowerShell.Streams.Error | ForEach-Object {
                                    Write-Warning $_.ToString()
                                }
                            }
                        }
                        catch {
                            Write-Warning "$($Job.Name) error: $_"
                        }
                        finally {
                            $Job.PowerShell.Dispose()
                            $Job.Completed = $true
                        }
                    }
                }

                $TotalJobs      = $Global:IRT_Playbook_JobList.Count
                $CompletedCount = ($Global:IRT_Playbook_JobList | Where-Object { $_.Completed }).Count
                $RemainingNames = $Global:IRT_Playbook_JobList | Where-Object { -not $_.Completed } | Select-Object -ExpandProperty Name
                $PercentComplete = [int](($CompletedCount / $TotalJobs) * 100)
                Write-Progress -Activity 'Playbook Running' -Status "Waiting on: $($RemainingNames -join ', ')" -PercentComplete $PercentComplete
                Start-Sleep -Seconds 10
            }
            Write-Progress -Activity 'Playbook Running' -Completed
        }
        #region cleanup
        finally {
            # stop all runspaces
            foreach ($Job in $Global:IRT_Playbook_JobList) {
                try   { $Job.PowerShell.Stop() } catch {}
                try   { $Job.PowerShell.Dispose() } catch {}
            }
            $Global:IRT_Playbook_JobList = @()

            # close pool
            if ($Global:IRT_Playbook_RunspacePool) {
                try { $Global:IRT_Playbook_RunspacePool.Close() }  catch {}
                try { $Global:IRT_Playbook_RunspacePool.Dispose() } catch {}
            }
            $Global:IRT_Playbook_RunspacePool = $null
        }

        if ($Stopwatch) {
            $Stopwatch.Stop()
            Write-Host "Playbook complete. Elapsed time: $($Stopwatch.Elapsed.ToString())"
        }
    }
}