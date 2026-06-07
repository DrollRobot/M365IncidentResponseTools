function Set-IRTUserUsageLocation {
    <#
	.SYNOPSIS
	Sets user's usage location.

	.NOTES
	Version: 1.0.2
    1.0.2 - .Contains() method is case sensitive. Adjusted so .ToUpper() happens before
            running .Contains() so lower case input of valid country codes will be accepted.
	#>
    [Alias('SetLocation', 'SetUsage')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject,

        [string] $CountryCode
    )

    begin {
        Update-IRTToken -Service 'Graph'
        Import-IRTModule -Name 'Microsoft.Graph.Users'
        # if not passed directly, find global
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # variables
        $CountryCodeHelpUrl = "https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes"
        $ValidCountryCodes = [system.collections.generic.hashset[string]]::new( [string[]](
                'AD', 'AE', 'AF', 'AG', 'AI', 'AL', 'AM', 'AO', 'AQ', 'AR', 'AS', 'AT', 'AU', 'AW',
                'AX', 'AZ', 'BA', 'BB', 'BD', 'BE', 'BF', 'BG', 'BH', 'BI', 'BJ', 'BL', 'BM', 'BN',
                'BO', 'BQ', 'BR', 'BS', 'BT', 'BV', 'BW', 'BY', 'BZ', 'CA', 'CC', 'CD', 'CF', 'CG',
                'CH', 'CI', 'CK', 'CL', 'CM', 'CN', 'CO', 'CR', 'CU', 'CV', 'CW', 'CX', 'CY', 'CZ',
                'DE', 'DJ', 'DK', 'DM', 'DO', 'DZ', 'EC', 'EE', 'EG', 'EH', 'ER', 'ES', 'ET', 'FI',
                'FJ', 'FK', 'FM', 'FO', 'FR', 'GA', 'GB', 'GD', 'GE', 'GF', 'GG', 'GH', 'GI', 'GL',
                'GM', 'GN', 'GP', 'GQ', 'GR', 'GS', 'GT', 'GU', 'GW', 'GY', 'HK', 'HM', 'HN', 'HR',
                'HT', 'HU', 'ID', 'IE', 'IL', 'IM', 'IN', 'IO', 'IQ', 'IR', 'IS', 'IT', 'JE', 'JM',
                'JO', 'JP', 'KE', 'KG', 'KH', 'KI', 'KM', 'KN', 'KP', 'KR', 'KW', 'KY', 'KZ', 'LA',
                'LB', 'LC', 'LI', 'LK', 'LR', 'LS', 'LT', 'LU', 'LV', 'LY', 'MA', 'MC', 'MD', 'ME',
                'MF', 'MG', 'MH', 'MK', 'ML', 'MM', 'MN', 'MO', 'MP', 'MQ', 'MR', 'MS', 'MT', 'MU',
                'MV', 'MW', 'MX', 'MY', 'MZ', 'NA', 'NC', 'NE', 'NF', 'NG', 'NI', 'NL', 'NO', 'NP',
                'NR', 'NU', 'NZ', 'OM', 'PA', 'PE', 'PF', 'PG', 'PH', 'PK', 'PL', 'PM', 'PN', 'PR',
                'PS', 'PT', 'PW', 'PY', 'QA', 'RE', 'RO', 'RS', 'RU', 'RW', 'SA', 'SB', 'SC', 'SD',
                'SE', 'SG', 'SH', 'SI', 'SJ', 'SK', 'SL', 'SM', 'SN', 'SO', 'SR', 'SS', 'ST', 'SV',
                'SX', 'SY', 'SZ', 'TC', 'TD', 'TF', 'TG', 'TH', 'TJ', 'TK', 'TL', 'TM', 'TN', 'TO',
                'TR', 'TT', 'TV', 'TW', 'TZ', 'UA', 'UG', 'UM', 'US', 'UY', 'UZ', 'VA', 'VC', 'VE',
                'VG', 'VI', 'VN', 'VU', 'WF', 'WS', 'YE', 'YT', 'ZA', 'ZM', 'ZW') )
        $UserGetProperties = @(
            'UsageLocation'
            'DisplayName'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'UserPrincipalName'
        )
        $UserDisplayProperties = @(
            'UsageLocation'
            'DisplayName'
            'OnPremisesSamAccountName'
            'UserPrincipalName'
            'Id'
        )

        # show country codes if not provided
        if (-not $CountryCode) {
            # open browser to wikipedia
            Start-Process $CountryCodeHelpUrl
            Write-IRT "Opening browser..." -Level Warn
            $CountryCode = Read-Host "Enter ISO-3166 A-2 country code"
            if ($CountryCode) {
                # set code to capital letters
                $CountryCode = $CountryCode.ToUpper()
            }
            while ( -not $ValidCountryCodes.Contains( $CountryCode ) ) {
                Write-IRT "Not a valid country code. Try again." -Level Error
                $CountryCode = Read-Host "Enter ISO-3166 A-2 country code"
            }
        }
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # set code to capital letters
            $CountryCode = $CountryCode.ToUpper()

            # set new location
            $Upn = $ScriptUserObject.UserPrincipalName
            if ($PSCmdlet.ShouldProcess($Upn, "Set usage location to $CountryCode")) {
                Write-IRT "Setting new usage location."
                Update-MgUser -UserId $ScriptUserObject.Id -Usagelocation $CountryCode
            }

            # get new user object
            Write-IRT "Getting new user properties."
            $FullUserObject = Get-MgUser -UserId $ScriptUserObject.Id -Property $UserGetProperties

            # display new object
            $FullUserObject | Format-Table $UserDisplayProperties
        }
    }
}
