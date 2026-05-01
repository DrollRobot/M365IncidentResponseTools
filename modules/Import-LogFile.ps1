New-Alias -Name "ImportLogs" -Value "Import-LogFile" -Force
New-Alias -Name "ImportLog" -Value "Import-LogFile" -Force
function Import-LogFile {
    <#
	.SYNOPSIS


	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [string] $Pattern,
        [switch] $ReturnPath,
        [switch] $Script
    )

    begin {

        # variables
        $CurrentPath = Get-Location

        if ( -not $Pattern ) {
            $Pattern = "\.xml$"
        }

        # get file names
        $Files = Get-ChildItem -Path $CurrentPath |
            Where-Object { $_.Name -match $Pattern } |
            Sort-Object LastWriteTime -Descending
        $FileNames = $Files.Name
    }

    process {

        if ( @( $FileNames ).Count -eq 1 ) {

            # if only one file, import that one
            Write-Host @Cyan "Only one file found in the current directory. Importing ${FileNames}."
            $ResolvedXmlPath = Join-Path -Path $CurrentPath -ChildPath $FileNames
        }
        # if more than one file, present user with a menu
        elseif ( @( $FileNames ).Count -gt 1 ) {
            $MenuParams = @{
                Title   = "Select a file to import logs from:"
                List    = $true
                Options = $FileNames
            }
            $FileName = Build-Menu @MenuParams
            $ResolvedXmlPath = Join-Path -Path $CurrentPath -ChildPath $FileName
        }
        # if none found
        else {
            throw "No files found matching ${FileNamePattern}."
        }

        if ( $ReturnPath ) {
            return $ResolvedXmlPath
        }
        else {

            $Data = Import-CliXml -Path $ResolvedXmlPath
            if ( $Script ) {
                return $Data
            }
            else {
                $Global:Logs = $Data
                $null = $Global:Logs
            }
        }
    }
}