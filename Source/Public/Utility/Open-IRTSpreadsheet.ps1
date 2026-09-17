function Open-IRTSpreadsheet {
    <#
    .SYNOPSIS
    Opens the .xlsx spreadsheets in a folder.

    .DESCRIPTION
    Opens every .xlsx workbook in a folder (the current directory by default) using the
    system default spreadsheet application. Intended for users who turn off the
    OpenSpreadsheets config setting so IRT exports do not open automatically: after running
    a batch of commands, run Open-IRTSpreadsheet to open the workbooks that were created.

    Excel lock and temporary files (names beginning with '~$') are skipped.

    .PARAMETER Path
    Folder to search for .xlsx files. Defaults to the current directory.

    .PARAMETER Recurse
    Also open .xlsx files found in subfolders of Path.

    .EXAMPLE
    Open-IRTSpreadsheet
    Opens every .xlsx file in the current directory.

    .EXAMPLE
    Open-IRTSpreadsheet -Path 'C:\Cases\Contoso' -Recurse
    Opens every .xlsx file under C:\Cases\Contoso and all of its subfolders.

    .OUTPUTS
    None.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('Open-IRTSpreadsheets', 'OpenIRTSpreadsheet', 'IRTSpreadsheet')]
    [CmdletBinding()]
    param (
        [string] $Path = '.',
        [switch] $Recurse
    )

    process {
        if (-not (Test-Path -Path $Path)) {
            Write-IRT "Path not found: ${Path}" -Level Error
            return
        }

        $GetParams = @{
            Path   = $Path
            Filter = '*.xlsx'
            File   = $true
        }
        if ($Recurse) {
            $GetParams.Recurse = $true
        }
        $Files = Get-ChildItem @GetParams |
            Where-Object { $_.Extension -eq '.xlsx' -and $_.Name -notlike '~$*' }

        if (-not $Files) {
            $Resolved = (Resolve-Path -Path $Path).Path
            Write-IRT "No .xlsx files found in: ${Resolved}" -Level Warn
            return
        }

        foreach ($File in $Files) {
            Write-IRT "Opening: $($File.Name)"
            Invoke-Item -Path $File.FullName
        }
    }
}
