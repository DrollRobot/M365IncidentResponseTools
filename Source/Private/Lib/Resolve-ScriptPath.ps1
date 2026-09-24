function Resolve-ScriptPath {
    <#
    .SYNOPSIS
    Resolves provided path and exits if it's not of the correct type.

    .PARAMETER Folder
    Script will exit if path is not a folder.

    .PARAMETER File
    Script will exit if path is not a file.

    .PARAMETER FileExtension
    Script will exit if path does not have this file path.

    .EXAMPLE
    The following would all complete without exiting:
    Resolve-ScriptPath -Path 'C:\Temp\' -Folder
    Resolve-ScriptPath -Path 'C:\Temp\File.exe' -File
    Resolve-ScriptPath -Path 'C:\Temp\File.exe' -File -FileExtension 'exe'

    .NOTES
    Version: 1.1.0
    1.1.0 - Removed -WriteToLog. Failures are reported only by the thrown error, which
            callers already surface, instead of also being written to the console.
    1.0.2 - Resolved logic error with file extension detection.
    #>
    [CmdletBinding( DefaultParameterSetName = 'File' )]
    param(
        [Parameter( Mandatory, Position = 0 )]
        [string] $Path,

        [Parameter( ParameterSetName = 'Folder' )]
        [switch] $Folder,

        [Parameter( ParameterSetName = 'File' )]
        [switch] $File,

        [string] $FileExtension
    )

    process {

        # resolve path
        try {
            $ResolveParams = @{
                Path = $Path
                ErrorAction = 'Stop'
            }
            $ResolvedPath = ( Resolve-Path @ResolveParams ).Path
        }
        catch {
            $Message = "Unable to resolve path: ${Path}. Exiting."
            throw $Message
        }

        # exit if path doesn't exist
        if ( -not $ResolvedPath ) {
            $Message = "Path does not exist: ${Path}. Exiting."
            throw $Message
        }

        # test if path is of correct type
        if ( $Folder ) {
            # verify path is folder
            $TestPathParameters = @{
                Path     = $ResolvedPath
                PathType = 'Container'
            }
            $Folder = Test-Path @TestPathParameters
            if ( -not $Folder ) {
                $Message = "Path is not a folder: ${Path}. Exiting."
                throw $Message
            }
        }
        elseif ( $File ) {

            # verify path is file
            $TestPathParameters = @{
                Path     = $ResolvedPath
                PathType = 'Leaf'
            }
            $File = Test-Path @TestPathParameters
            if ( -not $File ) {
                $Message = "Path is not a file: ${Path}. Exiting."
                throw $Message
            }

            if ( $FileExtension ) {

                # extract file extension
                $ExtensionParams = @{
                    Path = $ResolvedPath
                    Leaf = $true
                }
                $FileName = Split-Path @ExtensionParams

                if ( $FileName -notmatch "${FileExtension}$" ) {
                    $Message = "File extension does not match: " +
                        "${FileExtension},${FileName}. Exiting."
                    throw $Message
                }
            }
        }

        return $ResolvedPath
    }
}
