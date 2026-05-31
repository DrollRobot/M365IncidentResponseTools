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
        ((Get-Date) - (Get-Item $CsvPath).LastWriteTime) -gt (New-TimeSpan -Days 6)
    ) {
        # Download the file
        Invoke-WebRequest -Uri $Url -OutFile $CsvPath
    }
}