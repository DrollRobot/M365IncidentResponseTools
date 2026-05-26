function Open-MailboxInOWA {
    <#
	.SYNOPSIS
	Opens user mailbox in OWA in a browser.

	.NOTES
	Version: 1.1.0
    1.1.0 - Added Clipboard option.
	#>
    [Alias('OpenMailbox')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [ValidateSet( 'msedge','chrome','firefox','brave','default' )]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $ToClipboard
    )

    begin {
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
            $null = Get-AcceptedDomain
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

        foreach ($ScriptUserObject in $ScriptUserObjects) {
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # verify user has mailbox
            try { $Mailbox = Get-EXOMailbox -UserPrincipalName $UserEmail -ErrorAction Stop }
            catch { $Mailbox = $null }
            if (-not $Mailbox) {
                Write-IRT "No mailbox for ${UserEmail}" -Level Warn
                continue
            }

            $OwaHost = if ($Global:IRT_Session.Environment -in @('GCC High', 'DoD', 'USGov')) {
                'outlook.office365.us'
            } else {
                'outlook.office.com'
            }
            $OWAUrl = "https://${OwaHost}/mail/${UserEmail}/?offline=disabled"

            [pscustomobject]@{
                OWAUrl = $OWAUrl
            }

            if (-not $ToClipboard) {
                $Params = @{
                    Browser = $Browser
                    Url = $OWAUrl
                }
                if ($Private) {
                    $Params['Private'] = $true
                }
                Open-Browser @Params
            }
        }

        if ($ToClipboard -and ($ScriptUserObjects | Measure-Object).Count -eq 1) {
            Set-Clipboard -Value $OWAUrl
            Write-IRT "OWA URL copied to clipboard."
        }
    }
}


