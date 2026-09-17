<#
.SYNOPSIS
    Writes the module banner to the host.

    Set environmment variable $Global:IRT_Banner = $false  to suppress.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param()

$BannerVar = Get-Variable -Name 'IRT_Banner' -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $BannerVar -or $BannerVar.Value -ne $false) {

    # ScriptsToProcess runs in the caller's scope before the module is imported, so there is
    # no module object to read the version from. Read the manifest directly instead. It sits
    # one level up in both the source and built layouts. Best effort -- if it can't be read,
    # the banner just omits the version.
    $Version = $null
    $ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\M365IncidentResponseTools.psd1'
    try {
        $Manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath -ErrorAction Stop
        $Version = $Manifest.ModuleVersion
    }
    catch {
        $Version = $null
    }

    $Title = 'M365IncidentResponseTools'
    if ($Version) {
        $Title += " v$Version"
    }

    Write-Host $Title -ForegroundColor Blue
    Write-Host ""
    Write-Host "Documentation at:"
    Write-Host "https://drollrobot.github.io/M365IncidentResponseTools/"
    Write-Host ""
    Write-Host "Report bugs or contribute on GitHub:"
    Write-Host "https://github.com/DrollRobot/M365IncidentResponseTools"
    Write-Host ""
    Write-Host "Module loading..."
    Write-Host ""

}

# suppress banner after first load
$Global:IRT_Banner = $false
