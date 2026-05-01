New-Alias -Name 'Playbook' -Value 'Start-IncidentResponsePlaybook' 
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
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $Ticket,
        [switch] $NoFolder,
        [int] $MaxRunspaces = 15,
        [switch] $Test
    )

    begin {

        #region BEGIN

        # constants
        $Red = @{ForegroundColor = 'Red'}

        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        # if users passed via script argument:
        if (($UserObject | Measure-Object).Count -gt 0) {
            $ScriptUserObjects = $UserObject
        }
        # if not, look for global objects
        else {

            # get from global variables
            $ScriptUserObjects = Get-IRTUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "No -UserObject argument used, no `$Global:IRT_UserObjects present."
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
    }

    process {

        if (-not $NoFolder) {

            # make directory
            $DirParams = @{
                UserObject = $ScriptUserObjects
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
        Request-DirectoryRole -Return 'none'
        Request-DirectoryRoleTemplate -Return 'none'
        Request-GraphGroup -Return 'none'
        Request-GraphOauth2Grant -Return 'none'
        Request-GraphUser -Return 'none'
        Request-GraphServicePrincipal -Return 'none'
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

        # build Exchange connection params once for all runspaces
        $ExoConnectParams = @{
            AccessToken       = $Global:IRT_Session.Exchange.Token
            UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
            ShowBanner        = $false
        }
        if ($Global:IRT_Session.GCCHigh) {
            $ExoConnectParams['ExchangeEnvironmentName'] = 'O365USGovGCCHigh'
        }

        #region playbook steps

        $Steps = @(

            @{  Name   = 'Get-LicenseReport' # FIXME not included in module?
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

            @{  Name   = 'Get-UserApplication'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-UserApplication -Cached
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

            @{  Name   = 'Get-AdminRole'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-AdminRole -Excel -Highlight $Global:IRT_UserObjects.UserPrincipalName -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Find-RiskyApplication'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Find-RiskyApplication -Cached
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
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        UserObject = $Global:IRT_UserObjects
                        Days = 90
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-IRTInboxRule'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    Get-IRTInboxRule
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-EntraAuditLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-EntraAuditLog -Cached
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-SignInLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-SignInLog
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs
                )
            }

            @{  Name   = 'Get-UALog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        WaitOnMessageTrace = $true
                        Cached = $true
                    }
                    Get-UALog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'UALRiskyOperations'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        RiskyOperations = $true
                        Days = 180
                        Cached = $true
                    }
                    Get-UALog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'UALSignInLogs'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        SignInLogs = $true
                        Cached = $true
                    }
                    Get-UALog @UAParams
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
                )
            }

            @{  Name   = 'Get-NonInteractiveLog'
                Script = {
                    param(
                        $WorkingPath,
                        $SharedRefs
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Get-NonInteractiveLog
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
                        $SharedRefs,
                        $ExoConnectParams
                    )
                    foreach ($k in $SharedRefs.Keys) { Set-Variable -Scope Global -Name $k -Value $SharedRefs[$k] }
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        AllUsers = $true
                        Days = 2
                        Quiet = $true
                    }
                    Get-IRTMessageTrace @Params
                }
                Args  = @(
                    $WorkingPath,
                    $SharedRefs,
                    $ExoConnectParams
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
                                Write-Host @Red "$($Job.Name) Errors:"
                                $Job.PowerShell.Streams.Error | ForEach-Object {
                                    Write-Error $_
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