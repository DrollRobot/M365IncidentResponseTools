function Write-NameValue([string]$Name, [string]$ValueText, [int]$CurrentDepth, [int]$Size) {
    $Indent = Get-Indent $CurrentDepth $Size
    $PlainPrefix = $Indent + $Name + ': '
    $ContIndent = ' ' * ($PlainPrefix.Length)
    $Lines = [regex]::Split($ValueText, '(?:\r\n|\n|\r)')
    if ($Lines.Count -eq 0) { $Lines = @('') }

    if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSStyle) {
        $First = $Indent + $PSStyle.Foreground.BrightGreen + $Name +
        $PSStyle.Reset + ': ' + $Lines[0]
        Write-Host $First
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            Write-Host ($ContIndent + $Lines[$i])
        }
    } else {
        Write-Host @Green ($PlainPrefix + $Lines[0])
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            Write-Host ($ContIndent + $Lines[$i])
        }
    }
}