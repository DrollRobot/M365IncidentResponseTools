<#
.SYNOPSIS
    Writes the module banner to the host.

    Set environmment variable $Global:IRT_Banner = $false  to suppress.
#>

$BannerVar = Get-Variable -Name 'IRT_Banner' -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $BannerVar -or $BannerVar.Value -ne $false) {

Write-Host @"

M365IncidentResponseTools

Report bugs or contribute on GitHub:
https://github.com/DrollRobot/M365IncidentResponseTools

Module loading...

"@

}

# suppress banner after first load
$Global:IRT_Banner = $false
