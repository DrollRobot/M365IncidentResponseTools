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