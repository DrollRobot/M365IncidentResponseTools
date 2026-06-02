function Get-YesNo {
    <#
    .SYNOPSIS
    A utility function for asking the user to answer y or n. Returns $true if y, $false if n. If any other input is given, it will ask the user again.

    .PARAMETER Prompt
    The message to present to the user. The function appends " (y/n)"

    .PARAMETER Prompt
    Changes the color of the user prompt. Accepts same colors as Write-Host.

    .NOTES
    Version: 1.2.2
    1.2.2 - Fixed bug where incorrect input would generate errors.
    1.2.1 - Fixed bug where random text would be added to prompt. 
    1.2.0 - Added color option.
    #>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [string] $Prompt,

        [ValidateSet( 'Black', 'Blue', 'Cyan', 'DarkBlue', 'DarkCyan', 'DarkGray', 'DarkGreen', 'DarkMagenta', 'DarkRed', 'DarkYellow', 'Gray', 'Green', 'Magenta', 'Red', 'White', 'Yellow' )]
        [string] $ForegroundColor
    )

    if ( $ForegroundColor ) {
        $PromptParams['ForegroundColor'] = $ForegroundColor
    }

    # get input from user. if message provided, print message
    if ( $Prompt ) {
        Write-Host -NoNewLine "${Prompt} (y/n): "
    }
    # get user input
    $Reply = (Read-Host).Trim().ToLower()

    # if the user doesn't reply y or n, ask again
    while ( $Reply -ne 'y' -and $Reply -ne 'n' ) {
        Write-Host -NoNewLine "Your reply must be 'y' or 'n'. Please try again:"
        $Reply = (Read-Host).Trim().ToLower()
    }

    # function will return true if user answers yes, otherwise returns $false
    if ( $Reply -eq 'y' ) {
        return $true
    }
    else {
        return $false
    }
}