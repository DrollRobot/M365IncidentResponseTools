function Format-Powershell {
    <#
    .SYNOPSIS
    This function will remove all comments, empty lines, and leading whitespace from Powershell
    content in the clipboard or passed with -Content.

    .EXAMPLE
    Format-Powershell -Comments -KeepVersion -EmptyLines

    In scripts:
    Format-Powershell -Comments -EmptyLines -Whitespace -Script -Content $Content

    .NOTES
    Version: 1.0.3
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, ValueFromPipeline = $true )]
        [string] $Content,
        [switch] $Script,
        [switch] $Comments,
        [switch] $KeepVersion,
        [switch] $EmptyLines,
        [switch] $Whitespace,
        [switch] $OneLine
    )

    process {

        if ( -not $Script ) {
            $IsClipboardContent = $false
            if ( [string]::IsNullOrWhiteSpace( $Content ) ) {
                # if no content is provided, get text from the clipboard
                Write-Host -ForegroundColor Green "`nProcessing text from clipboard."
                $Content = Get-Clipboard -Raw
                $IsClipboardContent = $true
            }
        }

        # convert to standardized line ending
        $Content = $Content -replace "\r\n", "`n"

        # capture version number
        if ( $KeepVersion ) {
            $VersionPattern = "Version:\s?.*"
            $VersionString = $Content |
                Select-String -Pattern $VersionPattern -AllMatches |
                ForEach-Object { $_.Matches.Value }
        }

        # remove comments
        if ($Comments) {
            $Params = @{
                Content                        = $Content
                RemoveCommentsInParamBlock     = $true
                RemoveCommentsBeforeParamBlock = $true
            }
            if ($EmptyLines) {
                $Params["RemoveAllEmptyLines"] = $true
            }
            $Content = Remove-Comment @Params
        }

        # insert version number
        if ( $KeepVersion ) {
            # separate into l$Cines
            $SplitContent = $Content -Split "\r?\n"

            # insert version into the second line
            $ContentWithVersion = $SplitContent[0..0] +
            "    # ${VersionString}" +
            $SplitContent[1..$SplitContent.Length]

            # rejoin into one string
            $Content = $ContentWithVersion -Join "`n"
        }

        # remove whitespace from each line
        if ($Whitespace) {
            $Content = Remove-WhitespaceFromLine -Content $Content
        }

        if ( $OneLine ) {
            $Content = Remove-Newline -Content $Content
        }

        if ( $IsClipboardContent ) {
            # display output in console
            Write-Host -ForegroundColor Green "`nOutput:"
            Write-Host $Content
            # only copy to clipboard if the content was originally from the clipboard
            $Content | Set-Clipboard
        }
        else {
            # output content if it was provided directly
            Write-Output $Content
        }

    } # end process
}