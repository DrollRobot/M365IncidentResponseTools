function Build-EntraDeviceRow {
    <#
    .SYNOPSIS
    Converts raw Microsoft Graph device objects into display rows for the
    Get-IRTAllEntraDevice spreadsheet.

    .DESCRIPTION
    Pure transformation (no I/O, no Graph calls). Sorts devices by registration
    date newest-first (devices with no registration date sort to the bottom),
    maps TrustType to a friendly JoinType, resolves the registered owner UPN(s),
    converts the registration and last-sign-in timestamps to local time, and
    captures the full raw device as a JSON 'Raw' column. The property order of the
    returned objects is the spreadsheet column order.

    .PARAMETER Device
    The raw Graph device objects (from Get-MgDevice with RegisteredOwners expanded).

    .OUTPUTS
    System.Collections.Generic.List[PSCustomObject]
    #>
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Device
    )

    # newest registration first; null registration dates fall to the bottom
    $Sorted = $Device | Sort-Object -Property RegistrationDateTime -Descending

    $Rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($d in $Sorted) {

        $Raw = $d | ConvertTo-Json -Depth 10

        # friendly join type
        $JoinType = switch ($d.TrustType) {
            'AzureAd' { 'Entra joined' }
            'ServerAd' { 'Hybrid joined' }
            'Workplace' { 'Entra registered' }
            default { $d.TrustType }
        }

        # registered owner UPN(s)
        $OwnerUpn = ($d.RegisteredOwners | ForEach-Object {
                $_.AdditionalProperties['userPrincipalName']
            }) -join ', '

        # local-time dates
        $RegDate = $null
        if ($d.RegistrationDateTime) { $RegDate = $d.RegistrationDateTime.ToLocalTime() }
        $LastSignIn = $null
        if ($d.ApproximateLastSignInDateTime) {
            $LastSignIn = $d.ApproximateLastSignInDateTime.ToLocalTime()
        }

        $Rows.Add([pscustomobject]@{
                Raw                           = $Raw
                RegistrationDateTime          = $RegDate
                ApproximateLastSignInDateTime = $LastSignIn
                DisplayName                   = $d.DisplayName
                JoinType                      = $JoinType
                TrustType                     = $d.TrustType
                AccountEnabled                = $d.AccountEnabled
                OperatingSystem               = $d.OperatingSystem
                OperatingSystemVersion        = $d.OperatingSystemVersion
                RegisteredOwnerUPN            = $OwnerUpn
                IsCompliant                   = $d.IsCompliant
                IsManaged                     = $d.IsManaged
                IsRooted                      = $d.IsRooted
                DeviceOwnership               = $d.DeviceOwnership
                EnrollmentType                = $d.EnrollmentType
                ProfileType                   = $d.ProfileType
                ManagementType                = $d.ManagementType
                MdmAppId                      = $d.MdmAppId
                DeviceId                      = $d.DeviceId
                Id                            = $d.Id
            })
    }

    return $Rows
}
