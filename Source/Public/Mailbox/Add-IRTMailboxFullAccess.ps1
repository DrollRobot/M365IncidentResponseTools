function Add-IRTMailboxFullAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [Alias('FullAccess')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo,

        [switch] $Remove
    )

    begin {
        Update-IRTToken -Service 'Exchange'
        $GrantAccessToList = [System.Collections.Generic.List[string]]::new()

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
                Write-IRT "No user objects passed or found in global variables." -Level Error
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = 'No -UserObject argument used, ' +
                    'no $Global:IRT_UserObjects present.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
        }

        # verify connected to exchange
        try {
            $Domain = Get-AcceptedDomain
        }
        catch {}
        if ( -not $Domain ) {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
    }

    process {

        #region CURRENT USER

        if ($GrantAccessTo) {
            # normalise to list
            [void]$GrantAccessToList.Add($GrantAccessTo)
        }
        else {
            try {
                $Accounts = @((Get-ConnectionInformation).UserPrincipalName)
            }
            catch {
                $_
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "${Function}: Unable to detect currently connected Exchange" +
                    ' account. Specify with -GrantAccessTo.'
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }

            # if not empty, add to list
            foreach ($a in $Accounts) {
                if (-not [string]::IsNullOrWhiteSpace($a)) {
                    [void]$GrantAccessToList.Add($a)
                }
            }
        }

        if ($GrantAccessToList.Count -lt 1) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "${Function}: Unable to detect currently connected Exchange" +
                ' account. Specify with -GrantAccessTo.'
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
        elseif ($GrantAccessToList.Count -gt 1) {

            # remove duplicates
            $HashSet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Object in $GrantAccessToList) { [void]$HashSet.Add($Object) }
            $GrantAccessToList = @($HashSet)

            # if more than one option, have user choose
            if ( $GrantAccessToList.Count -gt 1 ) {
                $MenuParams = @{
                    Title = "Choose account to receive full access to mailbox."
                    Options = $GrantAccessToList
                    List = $true
                }
                $GrantAccessTo = Build-Menu @MenuParams
            }
            else {
                $GrantAccessTo = $GrantAccessToList | Select-Object -First 1
            }
        }
        else {
            $GrantAccessTo = $GrantAccessToList | Select-Object -First 1
        }

        #region USER LOOP

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            if ($Remove) {
                # remove access
                Write-IRT "Removing access to ${UserEmail} from ${GrantAccessTo}"
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    Confirm = $false
                }
                $null = Remove-MailboxPermission @Params
            }
            else {
                # add access
                Write-IRT "Adding access to ${UserEmail} to ${GrantAccessTo}"
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    InheritanceType = 'All'
                }
                $null = Add-MailboxPermission @Params
            }

            # show users who have access to target mailbox
            Write-IRT "Showing users who have access to ${UserEmail}"
            $Properties = @(
                'User'
                'AccessRights'
                'IsInherited'
                'InheritanceType'
            )
            $MailboxPermissions = Get-MailboxPermission -Identity $UserEmail
            $MailboxPermissions | Format-Table $Properties -AutoSize
        }
    }
}