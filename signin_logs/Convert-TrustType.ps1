function Convert-TrustType {
	<#
	.SYNOPSIS
	Helper function for displaying logs. Accepts string or int, returns human readable description".
	
	.NOTES
    TrustType int values described here:
    https://learn.microsoft.com/en-us/azure/active-directory/devices/concept-azure-ad-join

	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [psobject] $TrustType
    )

    begin {}
    
    process {

        if ($TrustType -is [int]) {
            switch ($TrustType) {
                0 { return "Az Registered" }
                1 { return "Az Joined" }
                2 { return "Hybrid Joined" }
                Default { return [string]$TrustType }
            }
        }
        elseif ($TrustType -is [string]) {
            switch ($TrustType.ToLower()) {
                "0" { return "Az Registered" }
                "1" { return "Az Joined" }
                "2" { return "Hybrid Joined" }
                "Hybrid Azure AD joined" { return "Hybrid Joined" }
                "Azure AD joined" { return "Az Joined" }
                "Azure AD registered" { return "Az Registered" }
                Default { return $TrustType }
            }
        }
        else {
            return [string]$TrustType
        }
    }
}