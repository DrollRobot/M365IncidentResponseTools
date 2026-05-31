function Compress-IRTInvestigationFolder {
    <#
	.SYNOPSIS
	Compresses all folders ending with "_investigation" into folder called investigations.

	.NOTES
	Version: 1.0.0
	#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Days', Justification = 'Used inside scriptblock'
    )]
    [CmdletBinding()]
    param (
        [int] $Days = 3
    )

    begin {
        # get the current directory path
        $CurrentDirectory = Get-Location

        # define the destination path as a subfolder named "incidents" under the current directory
        $DestinationPath = Join-Path -Path $CurrentDirectory.Path -ChildPath '\investigations\'

        if ( -not ( Test-Path -Path $DestinationPath ) ) {
            $null = New-Item -ItemType Directory -Path $DestinationPath
        }
    }

    process {

        # find all subdirectories in the current directory whose names end with "investigation"
        $IncidentParams = @{
            Path      = $CurrentDirectory.Path
            Directory = $true
        }
        $Investigations = Get-ChildItem @IncidentParams | Where-Object {
            $_.Name -match 'investigation$'
        }

        foreach ( $Investigation in $Investigations ) {

            # retrieve all files under this folder (including subfolders)
            $FilesParams = @{
                Path    = $Investigation.FullName
                File    = $true
                Recurse = $true
            }
            $Files = Get-ChildItem @FilesParams

            # find any file modified within the last 48 hours
            $RecentFilesParams = @{
                FilterScript = {
                    $_.LastWriteTime -ge (Get-Date).AddDays($Days)
                }
            }
            $RecentFiles = $Files | Where-Object @RecentFilesParams

            # only compress if there are no recent files
            if ( -not $RecentFiles ) {

                # build the .zip file path
                $ArchiveName = $Investigation.Name + '.zip'
                $ArchivePath = Join-Path -Path $DestinationPath -ChildPath $ArchiveName

                # compress the folder into the destination path
                $CompressParams = @{
                    Path             = $Investigation.FullName
                    DestinationPath  = $ArchivePath
                    CompressionLevel = 'Optimal'
                    Force            = $true
                }
                Compress-Archive @CompressParams

                # delete folder
                if ( Test-Path $ArchivePath ) {
                    Remove-Item -Recurse -Force -LiteralPath $Investigation.FullName
                }
            }
        }
    }
}