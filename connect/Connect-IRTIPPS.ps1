function Connect-IRTIPPS {
    <#
    .SYNOPSIS
    Connects to Security & Compliance PowerShell (IPPS).

    .DESCRIPTION
    Acquires a portable access token via MSAL using EXO's first-party client ID
    and the IPPS audience, then passes it to Connect-IPPSSession via -AccessToken.
    This bypasses IPPS's internal MSAL token-acquisition path, which fails with
    an assembly version mismatch when the Microsoft.Graph.Authentication MSAL
    has been pre-loaded.

    .PARAMETER SearchOnly
    Use the search-only audience (https://dataservice.o365filtering.com) and
    pass -EnableSearchOnlySession to Connect-IPPSSession. Required for newer
    eDiscovery and retention cmdlets (New-ComplianceSearchAction,
    Set-RetentionCompliancePolicy, etc.). Defaults to $true.

    .NOTES
    Version: 2.0.0
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

        [bool]   $SearchOnly = $true,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = $Global:IRT_Config.Browser,
        [switch] $Private,

        [switch] $Force
    )

    begin {
        # SearchOnly determines the audience. The same first-party client ID is
        # used either way; only the audience changes.
        $IPPSScope = if ($SearchOnly) {
            'https://dataservice.o365filtering.com/.default'
        } else {
            'https://outlook.office365.com/.default'
        }
        $Authority = "https://login.microsoftonline.com/$TenantId"
        if ($GCCHigh) {
            $Authority = "https://login.microsoftonline.us/$TenantId"
        }
        $Scopes = [string[]]@($IPPSScope)

        $ExoClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'  # EXO/IPPS first-party app
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
                    Write-Verbose "Silent IPPS token refresh failed: $_"
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
        #   2. cached session token (same tenant, same SearchOnly mode, not expired)
        #   3. fresh acquisition (silent refresh inside the helper if possible -
        #      reuses EXO's MSAL cache when present, swapping audience silently)
        #
        # The SearchOnly check on the cached path matters: a token issued for
        # the search-only audience won't authenticate against the full audience
        # and vice versa.

        $NeedNewToken = $false

        if ($AccessToken) {
            $Token = $AccessToken
            $Upn   = $UserPrincipalName
        } elseif (-not $Force -and
                  $Global:IRT_Session -and
                  $Global:IRT_Session.IPPS -and
                  $Global:IRT_Session.TenantId -eq $TenantId -and
                  $Global:IRT_Session.IPPS.SearchOnly -eq $SearchOnly -and
                  $Global:IRT_Session.IPPS.Token -and
                  -not (Test-TokenExpired -Token $Global:IRT_Session.IPPS.Token)) {
            $Token = $Global:IRT_Session.IPPS.Token
            $Upn   = $Global:IRT_Session.IPPS.UserPrincipalName
            $App   = $Global:IRT_Session.IPPS.PublicClientApplication
            Write-Verbose 'Using cached IPPS token.'
        } else {
            # MSAL setup, only needed when we actually have to acquire.
            $GraphModule = Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
            if (-not $GraphModule) {
                throw 'Microsoft.Graph.Authentication must be imported before acquiring an IPPS token.'
            }
            $MsalDll = Join-Path $GraphModule.ModuleBase 'Dependencies' 'Core' 'Microsoft.Identity.Client.dll'
            if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' })) {
                Add-Type -Path $MsalDll
            }

            # Prefer EXO's MSAL app if available - same client ID = same token
            # cache = silent audience swap with no prompt. Fall back to IPPS's
            # cached app, then build a new one.
            $App = if ($Global:IRT_Session -and
                       $Global:IRT_Session.Exchange -and
                       $Global:IRT_Session.Exchange.PublicClientApplication -and
                       $Global:IRT_Session.TenantId -eq $TenantId) {
                $Global:IRT_Session.Exchange.PublicClientApplication
            } elseif ($Global:IRT_Session -and
                      $Global:IRT_Session.IPPS -and
                      $Global:IRT_Session.IPPS.PublicClientApplication -and
                      $Global:IRT_Session.TenantId -eq $TenantId) {
                $Global:IRT_Session.IPPS.PublicClientApplication
            } else {
                [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ExoClientId).
                    WithAuthority($Authority).
                    WithRedirectUri('http://localhost').
                    Build()
            }

            if (
                -not $AccessToken -and
                $Global:IRT_Session -and
                $Global:IRT_Session.IPPS -and
                $Global:IRT_Session.IPPS.Token
            ) {
                Write-IRT "Refreshing expired IPPS token for tenant $TenantId..." -Level Warn
            }
            $TokenResult = & $AcquireToken
            if (-not $TokenResult.AccessToken) {
                throw 'Failed to acquire IPPS access token.'
            }
            $Token = $TokenResult.AccessToken
            $Upn   = $TokenResult.Account.Username
            $NeedNewToken = $true
        }

        # ---------- Phase 2: Connect-IPPSSession ----------
        # IPPS connections show up in Get-ConnectionInformation alongside EXO.
        # Distinguish by ConnectionUri matching the compliance endpoint.

        $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Connected' -and
                $_.TenantID -eq $TenantId -and
                $_.ConnectionUri -match 'compliance\.protection\.outlook\.com'
            }

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
            if ($SearchOnly) {
                $Params['EnableSearchOnlySession'] = $true
            }
            if ($GCCHigh) {
                $Params['ConnectionUri'] = 'https://ps.compliance.protection.office365.us/powershell-liveid/'
            }
            Connect-IPPSSession @Params
        }

        if (-not $NeedNewToken -and -not $NeedConnect) {
            Write-IRT "Already connected to IPPS for tenant $TenantId." -Level Warn
        }

        return [pscustomobject]@{
            Token                   = $Token
            UserPrincipalName       = $Upn
            TenantId                = $TenantId
            PublicClientApplication = $App
            SearchOnly              = [bool]$SearchOnly
        }
    }
}