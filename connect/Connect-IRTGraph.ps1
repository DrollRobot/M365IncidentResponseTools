function Connect-IRTGraph {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph with default incident response scopes.

    .PARAMETER TenantId
    The TenantId GUID for the environment you want to connect to.

    .PARAMETER GCCHigh
    Connect to a GCC High tenant environment.

    .PARAMETER DeviceCode
    Use device code authentication flow. An access token is acquired using
    the Microsoft.Identity.Client assembly (loaded by Microsoft.Graph.Authentication)
    and returned for storage by the caller.

    .PARAMETER AdditionalScopes
    Additional Graph scopes to request beyond the default set.

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
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [string[]] $AdditionalScopes,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = 'default',
        [switch] $Private,

        [switch] $Force
    )

    process {

        $DefaultScopes = @(
            'Application.ReadWrite.All'
            'AuditLog.Read.All'
            'AuditLogsQuery.Read.All'
            'BitLockerKey.Read.All'
            'CrossTenantInformation.ReadBasic.All'
            'DelegatedPermissionGrant.ReadWrite.All'
            'Device.ReadWrite.All'
            'DeviceLocalCredential.Read.All'
            'DeviceManagementApps.ReadWrite.All'
            'DeviceManagementConfiguration.ReadWrite.All'
            'DeviceManagementManagedDevices.ReadWrite.All'
            'DeviceManagementServiceConfig.ReadWrite.All'
            'Directory.AccessAsUser.All'
            'Directory.ReadWrite.All'
            'Domain.Read.All'
            'Group.ReadWrite.All'
            'GroupMember.ReadWrite.All'
            'IdentityRiskEvent.ReadWrite.All'
            'IdentityRiskyServicePrincipal.ReadWrite.All'
            'IdentityRiskyUser.ReadWrite.All'
            'Mail.ReadBasic.Shared'
            'Organization.Read.All'
            'Policy.Read.All'
            'Policy.Read.ConditionalAccess'
            'Policy.ReadWrite.Authorization'
            'RoleManagement.ReadWrite.Directory'
            'SecurityEvents.ReadWrite.All'
            'SecurityIncident.ReadWrite.All'
            'User-Mail.ReadWrite.All'
            'User-PasswordProfile.ReadWrite.All'
            'User-Phone.ReadWrite.All'
            'User.EnableDisableAccount.All'
            'User.ManageIdentities.All'
            'User.ReadWrite.All'
            'User.RevokeSessions.All'
            'UserAuthenticationMethod.ReadWrite'
            'UserAuthenticationMethod.ReadWrite.All'
            'UserAuthMethod-Passkey.ReadWrite.All'
        )

        $Scopes = $DefaultScopes
        if ( $AdditionalScopes ) {
            $Scopes = $DefaultScopes + $AdditionalScopes | Select-Object -Unique
        }

        # Check if already connected to the right tenant with all required scopes and a valid token
        $ExistingContext = Get-MgContext -ErrorAction SilentlyContinue
        if ( -not $Force -and $ExistingContext -and $ExistingContext.TenantId -eq $TenantId ) {
            $MissingScopes = $Scopes | Where-Object { $ExistingContext.Scopes -notcontains $_ }
            if ( -not $MissingScopes ) {
                if ( $Global:IRT_Session -and $Global:IRT_Session.Graph -and $Global:IRT_Session.TenantId -eq $TenantId ) {
                    if ( -not (Test-TokenExpired -Token $Global:IRT_Session.Graph.Token) ) {
                        Write-Host "Already connected to Microsoft Graph for tenant $TenantId." -ForegroundColor Yellow
                        return $Global:IRT_Session.Graph
                    }
                    Write-Verbose 'Graph token expired, re-authenticating.'
                    $Global:IRT_Session.Graph = $null
                    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                }
            } else {
                Write-Verbose "Graph session missing scopes, re-authenticating: $($MissingScopes -join ', ')"
            }
        } elseif ( $Force -and $Global:IRT_Session -and $Global:IRT_Session.Graph -and $Global:IRT_Session.TenantId -eq $TenantId ) {
            Write-Verbose '-Force specified, re-acquiring Graph token.'
            $Global:IRT_Session.Graph = $null
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }

        $GraphBaseUrl = 'https://graph.microsoft.com'
        $Authority    = "https://login.microsoftonline.com/$TenantId"
        if ( $GCCHigh ) {
            $GraphBaseUrl = 'https://graph.microsoft.us'
            $Authority    = "https://login.microsoftonline.us/$TenantId"
        }

        # Ensure the MSAL assembly is loaded from Microsoft.Graph.Authentication.
        $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
        if ( -not $GraphModule ) {
            throw 'Microsoft.Graph.Authentication must be imported before connecting to Graph.'
        }
        $MsalDll = Join-Path $GraphModule.ModuleBase 'Dependencies' 'Core' 'Microsoft.Identity.Client.dll'

        if ( -not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }) ) {
            Add-Type -Path $MsalDll
        }

        # Microsoft Graph Command Line Tools — Microsoft first-party app pre-consented for
        # Graph delegated permissions. No app registration needed.
        $GraphClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'

        # MSAL requires fully-qualified scope URIs for Graph delegated permissions
        $MsalScopes = [string[]]($Scopes | ForEach-Object {"$GraphBaseUrl/$_"})

        # Reuse the cached MSAL app instance to preserve its token cache (which holds the refresh token)
        if ( $Global:IRT_Session -and $Global:IRT_Session.Graph -and $Global:IRT_Session.Graph.PublicClientApplication -and $Global:IRT_Session.TenantId -eq $TenantId ) {
            $App = $Global:IRT_Session.Graph.PublicClientApplication
        } else {
            $App = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($GraphClientId).
                WithAuthority($Authority).
                WithRedirectUri('http://localhost').
                Build()
        }

        # Try silent refresh first using MSAL's cached refresh token before prompting the user
        $TokenResult = $null
        $CachedAccounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
        if ($CachedAccounts) {
            $CachedAccount = $CachedAccounts | Select-Object -First 1
            try {
                $TokenResult = $App.AcquireTokenSilent($MsalScopes, $CachedAccount).ExecuteAsync().GetAwaiter().GetResult()
                Write-Verbose 'Graph token silently refreshed.'
            } catch {
                Write-Verbose "Silent Graph token refresh failed, falling back to interactive: $_"
                $TokenResult = $null
            }
        }

        # Request admin consent so scopes are granted tenant-wide rather than per-user.
        # 'consent' (not 'admin_consent') is the valid prompt value for the /authorize endpoint.
        # When the signing-in user is a Global Admin, Entra shows the
        # "Consent on behalf of your organization" checkbox.
        $AdminConsentParams = [System.Collections.Generic.Dictionary[string,string]]::new()
        $AdminConsentParams['prompt'] = 'consent'

        if ($TokenResult) {
            # Token acquired via silent refresh — no additional steps needed
        } elseif ($DeviceCode) {
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
            $TokenTask = $App.AcquireTokenWithDeviceCode($MsalScopes, $Helper.Callback).WithExtraQueryParameters($AdminConsentParams).ExecuteAsync()

            # Block the PS thread until MSAL fires the device-code callback.
            $CodeResult = $Helper.WaitForResult(30000)
            if ($null -eq $CodeResult) {
                throw 'Timed out waiting for device code response from MSAL.'
            }

            # All PS work happens here on the main runspace thread.
            if ($CodeResult.Message -match 'enter the code\s+(\S+)') {
                $Matches[1] | Set-Clipboard
                Write-Host "Device code '$($Matches[1])' copied to clipboard." -ForegroundColor Green
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
            try {
                $AcquireBuilder = $App.AcquireTokenInteractive($MsalScopes).
                    WithPrompt([Microsoft.Identity.Client.Prompt]::NoPrompt)
                $AcquireBuilder = $AcquireBuilder.WithExtraQueryParameters($AdminConsentParams)
                $TokenResult = $AcquireBuilder.ExecuteAsync().GetAwaiter().GetResult()
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        $Token = $TokenResult.AccessToken

        if (-not $Token) {
            throw 'Failed to acquire Graph access token.'
        }

        # Only call Connect-MgGraph if not already connected to this tenant with the right scopes.
        $ExistingContext = Get-MgContext -ErrorAction SilentlyContinue
        $MissingScopes   = $Scopes | Where-Object {$ExistingContext.Scopes -notcontains $_}
        if (-not $ExistingContext -or $ExistingContext.TenantId -ne $TenantId -or $MissingScopes) {
            $SecureToken = ConvertTo-SecureString -String $Token -AsPlainText -Force

            $MgConnectParams = @{
                AccessToken = $SecureToken
                NoWelcome   = $true
            }
            if ($GCCHigh) {$MgConnectParams['Environment'] = 'USGov'}

            Connect-MgGraph @MgConnectParams
        }

        return [pscustomobject]@{
            Token                 = $Token
            Account               = $TokenResult.Account.Username
            TenantId              = $TenantId
            PublicClientApplication = $App
        }
    36}
}
