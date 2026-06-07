$Path = "$PSScriptRoot\..\..\Source\M365IncidentResponseTools.psd1" # source
# $Path = "$PSScriptRoot\..\..\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $Path" -ForegroundColor Green
Import-Module $Path -Force

& "$PSScriptRoot\..\.env.ps1"

# debug output on
# Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
# $InformationPreference = 'Continue'

# debug output off
$InformationPreference = 'SilentlyContinue'

# Clear-IRTCache
# Connect-IRT -TenantId $env:IRT_TEST_TENANT_ID

. "$PSScriptRoot\..\Dev\Get-MsalCacheStats.ps1"
$ExcludeProps = 'TenantId', 'AccountObjectId', 'CloudEnvironment', 'FailureReason'
Get-MsalCacheStats | Select-Object * -ExcludeProperty $ExcludeProps | Format-Table -AutoSize
