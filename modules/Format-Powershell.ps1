function Format-Powershell {
    <#
    .SYNOPSIS
    This function will remove all comments, empty lines, and leading whitespace from Powershell content in the clipboard or passed with -Content.

    .EXAMPLE
    Format-Powershell -Comments -KeepVersion -EmptyLines

    In scripts:
    Format-Powershell -Comments -EmptyLines -Whitespace -Script -Content $Content

    .NOTES
    Version: 1.0.3
    #>
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
        $VersionString = $Content | Select-String -Pattern $VersionPattern -AllMatches | ForEach-Object { $_.Matches.Value }
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
        $ContentWithVersion = $SplitContent[0..0] + "    # ${VersionString}" + $SplitContent[1..$SplitContent.Length]

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


function Remove-Newline {
	<#
	.SYNOPSIS
	Remove unnecessary newlines from Powershell code.

	.EXAMPLE


	.NOTES
		Version: 1.0.0
	#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string] $Content
    )

    process {

        # remove newlines before else, elseif, catch, finally
        $ElsePattern = "\}\s*(?:\r?\n\s*#.*\r?\n)?\s*(else|elseif|catch|finally)\s*([\{\(])"
        $ElseReplace = '} $1 $2'
        $Content = $Content -replace $ElsePattern,$ElseReplace

        # remove newlines after logical operators
        $LogicalPattern = "-(and|or|xor|not)\s*\n\s*"
        $LogicalReplace = '-$1 '
        $Content = $Content -replace $LogicalPattern,$LogicalReplace

        # remove newlines before/after pipes
        $PipePattern = "\s*\|\s*"
        $PipeReplace = "|"
        $Content = $Content -replace $PipePattern,$PipeReplace

        # remove newline from parameters
        $ParamNames = "Alias|CmdletBinding|Parameter|ValidateScript|ValidateSet|ValidateRange"
        $CmdletBindingPattern = "(\[(${ParamNames})\((.*?)\)])\s*\n\s*"
        $CmdletBindingReplace = '$1 '
        $Content = $Content -replace $CmdletBindingPattern,$CmdletBindingReplace

        # remove newlines after commas
        $CommaPattern = ",\s*\n\s*"
        $CommaReplace = ', '
        $Content = $Content -replace $CommaPattern,$CommaReplace

        # remove newlines after opening parenthesis/brackets
        $OpenPattern = "([\(\{])\s*"
        $OpenReplace = '$1'
        $Content = $Content -replace $OpenPattern,$OpenReplace

        # remove newlines before closing parenthesis/brackets
        $ClosePattern = "\s*([\)\}])"
        $CloseReplace = '$1'
        $Content = $Content -replace $ClosePattern,$CloseReplace

        # remove newlines, replace with semicolons. must be last
        $Content = $Content -replace '\n',';'

        return $Content
    }
}


function Remove-WhitespaceFromLine {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
	    [Parameter(
            Position=0,
            ValueFromPipeline=$true
        )]
        [string]$Content
    )

    process {

    # split the content into individual lines
    $Lines = $Content -split "`n"

    # trim each line
    $Lines = $Lines | ForEach-Object { $_.Trim() }

    # change tabs to spaces
    $Lines = $Lines -replace "\t",' '

    # remove instances of multiple spaces
    $Lines = $Lines -replace " +",' '

    # join lines back together
    $Output = $Lines -join "`n"

    Write-Output $Output

    } # end process
}


