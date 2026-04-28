New-Alias -Name 'FullAccess' -Value 'Grant-MailboxFullAccess' -Force
function Grant-MailboxFullAccess {
    <#
	.SYNOPSIS
	Grants the currently logged in user full access to the target user's mailbox.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [string] $GrantAccessTo,

        [switch] $Remove
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name

        $GrantAccessToList = [System.Collections.Generic.List[string]]::new()

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }

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
                Write-Host @Red "${Function}: No user objects passed or found in global variables."
                return
            }
            if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "No -UserObject argument used, no `$Global:IRT_UserObjects present."
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
                    Message     = "${Function}: Unable to detect currently connected Exchange account. Specify with -GrantAccessTo."
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
                Message     = "${Function}: Unable to detect currently connected Exchange account. Specify with -GrantAccessTo."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
        elseif ($GrantAccessToList.Count -gt 1) {

            # remove duplicates
            $HashSet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Object in $GrantAccessToList) {[void]$HashSet.Add($Object)}
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
                Write-Host @Red "${Function}: No mailbox for ${UserEmail}"
                continue
            }

            if ($Remove) {
                # remove access
                Write-Host @Blue "Removing access to ${UserEmail} from ${GrantAccessTo}" | Out-Host
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    Confirm = $false
                }
                Remove-MailboxPermission @Params | Out-Null
            }
            else {
                # add access
                Write-Host @Blue "Adding access to ${UserEmail} to ${GrantAccessTo}" | Out-Host
                $Params = @{
                    Identity = $UserEmail
                    User = $GrantAccessTo
                    AccessRights = 'FullAccess'
                    InheritanceType = 'All'
                }
                Add-MailboxPermission @Params | Out-Null
            }

            # show users who have access to target mailbox
            Write-Host @Blue "Showing users who have access to ${UserEmail}" | Out-Host
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
