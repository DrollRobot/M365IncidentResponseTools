function Get-IRTDefaultDomain {
    <#
    .SYNOPSIS
    Returns the tenant's default verified domain, with lazy caching on the session variable.

    .DESCRIPTION
    Queries Microsoft Graph for the tenant's default verified domain (IsDefault -eq $true),
    caches both the full domain object and the second-level domain (SLD) label on
    $Global:IRT_Session, and returns whichever form was requested.

    On the first call the function makes one Graph API request (Get-MgDomain). Every
    subsequent call within the same session is served from the in-memory cache with no
    network traffic. The cache is invalidated automatically when Disconnect-IRT clears
    $Global:IRT_Session.

    The second-level domain (SLD) is the label immediately to the left of the top-level
    domain (TLD): for "contoso.com" the SLD is "contoso". This label is used throughout
    the module as a short tenant identifier in exported file names.

    .PARAMETER Domain
    Return the full Microsoft Graph domain object
    (Microsoft.Graph.PowerShell.Models.MicrosoftGraphDomain) for the default domain.

    .PARAMETER SecondLevelDomain
    Return only the second-level domain label extracted from the default domain's Id
    property (e.g. "contoso" from "contoso.com"). This is the default output when
    neither switch is specified.

    .OUTPUTS
    [string] when -SecondLevelDomain or no parameter is supplied.
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphDomain] when -Domain is supplied.

    .EXAMPLE
    Get-IRTDefaultDomain

    Returns the SLD label for the current tenant's default domain, e.g. "contoso".
    Equivalent to passing -SecondLevelDomain explicitly.

    .EXAMPLE
    Get-IRTDefaultDomain -SecondLevelDomain

    Same as the default. Useful when you want to be explicit in a script.

    .EXAMPLE
    Get-IRTDefaultDomain -Domain

    Returns the full Graph domain object, including Id, IsDefault, IsVerified, etc.

    .EXAMPLE
    $FileNameDate = (Get-Date).ToString('yy-MM-dd_HH-mm')
    $FileName = "Users_Raw_$(Get-IRTDefaultDomain)_${FileNameDate}.xml"

    Typical use: build a tenant-scoped export file name.

    .NOTES
    Requires an active Microsoft Graph connection established via Connect-IRT or
    Connect-IRTGraph.

    The function writes a Verbose message only on a cache miss (i.e. when an actual
    Graph API call is made). There is no Verbose output on a cache hit.

    Property names stored on $Global:IRT_Session:
        DefaultDomain     - the full Graph domain object
        DefaultDomainName - the SLD string
    #>
    [OutputType([string], ParameterSetName = 'SecondLevelDomain')]
    [OutputType([object], ParameterSetName = 'Domain')]
    [CmdletBinding(DefaultParameterSetName = 'SecondLevelDomain')]
    param (
        [Parameter(ParameterSetName = 'Domain')]
        [switch] $Domain,

        [Parameter(ParameterSetName = 'SecondLevelDomain')]
        [switch] $SecondLevelDomain
    )

    process {

        # serve from cache when available
        if ($Global:IRT_Session -and $Global:IRT_Session.PSObject.Properties['DefaultDomain']) {
            if ($Domain)            { return $Global:IRT_Session.DefaultDomain }
            if ($SecondLevelDomain) { return $Global:IRT_Session.DefaultDomainName }
            return $Global:IRT_Session.DefaultDomainName
        }

        # cache miss -- fetch from Graph
        $FunctionName = $MyInvocation.MyCommand.Name
        Write-Verbose "${FunctionName}: Get-MgDomain (cache miss)"
        $DefaultDomain     = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DefaultDomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        if ($Global:IRT_Session) {
            $AmParams = @{ Force = $true }
            $AmParams.NotePropertyName  = 'DefaultDomain'
            $AmParams.NotePropertyValue = $DefaultDomain
            $Global:IRT_Session | Add-Member @AmParams
            $AmParams.NotePropertyName  = 'DefaultDomainName'
            $AmParams.NotePropertyValue = $DefaultDomainName
            $Global:IRT_Session | Add-Member @AmParams
        }

        if ($Domain)            { return $DefaultDomain }
        if ($SecondLevelDomain) { return $DefaultDomainName }
        return $DefaultDomainName
    }
}
