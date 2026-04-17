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

        # ensure global caches exist before runspaces start so they all share the same reference
        if ($Global:IRT_IpInfo -isnot [hashtable]) {
            $Global:IRT_IpInfo = [hashtable]::Synchronized(@{})
        }
        if ($Global:IRT_MessageTraceTable -isnot [hashtable]) {
            $Global:IRT_MessageTraceTable = [hashtable]::Synchronized(@{})
        }
        if ($Global:IRT_WaitFlags -isnot [hashtable]) {
            $Global:IRT_WaitFlags = [hashtable]::Synchronized(@{
                MessageTraceUserDone     = $false
                MessageTraceAllUsersDone = $false
            })
        }

        # pre-populate caches in main thread
        Request-DirectoryRoles -Return 'none'
        Request-DirectoryRoleTemplates -Return 'none'
        Request-GraphGroups -Return 'none'
        Request-GraphOauth2Grants -Return 'none'
        Request-GraphUsers -Return 'none'
        Request-GraphServicePrincipals -Return 'none'
        $null = ConvertTo-HumanErrorDescription -ErrorCode 0  # trigger lazy-load of error table

        # pack references for injection into child runspace globals
        $SharedRefs = @{
            IRT_IpInfo                     = $Global:IRT_IpInfo
            IRT_MessageTraceTable          = $Global:IRT_MessageTraceTable
            IRT_WaitFlags                  = $Global:IRT_WaitFlags
            IRT_DirectoryRoles             = $Global:IRT_DirectoryRoles
            IRT_DirectoryRolesById         = $Global:IRT_DirectoryRolesById
            IRT_DirectoryRoleTemplates     = $Global:IRT_DirectoryRoleTemplates
            IRT_DirectoryRoleTemplatesById = $Global:IRT_DirectoryRoleTemplatesById
            IRT_Groups                     = $Global:IRT_Groups
            IRT_GroupsById                 = $Global:IRT_GroupsById
            IRT_Oauth2Grants               = $Global:IRT_Oauth2Grants
            IRT_Oauth2GrantsByClientId     = $Global:IRT_Oauth2GrantsByClientId
            IRT_Users                      = $Global:IRT_Users
            IRT_UsersById                  = $Global:IRT_UsersById
            IRT_ServicePrincipals          = $Global:IRT_ServicePrincipals
            IRT_ServicePrincipalsByAppId   = $Global:IRT_ServicePrincipalsByAppId
            IRT_ServicePrincipalsById      = $Global:IRT_ServicePrincipalsById
            IRT_EntraErrorTable            = $Global:IRT_EntraErrorTable
            IRT_Session                    = $Global:IRT_Session
            IRT_UserObjects                = $ScriptUserObjects
        }

        #region playbook steps
        $Steps = @(

            @{  Name   = 'Get-LicenseReport'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-LicenseReport
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-UserInfo'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Show-UserInfo
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-UserApplications'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-UserApplications -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-Mailbox'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Show-Mailbox -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-AdminRoles'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-AdminRoles -Excel -Highlight $Global:IRT_UserObjects.UserPrincipalName -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Find-RiskyApplications'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Find-RiskyApplications -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Show-UserMFA'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Show-UserMFA
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTMessageTrace'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $Params = @{
                        UserObjects = $Global:IRT_UserObjects
                        Days = 90
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTInboxRules'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    Get-IRTInboxRules
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-EntraAuditLogs'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-EntraAuditLogs -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-SignInLogs'
                Script = { 
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-SignInLogs
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-UALogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $Global:IRT_UserObjects
                        WaitOnMessageTrace = $true
                        Cached = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'UALRiskyOperations'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $Global:IRT_UserObjects
                        RiskyOperations = $true
                        Days = 180
                        Cached = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'UALSignInLogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                        ShowBanner = $false
                    }
                    Connect-ExchangeOnline @ConnectParams
                    $UAParams = @{
                        UserObjects = $Global:IRT_UserObjects
                        SignInLogs = $true
                        Cached = $true
                    }
                    Get-UALogs @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-NonInteractiveLogs'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-NonInteractiveLogs
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-IRTMessageTrace -AllUsers'
                Script = {
                    param( 
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    $ConnectParams = @{
                        AccessToken = $Global:IRT_Session.Exchange.Token
                        UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
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
                    $SharedRefs
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
                    'M365IncidentResponseTools',
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