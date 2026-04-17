function Connect-IRTExchange {
    <#
    .SYNOPSIS
    Connects to Exchange Online.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER UserPrincipalName
    Optional. The UserPrincipalName (Email) for the user account. When provided
    with -AccessToken (e.g. in runspace re-connections), this value is passed to
    Connect-ExchangeOnline. For interactive flows the UPN is derived from the
    MSAL token result automatically.

    .PARAMETER GCCHigh
    Connect to a GCC High tenant environment.

    .PARAMETER DeviceCode
    Use device code authentication flow. An access token is acquired using
    the Microsoft.Identity.Client assembly (loaded by Microsoft.Graph.Authentication)
    and returned for storage by the caller.

    .PARAMETER AccessToken
    A pre-existing access token to use for connection. Intended for use within
    runspaces where interactive authentication is not possible.

    .PARAMETER Browser
    Browser to use for device code login. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .NOTES
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [string] $TenantId,
        [string] $UserPrincipalName,
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [string] $AccessToken,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = 'default',
        [switch] $Private,

        [switch] $Force
    )

    process {

        # --- Exchange Online ---
        # Check connection state up front so we can skip unnecessary token acquisition
        # and avoid prompting the user when Exchange is already connected.
        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {$_.State -eq 'Connected' -and $_.TenantID -eq $TenantId}

        # Step 1: ensure we have a token for this tenant
        if ($AccessToken) {
            # caller provided a token directly — use it and skip acquisition
            $ExchangeToken = [pscustomobject]@{
                Token             = $AccessToken
                UserPrincipalName = $UserPrincipalName
                TenantId          = $TenantId
            }

        } elseif (
            $Global:IRT_Session -and 
            $Global:IRT_Session.Exchange -and 
            $Global:IRT_Session.TenantId -eq $TenantId -and
            -not $Force -and 
            -not (Test-TokenExpired -Token $Global:IRT_Session.Exchange.Token) 
        ) {
            $ExchangeToken = $Global:IRT_Session.Exchange

            if ( $ExistingConnection ) {
                Write-Host "Already connected to Exchange Online for tenant $TenantId." -ForegroundColor Yellow
                return $ExchangeToken
            }

        } else {
            # Clear stale cached state before re-acquiring
            if ( $Global:IRT_Session -and $Global:IRT_Session.Exchange ) {
                if ( Test-TokenExpired -Token $Global:IRT_Session.Exchange.Token ) {
                    Write-Verbose 'Exchange token expired, re-authenticating.'
                } elseif ($Force) {
                    Write-Verbose '-Force specified, re-acquiring Exchange token.'
                }
                $Global:IRT_Session.Exchange = $null
            }
            # Disconnect before re-acquiring to avoid stale connection state
            if ( $ExistingConnection ) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                $ExistingConnection = $null
            }

            # Acquire a portable Exchange token via MSAL (interactive or device code)

            $ExchangeScope = 'https://outlook.office365.com/.default'
            $Authority     = "https://login.microsoftonline.com/$TenantId"
            if ($GCCHigh) {
                $ExchangeScope = 'https://outlook.office365.us/.default'
                $Authority     = "https://login.microsoftonline.us/$TenantId"
            }

            # Ensure the MSAL assembly is loaded from Microsoft.Graph.Authentication.
            # Graph is always connected first by Connect-IncidentResponseTools, so the
            # module should already be imported.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            if (-not $GraphModule) {
                throw 'Microsoft.Graph.Authentication must be imported before acquiring an Exchange token.'
            }
            $MsalDll = Join-Path $GraphModule.ModuleBase 'Dependencies' 'Core' 'Microsoft.Identity.Client.dll'

            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }) ) {
                Add-Type -Path $MsalDll
            }

            # Build a public client application using EXO's well-known first-party app ID.
            # This is a Microsoft-owned app pre-consented for Exchange — no app registration needed.
            $ExoClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'

            # Reuse the cached MSAL app instance to preserve its token cache (which holds the refresh token)
            if ( $Global:IRT_Session -and $Global:IRT_Session.Exchange -and $Global:IRT_Session.Exchange.PublicClientApplication -and $Global:IRT_Session.TenantId -eq $TenantId ) {
                $App = $Global:IRT_Session.Exchange.PublicClientApplication
            } else {
                $App = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ExoClientId).
                    WithAuthority($Authority).
                    WithRedirectUri('http://localhost').
                    Build()
            }

            $Scopes = [string[]]@($ExchangeScope)

            # Try silent refresh first using MSAL's cached refresh token before prompting the user
            $TokenResult = $null
            $CachedAccounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
            if ($CachedAccounts) {
                $CachedAccount = $CachedAccounts | Select-Object -First 1
                try {
                    $TokenResult = $App.AcquireTokenSilent($Scopes, $CachedAccount).ExecuteAsync().GetAwaiter().GetResult()
                    Write-Verbose 'Exchange token silently refreshed.'
                } catch {
                    Write-Verbose "Silent Exchange token refresh failed, falling back to interactive: $_"
                    $TokenResult = $null
                }
            }

            if ($TokenResult) {
                # Token acquired via silent refresh — no additional steps needed
            } elseif ($DeviceCode) {
                # --- Device code flow ---
                # PS-based delegates still require a runspace and will silently fail when
                # MSAL calls them on a .NET thread pool thread.  Compile a tiny C# helper
                # whose Callback is a pure .NET lambda so it can run on any thread.
                # We use Func<object,Task> (no MSAL reference) so we can skip
                # -ReferencedAssemblies and keep the default BCL refs. Contravariance
                # on Func<in T, out TResult> lets Func<object,Task> satisfy
                # MSAL's Func<DeviceCodeResult,Task> parameter.
                if (-not ([System.Management.Automation.PSTypeName]'IRT.DeviceCodeHelper').Type) {
                    Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Threading.Tasks;
namespace IRT {
    public sealed class DeviceCodeHelper {
        private object _result;
        private readonly SemaphoreSlim _signal = new SemaphoreSlim(0, 1);
        public Func<object, Task> Callback { get; }
        public DeviceCodeHelper() {
            Callback = result => { _result = result; _signal.Release(); return Task.CompletedTask; };
        }
        public object WaitForResult(int timeoutMs) {
            return _signal.Wait(timeoutMs) ? _result : null;
        }
    }
}
'@
                }

                $Helper    = [IRT.DeviceCodeHelper]::new()
                $TokenTask = $App.AcquireTokenWithDeviceCode($Scopes, $Helper.Callback).ExecuteAsync()

                # Block the PS thread until MSAL fires the device-code callback.
                $CodeResult = $Helper.WaitForResult(30000)
                if ($null -eq $CodeResult) {
                    throw 'Timed out waiting for device code response from MSAL.'
                }

                # All PS work happens here on the main runspace thread.
                if ($CodeResult.Message -match 'enter the code\s+(\S+)') {
                    $Matches[1] | Set-Clipboard
                    Write-Host "Device code '$( $Matches[1] )' copied to clipboard." -ForegroundColor Green
                    Open-Browser -Browser $Browser -Url $CodeResult.VerificationUrl -Private:$Private
                } else {
                    Write-Host $CodeResult.Message
                }

                try {
                    $TokenResult = $TokenTask.GetAwaiter().GetResult()
                } catch {
                    throw "Device code token acquisition failed: $_"
                }
            } else {
                # --- Interactive browser flow ---
                try {
                    $TokenResult = $App.AcquireTokenInteractive($Scopes).
                        ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    throw "Interactive token acquisition failed: $_"
                }
            }

            $Token = $TokenResult.AccessToken

            if (-not $Token) {
                throw 'Failed to acquire Exchange access token.'
            }

            $ExchangeToken = [pscustomobject]@{
                Token                   = $Token
                UserPrincipalName       = $TokenResult.Account.Username
                TenantId                = $TenantId
                PublicClientApplication = $App
            }
        }

        # Step 2: connect only if not already connected to this tenant
        if ($ExistingConnection) {
            Write-Host "Already connected to Exchange Online for tenant $TenantId." -ForegroundColor Yellow
            return $ExchangeToken
        }

        # Step 3: connect
        if ($ExchangeToken) {
            $ConnectParams = @{
                AccessToken       = $ExchangeToken.Token
                UserPrincipalName = $ExchangeToken.UserPrincipalName
                ShowBanner        = $false
            }
        } else {
            $ConnectParams = @{
                ShowBanner        = $false
                DisableWAM        = $true
            }
        }

        if ($GCCHigh) {
            $ConnectParams['ExchangeEnvironmentName'] = 'O365USGovGCCHigh'
        }

        Connect-ExchangeOnline @ConnectParams

        return $ExchangeToken
    }
}