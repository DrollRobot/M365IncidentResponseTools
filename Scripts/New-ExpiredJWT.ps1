<#
.SYNOPSIS
    Replaces the session's Graph, Exchange, and IPPS tokens with expired ones.

.DESCRIPTION
    Sets each token in $Global:IRT_Session to an unsigned JWT that expired in 1970, so
    the next command exercises the token refresh path.

.EXAMPLE
    .\New-ExpiredJWT.ps1

.OUTPUTS
    None.
#>

function New-ExpiredJwt {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '')]
    param()
    $Header = '{"alg":"none","typ":"JWT"}'
    $Payload = '{"exp":1}'   # Jan 1 1970
    $b64 = {
        param($s)
        $Bytes = [Text.Encoding]::UTF8.GetBytes($s)
        [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    "$(& $b64 $Header).$(& $b64 $Payload).sig"
}

$Global:IRT_Session.Graph.Token = New-ExpiredJwt
$Global:IRT_Session.Exchange.Token = New-ExpiredJwt
$Global:IRT_Session.IPPS.Token = New-ExpiredJwt
