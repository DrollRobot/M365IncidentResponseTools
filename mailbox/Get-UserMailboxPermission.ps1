function Get-UserMailboxPermission {
    [CmdletBinding( DefaultParameterSetName = 'UserObject' )]
    param(
        [Parameter(ParameterSetName = 'UserObject', Position = 0)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'UserEmail')]
        [Alias('UserEmails', 'UserPrincipalName')]
        [string[]] $UserEmail,

        # Skip the tenant query and reuse $Global:IRTMailboxPermissionsTable from a previous run
        [switch] $Cached
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        switch ($ParameterSet) {
            'UserObject' {
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObject
                } else {
                    $ScriptUserObjects = Get-IRTUserObject
                    if (-not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0) {
                        $Msg = 'No user objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                }
            }
            'UserEmail' {
                $ScriptUserObjects = foreach ($Email in $UserEmail) {
                    [pscustomobject]@{UserPrincipalName = $Email}
                }
            }
        }
    }

    process {
        # -- Step 1: build or reuse the global permissions table --------------
        if ($Cached -and $Global:IRT_MailboxPermissionTable) {
            Write-IRT "Using cached data."
            $PermissionsTable = $Global:IRT_MailboxPermissionTable
        } else {
            $EXOParams = @{
                ResultSize = 'Unlimited'
                Properties = 'Identity', 'Name', 'PrimarySmtpAddress'
            }
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Get-EXOMailbox $Elapsed"
            $Mailboxes = Get-EXOMailbox @EXOParams
            $Total     = $Mailboxes.Count
            $Index     = 0
            $PermissionsTable = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            foreach ($Mailbox in $Mailboxes) {
                $Index++
                $Elapsed       = $Stopwatch.Elapsed
                $EstTotal      = [timespan]::FromSeconds($Elapsed.TotalSeconds / $Index * $Total)
                $Remaining     = $EstTotal - $Elapsed
                $TimeRemaining = "{0:hh\:mm\:ss}" -f $Remaining

                $ProgressParams = @{
                    Activity        = "Building mailbox permissions table."
                    Status          = "Processing $($Mailbox.Name) [$Index of $Total]" +
                        " - Est. remaining: $TimeRemaining"
                    PercentComplete = ($Index / $Total * 100)
                }
                Write-Progress @ProgressParams

                try {
                    $PermParams = @{
                        Identity    = $Mailbox.Identity
                        ErrorAction = 'Stop'
                    }
                    $Permissions = Get-EXOMailboxPermission @PermParams
                    foreach ($Permission in $Permissions) {
                        $UserKey = $Permission.User.ToString()
                        if (-not $PermissionsTable.ContainsKey($UserKey)) {
                            $NewList = [System.Collections.Generic.List[psobject]]::new()
                            $PermissionsTable[$UserKey] = $NewList
                        }
                        $PermissionsTable[$UserKey].Add([pscustomobject]@{
                            MailboxName        = $Mailbox.Name
                            MailboxIdentity    = $Mailbox.Identity
                            PrimarySmtpAddress = $Mailbox.PrimarySmtpAddress
                            AccessRights       = $Permission.AccessRights -join ', '
                        })
                    }
                } catch {}
            }

            Write-Progress -Activity "Building mailbox permissions table." -Completed

            # Cache for subsequent -Cached calls
            $Global:IRT_MailboxPermissionTable = $PermissionsTable
            Write-IRT "Permissions table cached in `$Global:IRT_MailboxPermissionTable."
        }

        # -- Step 2: look up each user in the table and display results --------
        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $TargetUpn = $ScriptUserObject.UserPrincipalName
            $Entries   = $PermissionsTable[$TargetUpn]

            Write-IRT "Mailboxes ${TargetUpn} has permissions on:"
            if (($Entries | Measure-Object).Count -eq 0) {
                Write-IRT "None"
            } else {
                $Entries | Select-Object MailboxName, PrimarySmtpAddress, AccessRights
            }
        }
    }
}
