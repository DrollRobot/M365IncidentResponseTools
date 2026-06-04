function Start-IRTPlaybook {
    <#
    .SYNOPSIS
    Runs multiple functions to assist in investigating a user's activity.

    .DESCRIPTION
    The incident response playbook is the primary investigation entry point.
    It accepts one or more Entra ID user objects and launches ~15 investigation steps in
    parallel, then saves output files to the investigation folder.

    Steps include: license report, user info, app assignments, mailbox details, admin roles,
    risky applications, MFA state, message trace, inbox rules, Entra audit log, sign-in logs,
    non-interactive sign-in logs, and Unified Audit Log (UAL).

    If -UserObject is omitted the function falls back to $Global:IRT_UserObjects populated
    by Find-User.

    .PARAMETER UserObject
    One or more Entra ID user objects to investigate. Accepts the objects returned by
    Find-GraphUser or Get-GlobalUserObject. Falls back to global session objects if omitted.

    .PARAMETER Ticket
    Ticket or case number string. Used to name the investigation folder when -NoFolder is
    not specified.

    .PARAMETER NoFolder
    Skip creating an investigation output folder. Results are still displayed in the console
    but not written to disk.

    .PARAMETER MaxRunspaces
    Maximum number of parallel runspaces. Default: 15. Reduce if the host machine has
    limited memory or Graph throttling is a concern.

    .EXAMPLE
    Find-GraphUser 'jsmith@contoso.com'
    Start-IRTPlaybook
    Look up a user, then run the full playbook using the global user object.

    .EXAMPLE
    Start-IRTPlaybook -UserObject $User -Ticket 'INC-1234'
    Run the playbook for an already-resolved user object and name the output folder INC-1234.

    .EXAMPLE
    Start-IRTPlaybook -UserObject $User -NoFolder -MaxRunspaces 5
    Run without writing files, using a limited runspace pool.

    .OUTPUTS
    None. All output is written to the investigation folder or displayed in the console.

    .NOTES
    #>
    [Alias('Playbook')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $Ticket,
        [switch] $NoFolder,
        [int] $MaxRunspaces = 15
    )

    begin {

        #region BEGIN


        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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
                $ErrMsg = 'No -UserObject argument used, no $Global:IRT_UserObjects present.'
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = $ErrMsg
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

        $Target = $ScriptUserObjects[0].UserPrincipalName
        if (-not $PSCmdlet.ShouldProcess($Target, 'Start incident response playbook')) {
            return
        }

        if (-not $NoFolder) {

            # make directory
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: New-IRTInvestigationFolder [$Elapsed]")
            $DirParams = @{
                UserObject = $ScriptUserObjects
            }
            if ( $Ticket ) {
                $DirParams['Ticket'] = $Ticket
            }
            else {
                $DirParams['Confirm'] = $true
            }
            New-IRTInvestigationFolder @DirParams
        }

        if ($Global:IRT_Config.PlaybookOpenNewTab) {
            Open-IRTTab
        }

        # pre-populate caches in main thread
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Request-DirectoryRole [$Elapsed]"
        Request-DirectoryRole -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Request-DirectoryRoleTemplate [$Elapsed]")
        Request-DirectoryRoleTemplate -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Request-GraphGroup [$Elapsed]"
        Request-GraphGroup -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Request-GraphOauth2Grant [$Elapsed]"
        Request-GraphOauth2Grant -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Request-GraphUser [$Elapsed]"
        Request-GraphUser -Return 'none'
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Request-GraphServicePrincipal [$Elapsed]")
        Request-GraphServicePrincipal -Return 'none'

        #region PLAYBOOK STEPS

        # Each step relies on the shared references injected into the runspace globals
        # (see the InitialSessionState setup below): $IRT_PlaybookWorkingPath and
        # $IRT_PlaybookExoConnectParams plus the IRT_* caches. No per-step arguments.
        $Steps = @(

            @{  Name   = 'Get-IRTLicenseReport'
                Script = {
                    Set-Location -Path $WorkingPath
                    Get-IRTLicenseReport
                }
            }

            @{  Name   = 'Show-IRTUser'
                Script = {
                    Set-Location -Path $WorkingPath
                    Show-IRTUser
                }
            }

            @{  Name   = 'Get-IRTUserServicePrincipal'
                Script = {
                    Set-Location -Path $WorkingPath
                    Get-IRTUserServicePrincipal -Cached
                }
            }

            @{  Name   = 'Show-IRTMailbox'
                Script = {
                    Set-Location -Path $WorkingPath
                    Show-IRTMailbox -Cached
                }
            }

            @{  Name   = 'Get-IRTAdminRole'
                Script = {
                    Set-Location -Path $WorkingPath
                    $AdminParams = @{
                        Excel     = $true
                        Highlight = $Global:IRT_UserObjects.UserPrincipalName
                        Cached    = $true
                    }
                    Get-IRTAdminRole @AdminParams
                }
            }

            @{  Name   = 'Find-IRTRiskyServicePrincipal'
                Script = {
                    Set-Location -Path $WorkingPath
                    Find-IRTRiskyServicePrincipal -Cached
                }
            }

            @{  Name   = 'Show-IRTUserMfa'
                Script = {
                    Set-Location -Path $WorkingPath
                    Show-IRTUserMfa
                }
            }

            @{  Name   = 'Get-IRTMessageTrace'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        UserObject = $Global:IRT_UserObjects
                        Days       = 90
                        Quiet      = $true
                    }
                    Get-IRTMessageTrace @Params
                }
            }

            @{  Name   = 'Get-IRTInboxRule'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    Get-IRTInboxRule
                }
            }

            @{  Name   = 'Get-IRTEntraAuditLog'
                Script = {
                    Set-Location -Path $WorkingPath
                    Get-IRTEntraAuditLog -Cached
                }
            }

            @{  Name   = 'Get-IRTEntraSignInLog'
                Script = {
                    Set-Location -Path $WorkingPath
                    Get-IRTEntraSignInLog
                }
            }

            @{  Name   = 'Get-IRTUnifiedAuditLog'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject         = $Global:IRT_UserObjects
                        WaitOnMessageTrace = $true
                        Cached             = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
            }

            @{  Name   = 'UALRiskyOperations'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject      = $Global:IRT_UserObjects
                        RiskyOperations = $true
                        Days            = 180
                        Cached          = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
            }

            @{  Name   = 'UALSignInLogs'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $UAParams = @{
                        UserObject = $Global:IRT_UserObjects
                        SignInLogs = $true
                        Cached     = $true
                    }
                    Get-IRTUnifiedAuditLog @UAParams
                }
            }

            @{  Name   = 'Get-IRTNonInteractiveSignIn'
                Script = {
                    Set-Location -Path $WorkingPath
                    Get-IRTNonInteractiveSignIn
                }
            }

            @{  Name   = 'Get-IRTMessageTrace -AllUsers'
                Script = {
                    Set-Location -Path $WorkingPath
                    Connect-ExchangeOnline @ExoConnectParams
                    $Params = @{
                        AllUsers = $true
                        Days     = 10
                        Quiet    = $true
                    }
                    Get-IRTMessageTrace @Params
                }
            }
        )

        #region OPEN RUNSPACES

        try {

            $Global:IRT_Playbook_JobList = @()
            $Global:IRT_Playbook_RunspacePool = $null

            $WorkingPath = Get-Location

            # reset wait flags for this run (IRT_IpInfo and IRT_MessageTraceTable are
            # initialized as synchronized hashtables by the module and persist across runs)
            $Global:IRT_WaitFlags = [hashtable]::Synchronized(@{
                MessageTraceUserDone     = $false
                MessageTraceAllUsersDone = $false
            })

            # build Exchange connection params once for all runspaces
            $ExoConnectParams = @{
                AccessToken       = $Global:IRT_Session.Exchange.Token
                UserPrincipalName = $Global:IRT_Session.Exchange.UserPrincipalName
                ShowBanner        = $false
            }
            $ExoConnectParams['ExchangeEnvironmentName'] =
            $Global:IRT_Session.CloudConfig.ExchangeEnv

            # pack references for injection into child runspace globals. Keys become global
            # variable names inside each runspace.
            $SharedRefs = @{
                IRT_Banner                     = $Global:IRT_Banner
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
                IRT_UalOperationsData          = $Global:IRT_UalOperationsData
                IRT_UalUserTypeTable           = $Global:IRT_UalUserTypeTable
                IRT_TenantInfoTable            = $Global:IRT_TenantInfoTable
                IRT_Session                    = $Global:IRT_Session
                IRT_UserObjects                = $ScriptUserObjects
                ExoConnectParams               = $ExoConnectParams
                WorkingPath                    = $WorkingPath
            }

            ### build a runspace pool
            $IssType = [System.Management.Automation.Runspaces.InitialSessionState]
            $InitialSessionState = $IssType::CreateDefault()

            # Inject the shared references into each runspace global scope BEFORE the
            # modules are imported
            $SsveType =
            [System.Management.Automation.Runspaces.SessionStateVariableEntry]
            foreach ($Key in $SharedRefs.Keys) {
                $InitialSessionState.Variables.Add($SsveType::new($Key, $SharedRefs[$Key], ''))
            }

            # Seed the dependency-check flag too. Confirm-Dependencies.ps1
            # (ScriptsToProcess) reads it and skips its Get-Module -ListAvailable scan, so
            # the parallel runspaces don't each repeat the check the parent already pasbuised.
            $GvParams = @{
                Name        = 'IRT_DependenciesChecked'
                Scope       = 'Global'
                ValueOnly   = $true
                ErrorAction = 'SilentlyContinue'
            }
            $ParentDepsChecked = [bool](Get-Variable @GvParams)
            $InitialSessionState.Variables.Add(
                $SsveType::new('IRT_DependenciesChecked', $ParentDepsChecked, '')
            )

            $InitialSessionState.ImportPSModule(
                'ExchangeOnlineManagement',
                'M365IncidentResponseTools',
                'Microsoft.Graph.Authentication'
            )
            $Global:IRT_Playbook_RunspacePool = [RunspaceFactory]::CreateRunspacePool(
                1, $MaxRunspaces, $InitialSessionState, $Host
            )
            $Global:IRT_Playbook_RunspacePool.Open()

            ### queue tasks
            $Global:IRT_Playbook_JobList = foreach ($Step in $Steps) {

                $PowerShell = [PowerShell]::Create()
                $PowerShell.RunspacePool = $Global:IRT_Playbook_RunspacePool

                $null = $PowerShell.AddScript($Step.Script)

                # loop output
                [pscustomobject]@{
                    Name       = $Step.Name
                    PowerShell = $PowerShell
                    Handle     = $PowerShell.BeginInvoke()
                    Completed  = $false
                }
            }

            #region WAIT FOR RUNSPACES
            while ($Global:IRT_Playbook_JobList.Completed -contains $false) {
                foreach ($Job in $Global:IRT_Playbook_JobList) {
                    if ( -not $Job.Completed -and $Job.Handle.IsCompleted ) {
                        try {
                            $Job.PowerShell.EndInvoke( $Job.Handle )

                            # output errors, if any
                            foreach ($RunspaceError in $Job.PowerShell.Streams.Error) {
                                Write-IRT "$($Job.Name) error:" -Level Error
                                Write-Error -ErrorRecord $RunspaceError
                            }
                        }
                        catch {
                            Write-IRT "$($Job.Name): exception during EndInvoke" -Level Error
                            Write-Error -ErrorRecord $_
                        }
                        finally {
                            $Job.PowerShell.Dispose()
                            $Job.Completed = $true
                        }
                    }
                }

                $TotalJobs = $Global:IRT_Playbook_JobList.Count
                $CompletedJobs = $Global:IRT_Playbook_JobList | Where-Object { $_.Completed }
                $CompletedCount = $CompletedJobs.Count
                $RemainingNames = $Global:IRT_Playbook_JobList |
                    Where-Object { -not $_.Completed } |
                    Select-Object -ExpandProperty Name
                $PercentComplete = [int](($CompletedCount / $TotalJobs) * 100)
                $WpParams = @{
                    Activity        = 'Playbook Running'
                    Status          = "Waiting on: $($RemainingNames -join ', ')"
                    PercentComplete = $PercentComplete
                }
                Write-Progress @WpParams
                Start-Sleep -Seconds 10
            }
            Write-Progress -Activity 'Playbook Running' -Completed
        }

        #region CLEANUP

        finally {
            # stop all runspaces
            foreach ($Job in $Global:IRT_Playbook_JobList) {
                try { $Job.PowerShell.Stop() } catch {}
                try { $Job.PowerShell.Dispose() } catch {}
            }
            $Global:IRT_Playbook_JobList = @()

            # close pool
            if ($Global:IRT_Playbook_RunspacePool) {
                try { $Global:IRT_Playbook_RunspacePool.Close() }  catch {}
                try { $Global:IRT_Playbook_RunspacePool.Dispose() } catch {}
            }
            $Global:IRT_Playbook_RunspacePool = $null
        }

        $Stopwatch.Stop()
        $TotalElapsed = $Stopwatch.Elapsed.ToString()
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Playbook complete. Total elapsed: $TotalElapsed")
    }
}
