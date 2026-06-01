function Get-LoginOperationSummary {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory UserLoggedIn, UserLoggedOff, and UserLoginFailed events from UAL.

	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log,

        [switch] $Cached
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # ErrorNumber
        $ErrorDescription = ConvertTo-HumanErrorDescription -ErrorCode $Log.AuditData.ErrorNumber
        $SummaryLines.Add("Error: $ErrorDescription")

        # Target
        $TargetId = $Log.AuditData.Target.ID
        if ($TargetId) {
            # ensure global variable exists
            Request-GraphServicePrincipal -Return 'none' -Cached:$Cached

            # fetch name from table
            $TargetName = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            if ($TargetName) {
                $SummaryLines.Add("TargetApp: $TargetName")
            }
        }

        # DeviceProperties
        $DispNameEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DisplayName' }
        $DisplayName = $DispNameEntry.Value
        if (-not $DisplayName) {
            $DevNameEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'DeviceName' }
            $DisplayName = $DevNameEntry.Value
        }
        if ($DisplayName) { $SummaryLines.Add("DeviceDisplayName: $DisplayName") }
        $OS = ($Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'OS' }).Value
        if ($OS) { $SummaryLines.Add("OS: $OS") }
        $DevBrowserEntry = $Log.AuditData.DeviceProperties |
            Where-Object { $_.Name -eq 'DeviceBrowser' }
        $Browser = $DevBrowserEntry.Value
        if (-not $Browser) {
            $BrwTypeEntry = $Log.AuditData.DeviceProperties |
                Where-Object { $_.Name -eq 'BrowserType' }
            $Browser = $BrwTypeEntry.Value
        }
        if ($Browser) { $SummaryLines.Add("Browser: $Browser") }
        $TrustEntry = $Log.AuditData.DeviceProperties | Where-Object { $_.Name -eq 'TrustType' }
        $TrustType = Convert-TrustType -TrustType $TrustEntry.Value
        if ($TrustType) { $SummaryLines.Add("Trust: $TrustType") }

        # UserAgent
        $UserAgentEntry = $Log.AuditData.ExtendedProperties |
            Where-Object { $_.Name -eq 'UserAgent' }
        $UserAgent = $UserAgentEntry.Value
        if ($UserAgent) { $SummaryLines.Add("UserAgent: $UserAgent") }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}
