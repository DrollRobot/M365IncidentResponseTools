function Invoke-GraphUALRequest {
    <#
    .SYNOPSIS
    Sends one request to the Microsoft Graph audit log query API, with retry.

    .DESCRIPTION
    Internal helper for the Start/Wait/Receive-IRTGraphUAL family. Wraps
    Invoke-MgGraphRequest with the behaviour the audit search endpoint needs:

      - Builds the URI from IRT_Config.GraphUALApiVersion (default 'v1.0') when the
        caller passes a relative -Path, and passes an absolute -Uri through unchanged so
        an @odata.nextLink can be followed directly.
      - Falls back to the beta endpoint, once per session, when v1.0 answers
        "Resource not found for the segment 'auditLog'". Some tenants have the v1.0
        route documented but not enabled.
      - Refreshes the Graph token before each attempt. A wait loop can outlive the token.
      - Retries throttling and timeouts, honouring Retry-After when Graph sends one and
        backing off exponentially when it does not. The Graph SDK already retries 429
        internally about three times over ~24 seconds, so the retry count here is low by
        design.

    Errors are returned as a result object rather than thrown, so callers can record a
    failure per job and carry on with the rest of a group.

    .PARAMETER Path
    Path relative to the audit log root, for example 'queries' or
    'queries/<id>/records?$top=999'. Mutually exclusive with -Uri.

    .PARAMETER Uri
    Absolute URI, used to follow an @odata.nextLink. Mutually exclusive with -Path.

    .PARAMETER Method
    HTTP method. Default: GET.

    .PARAMETER Body
    Request body for POST. Serialized as JSON by Invoke-MgGraphRequest.

    .PARAMETER OutputType
    Invoke-MgGraphRequest output type. Default: HashTable. Pass 'Json' to inspect the
    raw response.

    .PARAMETER MaxRetry
    Attempts before giving up on a retryable failure. Default: 3.

    .PARAMETER ThrottleDelaySeconds
    Base backoff in seconds when Graph throttles without a Retry-After header. Grows
    exponentially per retry. Default: 30.

    .EXAMPLE
    ```powershell
    Invoke-GraphUALRequest -Path 'queries'
    ```
    Lists the tenant's audit log queries.

    .EXAMPLE
    ```powershell
    $Body = @{ displayName = 'IRT: test'; filterStartDateTime = '2026-09-01T00:00:00Z' }
    Invoke-GraphUALRequest -Method 'POST' -Path 'queries' -Body $Body
    ```
    Creates an audit log query.

    .OUTPUTS
    [pscustomobject] with properties:
        Ok      - [bool] whether the request succeeded
        Result  - the response body, or $null on failure
        Error   - [string] exception message on failure, else $null
        Status  - [string] short HTTP status name when one could be parsed
        Seconds - [int] elapsed seconds

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [string] $Uri,

        [ValidateSet('GET', 'POST', 'DELETE', 'PATCH')]
        [string] $Method = 'GET',

        [hashtable] $Body,

        [ValidateSet('HashTable', 'Json', 'PSObject')]
        [string] $OutputType = 'HashTable',

        [ValidateRange(1, 10)]
        [int] $MaxRetry = 3,

        [ValidateRange(1, 3600)]
        [int] $ThrottleDelaySeconds = 30
    )

    Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Session-scoped API version. Starts from config, then sticks at 'beta' for the rest
    # of the session once a v1.0 call proves the route is missing, so one tenant-wide
    # fact is learned once instead of on every request.
    if (-not $Global:IRT_GraphUALApiVersion) {
        $Configured = $Global:IRT_Config.GraphUALApiVersion
        $Global:IRT_GraphUALApiVersion = $Configured ? $Configured : 'v1.0'
    }

    # A relative path is resolved against the current API version; an absolute URI
    # (a nextLink) already carries its own version and is used as given.
    $UsingPath = $PSCmdlet.ParameterSetName -eq 'Path'

    $Attempt = 0
    while ($true) {
        $Attempt++

        if ($UsingPath) {
            $Version = $Global:IRT_GraphUALApiVersion
            $RequestUri = "https://graph.microsoft.com/${Version}/security/auditLog/${Path}"
        }
        else {
            $RequestUri = $Uri
        }

        # a long wait or a large download can outlive the token; cheap no-op when healthy
        $null = Update-IRTToken -Service 'Graph'

        $Params = @{
            Method      = $Method
            Uri         = $RequestUri
            OutputType  = $OutputType
            ErrorAction = 'Stop'
        }
        if ($Body) {
            $Params['Body'] = $Body
            $Params['ContentType'] = 'application/json'
        }

        Write-PSFMessage -Level 9 -Message "${FunctionName}: $Method $RequestUri"

        try {
            $Result = Invoke-MgGraphRequest @Params
            return [pscustomobject]@{
                Ok      = $true
                Result  = $Result
                Error   = $null
                Status  = 'OK'
                Seconds = [int]$Stopwatch.Elapsed.TotalSeconds
            }
        }
        catch {
            $Message = $_.Exception.Message
            $Status = Get-GraphUALErrorStatus -Message $Message

            # v1.0 documented but not enabled on this tenant: switch to beta and retry
            # the same request once. The switch persists for the session.
            $SegmentMissing = $Message -match "Resource not found for the segment 'auditLog'"
            if ($SegmentMissing -and $UsingPath -and
                $Global:IRT_GraphUALApiVersion -ne 'beta') {
                Write-IRT ('Audit search v1.0 is not available on this tenant. ' +
                    'Falling back to the beta endpoint.') -Level Warn
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: v1.0 route missing; switching to beta for the session.")
                $Global:IRT_GraphUALApiVersion = 'beta'
                continue
            }

            $IsThrottle = $Status -eq 'TooManyRequests' -or $Message -match '429'
            $IsTimeout = $Message -match
            'HttpClient\.Timeout|request was canceled|task was canceled'

            if (($IsThrottle -or $IsTimeout) -and $Attempt -lt $MaxRetry) {
                $DelayParams = @{
                    ErrorRecord = $_
                    Attempt     = $Attempt
                    BaseSeconds = $ThrottleDelaySeconds
                }
                $Wait = Get-GraphUALRetryDelay @DelayParams
                $Reason = $IsThrottle ? 'Throttled by Graph' : 'Request timed out'
                Write-IRT ("${Reason}. Waiting ${Wait}s then retrying " +
                    "(${Attempt}/${MaxRetry}).") -Level Warn
                Write-PSFMessage -Level 8 -ErrorRecord $_ -Message (
                    "${FunctionName}: ${Reason}; retry ${Attempt}/${MaxRetry} after ${Wait}s.")
                Start-Sleep -Seconds $Wait
                continue
            }

            Write-PSFMessage -Level Warning -ErrorRecord $_ -Message (
                "${FunctionName}: $Method $RequestUri failed after ${Attempt} attempt(s): " +
                "$Status - $Message")

            return [pscustomobject]@{
                Ok      = $false
                Result  = $null
                Error   = $Message
                Status  = $Status
                Seconds = [int]$Stopwatch.Elapsed.TotalSeconds
            }
        }
    }
}
