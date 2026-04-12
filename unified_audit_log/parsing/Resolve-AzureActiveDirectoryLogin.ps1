function Resolve-AzureActiveDirectoryLogin {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory UserLoggedIn, UserLoggedOff, and UserLoginFailed events from UAL.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log
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
            Request-GraphServicePrincipals -Return 'none'

            # fetch name from table
            $TargetName = $Global:IRT_ServicePrincipalsByAppId["$TargetId"].DisplayName
            if ($TargetName) {
                $SummaryLines.Add("TargetApp: $TargetName")
            }
        }

        # DeviceProperties
        $DisplayName = ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'DisplayName' }).Value
        if ($DisplayName) {$SummaryLines.Add("DeviceDisplayName: $DisplayName")}
        $OS = ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'OS' }).Value
        if ($OS) { $SummaryLines.Add("OS: $OS") }
        $Browser = ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'DeviceBrowser' }).Value
        if ($Browser) { $SummaryLines.Add("Browser: $Browser") }
        $TrustType = Convert-TrustType -TrustType ($Log.AuditData.DeviceProperties | Where-Object {$_.Name -eq 'TrustType' }).Value
        if ($TrustType) { $SummaryLines.Add("Trust: $TrustType") }

        # UserAgent
        $UserAgent = ($Log.AuditData.ExtendedProperties | Where-Object {$_.Name -eq 'UserAgent'}).Value
        if ($UserAgent) {$SummaryLines.Add("UserAgent: $UserAgent")}

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}