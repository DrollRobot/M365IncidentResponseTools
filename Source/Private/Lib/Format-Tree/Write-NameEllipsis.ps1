function Write-NameEllipsis([string]$Name, [int]$CurrentDepth, [int]$Size) {
    $indent = Get-Indent $CurrentDepth $Size
    Write-Host -NoNewline $indent
    Write-Host -NoNewline @Green ($Name + ': ')
    Write-Host @Red '...'
}