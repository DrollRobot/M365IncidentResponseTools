$Path = "$PSScriptRoot\..\..\Source\M365IncidentResponseTools.psd1" # source
# $Path = "$PSScriptRoot\..\..\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $Path" -ForegroundColor Green
Import-Module $Path -Force

& "$PSScriptRoot\..\.env.ps1"

Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
$InformationPreference = 'Continue'

# if (-not (Test-IRTConnection -Quiet)) {
#     Connect-IRTT -TenantId $env:IRT_TEST_TENANT_ID
# }

Set-Location ([environment]::GetFolderPath('Desktop'))

# interactive query builder
New-IRTEmailSearch

# non-interactive example
# $Params = @{
#     From    = 'sus@hacker.com'
#     Subject = 'Payroll change'
#     Start   = '5/28/26'
#     End     = '5/29/26'
# }
# New-IRTEmailSearch @Params
