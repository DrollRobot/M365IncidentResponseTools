function Invoke-IRTDeviceCodeAuth {
    <#
    .SYNOPSIS
    Acquires an access token via MSAL device-code flow, handling callback
    marshaling and the clipboard/browser convenience steps.

    .DESCRIPTION
    MSAL's device-code callback is invoked on a .NET thread-pool thread,
    where PowerShell-based delegates fail silently. This helper compiles
    a small C# wrapper whose callback is a pure .NET lambda, then blocks
    the calling thread until MSAL fires it. The device code is copied to
    the clipboard and the verification URL is opened in the configured
    browser.

    .PARAMETER App
    An MSAL IPublicClientApplication built by the caller. Untyped to avoid
    requiring the MSAL assembly at function-definition time.

    .PARAMETER Scope
    Scopes to request. Format depends on the audience (Graph permission
    URIs, .default for Exchange/IPPS, etc.).

    .PARAMETER ExtraQueryParameter
    Optional hashtable of extra parameters appended to the /authorize
    request (e.g. @{ prompt = 'consent' } to drive admin consent).

    .PARAMETER Browser
    Browser to use for opening the verification URL.

    .PARAMETER Private
    Open the browser in private/incognito mode.

    .PARAMETER TimeoutMs
    How long to wait for MSAL to fire the device-code callback. Default 30000.

    .OUTPUTS
    Microsoft.Identity.Client.AuthenticationResult
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $App,
        [Parameter(Mandatory)] [Alias('Scopes')] [string[]] $Scope,

        [Alias('ExtraQueryParameters')] [hashtable] $ExtraQueryParameter,

        [ValidateSet('msedge','chrome','firefox','brave','default')]
        [string] $Browser = 'default',
        [switch] $Private,

        [int] $TimeoutMs = 30000
    )

    # PS-based delegates fail when MSAL invokes them on a thread-pool thread.
    # A C# lambda runs on any thread. Func<object,Task> avoids referencing
    # MSAL types at compile time - Func contravariance lets it satisfy
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

    $Helper  = [IRT.DeviceCodeHelper]::new()
    $Builder = $App.AcquireTokenWithDeviceCode($Scope, $Helper.Callback)

    if ($ExtraQueryParameter -and $ExtraQueryParameter.Count -gt 0) {
        $Extra = [System.Collections.Generic.Dictionary[string,string]]::new()
        foreach ($Key in $ExtraQueryParameter.Keys) {
            $Extra[$Key] = [string]$ExtraQueryParameter[$Key]
        }
        $Builder = $Builder.WithExtraQueryParameters($Extra)
    }

    $Task = $Builder.ExecuteAsync()

    # Block until MSAL fires the callback on a thread-pool thread.
    $CodeResult = $Helper.WaitForResult($TimeoutMs)
    if ($null -eq $CodeResult) {
        throw 'Timed out waiting for device code response from MSAL.'
    }

    # All PS-side work runs on the runspace thread.
    if ($CodeResult.Message -match 'enter the code\s+(\S+)') {
        $Matches[1] | Set-Clipboard
        Write-IRT "Device code '$($Matches[1])' copied to clipboard." -Level Warn
        Open-Browser -Browser $Browser -Url $CodeResult.VerificationUrl -Private:$Private
    } else {
        Write-Host $CodeResult.Message
    }

    try {
        return $Task.GetAwaiter().GetResult()
    } catch {
        throw "Device code token acquisition failed: $_"
    }
}
