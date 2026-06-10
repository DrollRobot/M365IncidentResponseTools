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
    Switch to Format-Table -AutoSize output instead of Write-PSObject color formatting.
    Set automatically when called from a runspace (e.g., the incident response playbook).

    .EXAMPLE
    Get-IRTLicenseReport
    Displays a color-formatted license table in the console.

    .EXAMPLE
    $Licenses = Get-IRTLicenseReport -Objects
    Returns raw license objects for further processing.

    .OUTPUTS
    None (console table) by default.
    Microsoft.Graph.PowerShell.Models.MicrosoftGraphSubscribedSku[] when -Objects is used.

    .NOTES
    Version: 1.1.3
    1.1.3 - Added optional output formatting for runspaces.
    #>
    [Alias('LicenseReport')]
    [CmdletBinding()]
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

            # generate report for viewing in terminal
            $OutputTable = $Licenses | ForEach-Object {

                $LicenseName = if ( $_.LicenseFullName ) {
                    $_.LicenseFullName
                }
                else {
                    $_.SkuPartNumber
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

            # sort
            $SortOrder = @(
                'CapabilityStatus'
                'AppliesTo'
                'LicenseName'
            )
            $OutputTable = $OutputTable | Sort-Object $SortOrder

            if ( $RunSpace ) {
                # output formatting if being run in a runspace
                return $OutputTable | Format-Table -AutoSize
            }
            else {

                # output formatting if being run directly in terminal
                $WriteParams = @{
                    HeadersForeColor = 'Green'
                    MatchMethod      = 'Match', 'Match'
                    Column           = 'LicenseName', 'LicenseName'
                    Value            = 'E3', 'E5'
                    ValueForeColor   = 'Magenta', 'Magenta'
                }
                Write-PSObject $OutputTable @WriteParams
            }
        }
    }
}
