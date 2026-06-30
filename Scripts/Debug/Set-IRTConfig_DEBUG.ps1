# resolve the module root so paths keep working if this folder moves
. "$PSScriptRoot\Find-ModuleRoot.ps1"
$RepoRoot = (Find-ModuleRoot -Path $PSScriptRoot).Path
$Path = "$RepoRoot\Source\M365IncidentResponseTools.psd1" # source
# $Path = "$RepoRoot\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $Path" -ForegroundColor Green
Import-Module $Path -Force

& "$RepoRoot\Tests\.env.ps1"

Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
$InformationPreference = 'Continue'

if (-not (Test-IRTConnection -Quiet)) {
    Connect-IRT -TenantId $env:IRT_TEST_TENANT_ID
}
if (($Global:IRT_UserObjects | Measure-Object).Count -eq 0) {
    Find-IRTUser $env:IRT_TEST_USER_ID
}

Set-IRTConfig
