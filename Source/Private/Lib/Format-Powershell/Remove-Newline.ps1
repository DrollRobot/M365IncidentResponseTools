function Remove-Newline {
    <#
	.SYNOPSIS
	Remove unnecessary newlines from Powershell code.

	.EXAMPLE


	.NOTES
		Version: 1.0.0
	#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param (
        [string] $Content
    )

    process {

        # remove newlines before else, elseif, catch, finally
        $ElsePattern = "\}\s*(?:\r?\n\s*#.*\r?\n)?\s*(else|elseif|catch|finally)\s*([\{\(])"
        $ElseReplace = '} $1 $2'
        $Content = $Content -replace $ElsePattern, $ElseReplace

        # remove newlines after logical operators
        $LogicalPattern = "-(and|or|xor|not)\s*\n\s*"
        $LogicalReplace = '-$1 '
        $Content = $Content -replace $LogicalPattern, $LogicalReplace

        # remove newlines before/after pipes
        $PipePattern = "\s*\|\s*"
        $PipeReplace = "|"
        $Content = $Content -replace $PipePattern, $PipeReplace

        # remove newline from parameters
        $ParamNames = "Alias|CmdletBinding|Parameter|ValidateScript|ValidateSet|ValidateRange"
        $CmdletBindingPattern = "(\[(${ParamNames})\((.*?)\)])\s*\n\s*"
        $CmdletBindingReplace = '$1 '
        $Content = $Content -replace $CmdletBindingPattern, $CmdletBindingReplace

        # remove newlines after commas
        $CommaPattern = ",\s*\n\s*"
        $CommaReplace = ', '
        $Content = $Content -replace $CommaPattern, $CommaReplace

        # remove newlines after opening parenthesis/brackets
        $OpenPattern = "([\(\{])\s*"
        $OpenReplace = '$1'
        $Content = $Content -replace $OpenPattern, $OpenReplace

        # remove newlines before closing parenthesis/brackets
        $ClosePattern = "\s*([\)\}])"
        $CloseReplace = '$1'
        $Content = $Content -replace $ClosePattern, $CloseReplace

        # remove newlines, replace with semicolons. must be last
        $Content = $Content -replace '\n', ';'

        return $Content
    }
}