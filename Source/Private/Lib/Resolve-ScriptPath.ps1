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
    Version: 1.0.2
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

        [string] $FileExtension,

        [switch] $WriteToLog
    )

    begin {

        function Write-Preferred {
            param(
                [Parameter( Mandatory, Position = 0 )]
                [string] $Message
            )

            if ( $WriteToLog ) {
                Write-LogFile $Message
            }
            else {
                Write-Host $Message
            }
        }
    }

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
            Write-Preferred $Message
            throw $Message
        }

        # exit if path doesn't exist
        if ( -not $ResolvedPath ) {
            $Message = "Path does not exist: ${Path}. Exiting."
            Write-Preferred $Message
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
                Write-Preferred $Message
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
                Write-Preferred $Message
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
                    Write-Preferred $Message
                    throw $Message
                }
            }
        }

        return $ResolvedPath
    }
}
