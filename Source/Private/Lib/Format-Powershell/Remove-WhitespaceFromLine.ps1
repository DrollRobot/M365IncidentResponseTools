function Remove-WhitespaceFromLine {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true
        )]
        [string]$Content
    )

    process {

        # split the content into individual lines
        $Lines = $Content -split "`n"

        # trim each line
        $Lines = $Lines | ForEach-Object { $_.Trim() }

        # change tabs to spaces
        $Lines = $Lines -replace "\t", ' '

        # remove instances of multiple spaces
        $Lines = $Lines -replace " +", ' '

        # join lines back together
        $Output = $Lines -join "`n"

        Write-Output $Output

    } # end process
}
