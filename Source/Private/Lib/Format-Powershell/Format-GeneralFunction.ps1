function Format-GeneralFunction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param()

    # variables
    $VersionPattern = "Version: .*"

    # get content from clipboard
    $Content = Get-Clipboard -Raw

    # extract version
    $Version = $Content |
        Select-String -Pattern $VersionPattern -AllMatches |
        ForEach-Object { $_.Matches.Value }
    Write-Host -ForegroundColor Green "`nExtracted version string:"
    Write-Host $Version

    # run remove-comments
    $CommentParams = @{
        Content = $Content
        RemoveAllEmptyLines = $true
        RemoveCommentsInParamBlock = $true
        RemoveCommentsBeforeParamBlock = $true
    }
    $OutputRaw = Remove-Comment @CommentParams

    # separate into lines
    $OutputLines = $OutputRaw -Split "`r?`n"

    # insert version into the second line
    $OutputLinesWithVersion = $OutputLines[0..0] +
    "    # ${Version}" +
    $OutputLines[1..$OutputLines.Length]

    # rejoin into one string
    $Output = $OutputLinesWithVersion -Join "`r`n"

    # remove double carriage returns to prevent errors
    $Output = $Output -Replace "`r`r", "`r"

    # show on screen
    Write-Host -ForegroundColor Green "`nOutput:"
    Write-Output $Output

    # put output in clipboard
    Set-Clipboard $Output
}