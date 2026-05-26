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
    Use device code authentication flow.

    .PARAMETER AccessToken
    A pre-existing access token to use for connection. Intended for use within
    runspaces where interactive authentication is not possible.

    .PARAMETER Browser
    Browser to use for device code login. Valid values: msedge, chrome, firefox, brave, default.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .NOTES
    Version: 3.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'DeviceCode', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Browser', Justification = 'Used inside scriptblock')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Private', Justification = 'Used inside scriptblock')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $TenantId,
        [string] $UserPrincipalName,
        [switch] $GCCHigh,
        [switch] $DeviceCode,
        [string] $AccessToken,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force
    )

    begin {
        $ExchangeScope = 'https://outlook.office365.com/.default'
        $Authority     = "https://login.microsoftonline.com/$TenantId"
        if ($GCCHigh) {
            $ExchangeScope = 'https://outlook.office365.us/.default'
            $Authority     = "https://login.microsoftonline.us/$TenantId"
        }
        $Scopes = [string[]]@($ExchangeScope)

        $ExoClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO first-party app
        $App = $null  # built lazily; not needed when -AccessToken provided
    }

    process {

        # ---------- Setup: scope, authority ----------

        # Inline helper - closes over $App, $Scopes, $DeviceCode, $Browser, $Private.
        # Tries silent refresh first, then interactive or device code.
        $AcquireToken = {
            $Cached = $App.GetAccountsAsync().GetAwaiter().GetResult()
            if ($Cached) {
                try {
                    return $App.AcquireTokenSilent($Scopes, ($Cached | Select-Object -First 1)).
                        ExecuteAsync().GetAwaiter().GetResult()
                } catch {
                    Write-Verbose "Silent Exchange token refresh failed: $_"
                }
            }

            if ($DeviceCode) {
                $DeviceCodeParams = @{
                    App     = $App
                    Scopes  = $Scopes
                    Browser = $Browser
                    Private = $Private
                }
                return Invoke-IRTDeviceCodeAuth @DeviceCodeParams
            }

            try {
                $Cts  = [System.Threading.CancellationTokenSource]::new()
                $Task = $App.AcquireTokenInteractive($Scopes).ExecuteAsync($Cts.Token)
                try {
                    while (-not $Task.IsCompleted) { Start-Sleep -Milliseconds 250 }
                } finally {
                    $Cts.Cancel()
                    $Cts.Dispose()
                }
                return $Task.GetAwaiter().GetResult()
            } catch {
                throw "Interactive token acquisition failed: $_"
            }
        }

        # ---------- Phase 1: token ----------
        # Three sources, in priority order:
        #   1. -AccessToken parameter (caller already has one - runspace reconnect)
        #   2. cached session token (if not forced, same tenant, not expired)
        #   3. fresh acquisition (silent refresh inside the helper if possible)

        $NeedNewToken = $false

        if ($AccessToken) {
            $Token = $AccessToken
            $Upn   = $UserPrincipalName
        } elseif (-not $Force -and
                  $Global:IRT_Session -and
                  $Global:IRT_Session.Exchange -and
                  $Global:IRT_Session.TenantId -eq $TenantId -and
                  $Global:IRT_Session.Exchange.Token -and
                  -not (Test-TokenExpired -Token $Global:IRT_Session.Exchange.Token)) {
            $Token = $Global:IRT_Session.Exchange.Token
            $Upn   = $Global:IRT_Session.Exchange.UserPrincipalName
            $App   = $Global:IRT_Session.Exchange.PublicClientApplication
            Write-Verbose 'Using cached Exchange token.'
        } else {
            # MSAL setup, only needed when we actually have to acquire.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            if (-not $GraphModule) {
                throw 'Microsoft.Graph.Authentication must be imported' +
                    ' before acquiring an Exchange token.'
            }
            $MsalDllParams = @{
                Path                = $GraphModule.ModuleBase
                ChildPath           = 'Dependencies'
                AdditionalChildPath = 'Core', 'Microsoft.Identity.Client.dll'
            }
            $MsalDll = Join-Path @MsalDllParams
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
                Add-Type -Path $MsalDll
            }

            $App = if ($Global:IRT_Session -and
                       $Global:IRT_Session.Exchange -and
                       $Global:IRT_Session.Exchange.PublicClientApplication -and
                       $Global:IRT_Session.TenantId -eq $TenantId) {
                $Global:IRT_Session.Exchange.PublicClientApplication
            } else {
                [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ExoClientId).
                    WithAuthority($Authority).
                    WithRedirectUri('http://localhost').
                    Build()
            }

            if (
                -not $AccessToken -and
                $Global:IRT_Session -and
                $Global:IRT_Session.Exchange -and
                $Global:IRT_Session.Exchange.Token
            ) {
                Write-IRT "Refreshing expired Exchange token for tenant $TenantId..." -Level Warn
            }
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire Exchange access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn   = $TokenResult.Account.Username
            $NeedNewToken = $true
        }

        # ---------- Phase 2: Connect-ExchangeOnline ----------
        # Connect if no existing connection, wrong tenant, or -Force.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Connected' -and $_.TenantID -eq $TenantId }

        $NeedConnect = $Force -or -not $ExistingConnection

        if ($NeedConnect) {
            if ($ExistingConnection) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            }
            $Params = @{
                AccessToken       = $Token
                UserPrincipalName = $Upn
                ShowBanner        = $false
            }
            if ($GCCHigh) { $Params['ExchangeEnvironmentName'] = 'O365USGovGCCHigh' }
            Connect-ExchangeOnline @Params
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to Exchange Online for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
        }
    }
}
