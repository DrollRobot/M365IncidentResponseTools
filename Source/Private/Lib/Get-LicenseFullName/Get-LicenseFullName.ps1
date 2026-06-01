function Get-LicenseFullName {
    <#
    .SYNOPSIS
    Pipeline function that adds a LicenseFullName property to Graph license objects.

    .DESCRIPTION
    Accepts Microsoft Graph subscribed SKU objects from the pipeline and enriches each
    with a LicenseFullName property resolved from Microsoft's published product name CSV.
    The CSV is downloaded automatically to $env:AppData on first use (or when stale).

    When called with a bare -SkuId GUID instead of pipeline input, returns the friendly
    name as a string directly.

    .PARAMETER SkuId
    The SKU GUID of the license to look up. Accepts pipeline input and
    ValueFromPipelineByPropertyName.

    .PARAMETER LicenseFullName
    Reserved for internal pipeline passthrough; not intended for direct use.

    .EXAMPLE
    Get-MgSubscribedSku | Get-LicenseFullName
    Returns enriched license objects with a LicenseFullName property added.

    .EXAMPLE
    Get-LicenseFullName -SkuId '05e9a617-0261-4cee-bb44-138d3ef5d965'
    Returns the friendly product name for the given SKU GUID.

    .OUTPUTS
    PSObject (enriched input object) when used in the pipeline.
    System.String when called with a bare -SkuId.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$SkuId,
        [string]$LicenseFullName
    )

    process {
        $ModuleName = $MyInvocation.MyCommand.ModuleName

        # URL to download csv from
        $Url = 'https://download.microsoft.com/download/e/3/e/' +
        'e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/' +
        'Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'

        # Set the destination path
        $CsvPath = "${env:AppData}\${ModuleName}\ProductNamesAndServicePlanIdentifiers.csv"

        # download updated list of license names, if needed
        Get-LicenseCSVFile -url $Url -csvpath $CsvPath

        # two if statements take different action depending on whether being
        # used in pipeline or manually
        if ($SkuId -and $_) {
            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath |
                Sort-Object -Unique

            # adds attributes
            $AmParams = @{
                MemberType = 'NoteProperty'
                Name       = 'LicenseFullName'
                Value      = $LicenseFullName
                PassThru   = $true
            }
            $OutputObject = $_ | Add-Member @AmParams

            Write-Output $OutputObject
        }

        if ($SkuId -and $null -eq $_) {
            # if manually enters, validates good guid
            if ($SkuId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                Write-IRT "Invalid GUID provided. Please provide a valid GUID." -Level Error
                return
            }

            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath |
                Sort-Object -Unique

            Write-IRT "License full name is:"
            Write-IRT $LicenseFullName -NoColor
        }
    }
}
