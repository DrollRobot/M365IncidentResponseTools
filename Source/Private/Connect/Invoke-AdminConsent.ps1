function Invoke-AdminConsent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $TenantId,
        [Parameter(Mandatory)] [string]   $ClientId,
        [Parameter(Mandatory)] [Alias('Scopes')] [string[]] $Scope,
        # Mandatory and no default: the resource URI is cloud-specific (e.g.
        # graph.microsoft.us for USGov). A wrong/commercial default silently produces
        # cross-cloud consent URLs, so fail loudly rather than guess.
        [Parameter(Mandatory)] [string] $ResourceUri,
        [ValidateSet('Commercial', 'USGov', 'USGovDoD', 'China')]
        [string] $Cloud,
        [string] $Browser = 'default',
        [switch] $Private,

        [int] $TimeoutSeconds = 300
    )

    begin {
        $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Listener.Start()
        $Port = ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
        $RedirectUri = "http://localhost:$Port/"
        Write-PSFMessage -Level 8 -Message (
            "Invoke-AdminConsent: Listener started on port $Port, " +
            "RedirectUri=$RedirectUri")
    }

    process {
        try {
            $LoginHost = $Global:IRT_CloudEnvironments[$Cloud].LoginHost
            $State = [guid]::NewGuid().ToString('N')
            Write-PSFMessage -Level 8 -Message (
                "Invoke-AdminConsent: TenantId=$TenantId, ClientId=$ClientId, " +
                "Cloud=$Cloud, Scope count=$($Scope.Count), State=$State")

            # Fully-qualify each scope with the resource URI, then space-delimit.
            # This is what makes /v2.0/adminconsent work for dynamic-consent apps
            # like Microsoft Graph Command Line Tools, where /.default would only
            # consent to statically configured permissions (User.Read in this case).
            $ScopeQuery = ($Scope | ForEach-Object { "$ResourceUri/$_" }) -join ' '

            $ConsentUrl = "$LoginHost/$TenantId/v2.0/adminconsent" +
            "?client_id=$ClientId" +
            "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
            "&state=$State" +
            "&scope=$([uri]::EscapeDataString($ScopeQuery))"

            Write-IRT 'Opening admin consent page in browser...' -Level Warn
            Write-IRT "  Granting tenant-wide consent for $($Scope.Count) scope(s)." -Level Warn
            Write-IRT '  Sign in as a Global Administrator and click Accept.' -Level Warn
            Open-Browser -Browser $Browser -Url $ConsentUrl -Private:$Private

            $Cts = [System.Threading.CancellationTokenSource]::new()
            $AcceptTask = $Listener.AcceptTcpClientAsync($Cts.Token)
            $Deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
            while (-not $AcceptTask.IsCompleted) {
                if ([datetime]::UtcNow -gt $Deadline) {
                    $Cts.Cancel()
                    throw "Timed out after $TimeoutSeconds seconds" +
                    " waiting for admin consent response."
                }
                Start-Sleep -Milliseconds 250
            }
            $Client = $AcceptTask.GetAwaiter().GetResult()

            try {
                $Stream = $Client.GetStream()
                $Reader = [System.IO.StreamReader]::new($Stream)
                $RequestLine = $Reader.ReadLine()

                $Body = '<html>' +
                '<body style="font-family:sans-serif;text-align:center;padding-top:4em">' +
                '<h2>Admin consent received.</h2>' +
                '<p>You may close this window and return to PowerShell.</p>' +
                '</body></html>'
                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                $Header = "HTTP/1.1 200 OK`r`n" +
                "Content-Type: text/html; charset=utf-8`r`n" +
                "Content-Length: $($Bytes.Length)`r`n" +
                "Connection: close`r`n`r`n"
                $HeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($Header)
                $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)
                $Stream.Write($Bytes, 0, $Bytes.Length)
                $Stream.Flush()
            } finally {
                $Client.Close()
            }

            if ($RequestLine -notmatch '^GET\s+(\S+)\s+HTTP') {
                throw "Malformed redirect request: $RequestLine"
            }
            $Path = $Matches[1]
            $Query = if ($Path -match '\?(.+)$') { $Matches[1] } else { '' }

            $Params = @{}
            foreach ($Pair in $Query -split '&') {
                $Kv = $Pair -split '=', 2
                if ($Kv.Count -eq 2) {
                    $Params[[uri]::UnescapeDataString($Kv[0])] = [uri]::UnescapeDataString($Kv[1])
                }
            }

            if ($Params['state'] -ne $State) {
                throw 'Admin consent response state mismatch - possible CSRF or stale request.'
            }
            if ($Params['error']) {
                $ErrCode = $Params['error']
                $ErrDesc = $Params['error_description']
                throw "Admin consent denied or failed: $ErrCode - $ErrDesc"
            }
            if ($Params['admin_consent'] -eq 'True') {
                Write-PSFMessage -Level 8 -Message 'Invoke-AdminConsent: admin_consent=True received.'
                return $true
            }
            throw "Unexpected admin consent response: $Query"
        }
        finally {
            if ($Cts) { $Cts.Cancel(); $Cts.Dispose() }
            $Listener.Stop()
        }
    }
}
