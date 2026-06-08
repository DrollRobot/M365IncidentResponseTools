$Path = "$PSScriptRoot\..\..\Source\M365IncidentResponseTools.psd1" # source
# $Path = "$PSScriptRoot\..\..\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $Path" -ForegroundColor Green
Import-Module $Path -Force

& "$PSScriptRoot\..\.env.ps1"

Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
$InformationPreference = 'Continue'

if (-not (Test-IRTConnection -Quiet)) {
    Connect-IRTT -TenantId $env:IRT_TEST_TENANT_ID
}
if (($Global:IRT_ServicePrincipalObjects | Measure-Object).Count -eq 0) {
    Find-IRTServicePrincipal 'Microsoft Graph'
}

Show-IRTServicePrincipal
