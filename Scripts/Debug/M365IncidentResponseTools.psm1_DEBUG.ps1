# resolve the module root so paths keep working if this folder moves
. "$PSScriptRoot\Find-ModuleRoot.ps1"
$RepoRoot = (Find-ModuleRoot -Path $PSScriptRoot).Path

Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
$InformationPreference = 'Continue'

& "$RepoRoot\Tests\.env.ps1"

$Path = "$RepoRoot\Source\M365IncidentResponseTools.psd1" # source
# $Path = "$RepoRoot\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $Path" -ForegroundColor Green
Import-Module $Path -Force

