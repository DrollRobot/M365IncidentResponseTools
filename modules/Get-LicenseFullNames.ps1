function Get-LicenseCSVFile {
    <#
    .SYNOPSIS
    Downloads the Microsoft license name CSV to $env:AppData if missing or older than 6 days.

    .DESCRIPTION
    Internal helper used by Get-LicenseFullNames. Downloads the Microsoft product names and
    service plan identifiers CSV from the Microsoft Download Center. Skips the download if
    the file already exists in $env:AppData and was last modified less than 6 days ago.
    #>
    param (
        [string]$Url,
        [string]$CsvPath
    )

    # Check if the file exists and if the last modified date is more than a week ago
    if (
        -not ( Test-Path $CsvPath ) -or
        ( Get-Date ) - ( Get-Item $CsvPath ).LastWriteTime -gt ( New-TimeSpan -Days 6 )
    ) {
        # Download the file
        Invoke-WebRequest -Uri $Url -OutFile $CsvPath
    }
}

function Get-LicenseNameFromCSV {
    <#
    .SYNOPSIS
    Looks up a license SKU GUID in the Microsoft CSV file and returns the friendly product name.

    .DESCRIPTION
    Internal helper used by Get-LicenseFullNames. Imports the CSV from the specified path
    and returns the Product_Display_Name for the matching SKU GUID.
    #>
    param (
        [string]$SkuId,
        [string]$CsvPath
    )

    # import csv file
    $CsvData = Import-Csv -Path $CsvPath

    # finds the row that matches the skuid
    $MatchingRow = $CsvData | Where-Object { $_.guid -eq $SkuId }

    # pulls the full name from the matching row
    $LicenseFullName = $Matchingrow.Product_Display_Name

    return $LicenseFullName
}


function Get-LicenseFullNames {
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
    Get-MgSubscribedSku | Get-LicenseFullNames
    Returns enriched license objects with a LicenseFullName property added.

    .EXAMPLE
    Get-LicenseFullNames -SkuId '05e9a617-0261-4cee-bb44-138d3ef5d965'
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
        $Url = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"

        # Set the destination path
        $CsvPath = "${env:AppData}\${ModuleName}\ProductNamesAndServicePlanIdentifiers.csv"

        # download updated list of license names, if needed
        Get-LicenseCSVFile -url $Url -csvpath $CsvPath

        # two if statements take different action depending on whether being use in pipeline or manually
        if ($SkuId -and $_) {
            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath | Sort-Object -Unique

            # adds attributes
            $OutputObject = $_ | Add-Member -MemberType NoteProperty -Name "LicenseFullName" -Value $LicenseFullName -PassThru

            Write-Output $OutputObject
        }

        if ($SkuId -and $null -eq $_) {
            # if manually enters, validates good guid
            if ($SkuId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                Write-Host "Invalid GUID provided. Please provide a valid GUID."
                return
            }

            # uses the skuid to find the full name in the csv
            $LicenseFullName = Get-LicenseNameFromCSV -SkuId $SkuId -CsvPath $CsvPath | Sort-Object -Unique

            Write-Output "License full name is:`n$LicenseFullName"
        }
    }
}