function Remove-Comment {
    <#
    .SYNOPSIS
    Remove comments from PowerShell file

    .DESCRIPTION
    Remove comments from PowerShell file and optionally remove empty lines
    By default comments in param block are not removed
    By default comments before param block are not removed

    .PARAMETER SourceFilePath
    File path to the source file

    .PARAMETER Content
    Content of the file

    .PARAMETER DestinationFilePath
    File path to the destination file. If not provided, the content will be returned

    .PARAMETER RemoveEmptyLines
    Remove empty lines if more than one empty line is found

    .PARAMETER RemoveAllEmptyLines
    Remove all empty lines from the content

    .PARAMETER RemoveCommentsInParamBlock
    Remove comments in param block. By default comments in param block are not removed

    .PARAMETER RemoveCommentsBeforeParamBlock
    Remove comments before param block. By default comments before param block are not removed

    .EXAMPLE
    Remove-Comments -SourceFilePath 'C:\Support\GitHub\PSPublishModule\Examples\TestScript.ps1' -DestinationFilePath 'C:\Support\GitHub\PSPublishModule\Examples\TestScript1.ps1' -RemoveAllEmptyLines -RemoveCommentsInParamBlock -RemoveCommentsBeforeParamBlock

    .NOTES
    Most of the work done by Chris Dent, with improvements by Przemyslaw Klys
    https://evotec.xyz/how-to-efficiently-remove-comments-from-your-powershell-script/
    #>
    [CmdletBinding(DefaultParameterSetName = 'FilePath', SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FilePath')]
        [alias('FilePath', 'Path', 'LiteralPath')]
        [string] $SourceFilePath,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [string] $Content,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [alias('Destination')]
        [string] $DestinationFilePath,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [switch] $RemoveAllEmptyLines,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [switch] $RemoveEmptyLines,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [switch] $RemoveCommentsInParamBlock,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [switch] $RemoveCommentsBeforeParamBlock,

        [Parameter(ParameterSetName = 'Content')]
        [Parameter(ParameterSetName = 'FilePath')]
        [switch] $DoNotRemoveSignatureBlock
    )
    if ($SourceFilePath) {
        $Fullpath = Resolve-Path -LiteralPath $SourceFilePath
        $Content = [IO.File]::ReadAllText($FullPath, [System.Text.Encoding]::UTF8)
    }

    $Tokens = $Errors = @()
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$Tokens, [ref]$Errors)
    #$functionDefinition = $ast.Find({ $args[0] -is [FunctionDefinitionAst] }, $false)
    $GroupedTokens = $Tokens | Group-Object { $_.Extent.StartLineNumber }
    $DoNotRemove = $false
    $DoNotRemoveCommentParam = $false
    $CountParams = 0
    $ParamFound = $false
    $SignatureBlock = $false
    $ToRemove = foreach ($Line in $GroupedTokens) {
        if ($Ast.Body.ParamBlock.Extent.StartLineNumber -gt $Line.Name) {
            continue
        }
        $Tokens = $Line.Group
        for ($i = 0; $i -lt $Line.Count; $i++) {
            $Token = $Tokens[$i]
            if ($Token.Extent.StartOffset -lt $Ast.Body.ParamBlock.Extent.StartOffset) {
                continue
            }

            # Lets find comments between function and param block and not remove them
            if ($Token.Extent.Text -eq 'function') {
                if (-not $RemoveCommentsBeforeParamBlock) {
                    $DoNotRemove = $true
                }
                continue
            }
            if ($Token.Extent.Text -eq 'param') {
                $ParamFound = $true
                $DoNotRemove = $false
            }
            if ($DoNotRemove) {
                continue
            }
            # lets find comments between param block and end of param block
            if ($Token.Extent.Text -eq 'param') {
                if (-not $RemoveCommentsInParamBlock) {
                    $DoNotRemoveCommentParam = $true
                }
                continue
            }
            if ($ParamFound -and ($Token.Extent.Text -eq '(' -or $Token.Extent.Text -eq '@(')) {
                $CountParams += 1
            } elseif ($ParamFound -and $Token.Extent.Text -eq ')') {
                $CountParams -= 1
            }
            if ($ParamFound -and $Token.Extent.Text -eq ')') {
                if ($CountParams -eq 0) {
                    $DoNotRemoveCommentParam = $false
                    $ParamFound = $false
                }
            }
            if ($DoNotRemoveCommentParam) {
                continue
            }
            # if token not comment we leave it as is
            if ($Token.Kind -ne 'Comment') {
                continue
            }

            # kind of useless to not remove signature block if we're not removing comments
            # this changes the structure of a file and signature will be invalid
            if ($DoNotRemoveSignatureBlock) {
                if ($Token.Kind -eq 'Comment' -and $Token.Text -eq '# SIG # Begin signature block') {
                    $SignatureBlock = $true
                    continue
                }
                if ($SignatureBlock) {
                    if ($Token.Kind -eq 'Comment' -and $Token.Text -eq '# SIG # End signature block') {
                        $SignatureBlock = $false
                    }
                    continue
                }
            }
            $Token
        }
    }
    $ToRemove = $ToRemove | Sort-Object { $_.Extent.StartOffset } -Descending
    foreach ($Token in $ToRemove) {
        $StartIndex = $Token.Extent.StartOffset
        $HowManyChars = $Token.Extent.EndOffset - $Token.Extent.StartOffset
        $Content = $Content.Remove($StartIndex, $HowManyChars)
    }
    if ($RemoveEmptyLines) {
        # Remove empty lines if more than one empty line is found. If it's just one line, leave it as is
        #$Content = $Content -replace '(?m)^\s*$', ''
        #$Content = $Content -replace "(`r?`n){2,}", "`r`n"
        # $Content = $Content -replace "(`r?`n){2,}", "`r`n`r`n"
        $Content = $Content -replace '(?m)^\s*$', ''
        $Content = $Content -replace "(?:`r?`n|\n|\r)", "`r`n"
    }
    if ($RemoveAllEmptyLines) {
        # Remove all empty lines from the content
        $Content = $Content -replace '(?m)^\s*$(\r?\n)?', ''
    }
    if ($Content) {
        $Content = $Content.Trim()
    }
    if ($DestinationFilePath) {
        $Content | Set-Content -Path $DestinationFilePath -Encoding utf8
    } else {
        $Content
    }
}


function Format-GeneralFunction {

	# variables
	$VersionPattern = "Version: .*"

	# get content from clipboard
	$Content = Get-Clipboard -Raw

	# extract version
	$Version = $Content | Select-String -Pattern $VersionPattern -AllMatches | ForEach-Object { $_.Matches.Value }
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
	$OutputLinesWithVersion = $OutputLines[0..0] + "    # ${Version}" + $OutputLines[1..$OutputLines.Length]

	# rejoin into one string
	$Output = $OutputLinesWithVersion -Join "`r`n"

	# remove double carriage returns to prevent errors
	$Output = $Output -Replace "`r`r","`r"

	# show on screen
	Write-Host -ForegroundColor Green "`nOutput:"
	Write-Output $Output

	# put output in clipboard
	Set-Clipboard $Output
}
