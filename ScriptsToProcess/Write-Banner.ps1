<#
.SYNOPSIS
    Writes the module banner to the host.

    Set environmment variable $Global:IRT_Banner = $false  to suppress.
#>



$BannerVar = Get-Variable -Name 'IRT_Banner' -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $BannerVar -or $BannerVar.Value -ne $false) {

    Write-Host "M365IncidentResponseTools" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Report bugs or contribute on GitHub:"
    Write-Host "https://github.com/DrollRobot/M365IncidentResponseTools"
    Write-Host ""
    Write-Host "Module loading..."
    Write-Host ""

}

# suppress banner after first load
$Global:IRT_Banner = $false
