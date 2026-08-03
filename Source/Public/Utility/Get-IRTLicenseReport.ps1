function Get-IRTLicenseReport {
    <#
    .SYNOPSIS
    Shows table of tenant licenses.

    .DESCRIPTION
    Retrieves all subscribed SKUs from Microsoft Graph, resolves each SKU's friendly
    product name via Get-LicenseFullName, and displays a formatted table showing
    capability status, applies-to scope, license name, total enabled units, consumed
    units, and available units. Use -Objects to return raw enriched objects instead.

    .PARAMETER Objects
    Return raw license objects (with the LicenseFullName property added) instead of
    displaying the formatted table. Useful for piping to further processing.

    .PARAMETER Runspace
    Deprecated. Output is always a plain Format-Table now; the switch is retained
    so existing callers do not break.

    .EXAMPLE
    ```powershell
    Get-IRTLicenseReport
    ```
    Displays a color-formatted license table in the console.

    .EXAMPLE
    ```powershell
    $Licenses = Get-IRTLicenseReport -Objects
    ```
    Returns raw license objects for further processing.

    .OUTPUTS
    None (console table) by default.
    Microsoft.Graph.PowerShell.Models.MicrosoftGraphSubscribedSku[] when -Objects is used.

    .NOTES
    Version: 1.3.0
    1.3.0 - Highlight E5 SKUs in yellow via $PSStyle (PS 7.2+) and print an E5
            security-tooling callout after the table.
    1.2.0 - Removed the Write-PSObject dependency; output is always plain
            Format-Table. -Runspace is now a no-op kept for compatibility.
    1.1.3 - Added optional output formatting for runspaces.
    #>
    [Alias('LicenseReport')]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Runspace',
        Justification = 'Deprecated no-op retained for backward compatibility.')]
    param (
        [switch] $Objects,
        [switch] $Runspace
    )

    begin {
        $ImportParams = @{
            Name = @(
                'Microsoft.Graph.Authentication'
                'Microsoft.Graph.Identity.DirectoryManagement'
            )
        }
        Import-IRTModule @ImportParams
        $Context = Get-MgContext
        if ( -not $Context ) {
            throw "Not connected to Graph. Exiting"
        }

        # get license objects
        $Licenses = Get-MgSubscribedSku |
            # Where-Object { $_.CapabilityStatus -eq 'Enabled' } |
            Get-LicenseFullName
    }

    process {

        Write-IRT "Retrieving tenant licenses..."

        if ( $Objects ) {
            return $Licenses
        }
        # if user doesn't specify output, display table in terminal
        else {

            if ( -not $Licenses ) {
                Write-IRT "No Licenses found. Exiting." -Level Error
                return
            }

            # sort before projecting so embedded ANSI color codes can't skew
            # LicenseName ordering
            $SortOrder = @(
                'CapabilityStatus'
                'AppliesTo'
                { if ( $_.LicenseFullName ) { $_.LicenseFullName } else { $_.SkuPartNumber } }
            )
            $Licenses = $Licenses | Sort-Object $SortOrder

            # track E5 SKUs - they unlock additional security tooling
            $E5Licenses = [Collections.Generic.List[string]]::new()
            $Highlight = $PSStyle.Foreground.BrightYellow
            $Reset = $PSStyle.Reset

            # generate report for viewing in terminal
            $OutputTable = $Licenses | ForEach-Object {

                $LicenseName = if ( $_.LicenseFullName ) {
                    $_.LicenseFullName
                }
                else {
                    $_.SkuPartNumber
                }

                # highlight E5 SKUs in yellow - they unlock extra security tooling
                $IsE5 = $_.LicenseFullName -match '\bE5\b' -or
                    $_.SkuPartNumber -match 'SPE_E5|ENTERPRISEPREMIUM'
                if ( $IsE5 ) {
                    $E5Licenses.Add( $LicenseName )
                    $LicenseName = "${Highlight}${LicenseName}${Reset}"
                }

                [pscustomobject]@{
                    CapabilityStatus = $_.CapabilityStatus
                    AppliesTo        = $_.AppliesTo
                    LicenseName      = $LicenseName
                    Enabled          = $_.PrepaidUnits.Enabled
                    Consumed         = $_.ConsumedUnits
                    Available        = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
                }
            }

            $OutputTable | Format-Table -AutoSize | Out-Host

            # flag the extra security tooling E5 unlocks
            if ( $E5Licenses.Count -gt 0 ) {
                Write-IRT ( "E5 detected - additional security tooling available: " +
                    "Defender (Endpoint/Identity/Office 365 P2), Entra ID P2 / " +
                    "Identity Protection, Advanced Audit." ) -Level Warn
            }

            return
        }
    }
}
