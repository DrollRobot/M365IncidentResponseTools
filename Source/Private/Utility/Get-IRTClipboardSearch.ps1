function Get-IRTClipboardSearch {
    <#
    .SYNOPSIS
    Reads the clipboard and returns one trimmed search string per non-empty line.

    .DESCRIPTION
    Internal helper that backs the -FromClipboard switch on the Find-IRT* functions.
    Pulls the current clipboard contents, normalizes line endings, trims surrounding
    whitespace from each line, and discards blank lines. The resulting array is suitable
    for use as a -Search value, treating each clipboard line as a separate query.

    Throws a terminating error when the clipboard is empty or contains no usable lines.

    .EXAMPLE
    $Search = Get-IRTClipboardSearch
    Returns each non-empty clipboard line as an element of the returned array.

    .OUTPUTS
    System.String[]

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string[]])]
    [CmdletBinding()]
    param ()

    begin {
        Import-IRTModule -Name 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
    }

    process {

        # Get-Clipboard returns one array element per line by default, but -Raw or
        # programmatic copies can yield a single multi-line string; join then re-split
        # so both shapes normalize to one element per line.
        $Raw = @( Get-Clipboard )
        $Lines = ( $Raw -join "`n" ) -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }

        if ( @( $Lines ).Count -eq 0 ) {
            throw 'Clipboard is empty or contains no usable search text.'
        }

        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Pulled $( @( $Lines ).Count ) search term(s) from clipboard.")

        return [string[]] $Lines
    }
}
