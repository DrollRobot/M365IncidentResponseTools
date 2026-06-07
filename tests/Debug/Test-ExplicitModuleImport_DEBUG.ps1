$ModulePath = "$PSScriptRoot\..\..\Source\M365IncidentResponseTools.psd1" # source
# $ModulePath = "$PSScriptRoot\..\..\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $ModulePath" -ForegroundColor Green
Import-Module $ModulePath -Force

# debug output on
# Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
# $InformationPreference = 'Continue'

# debug output off
$InformationPreference = 'SilentlyContinue'

# scan source folder
# . "$PSScriptRoot\..\Dev\Find-ModuleRoot.ps1"
# $ModuleRoot = (Find-ModuleRoot -Path $PSScriptRoot).Path
# & "$PSScriptRoot\..\Test-ExplicitModuleImport.ps1" -Path $ModuleRoot -Recurse

# scan specific files
# & "$PSScriptRoot\..\Test-ExplicitModuleImport.ps1" `
#     -Path "$PSScriptRoot\..\..\Source\Public\Email\Get-IRTMessageTrace.ps1"
# & "$PSScriptRoot\..\Test-ExplicitModuleImport.ps1" -Path "$PSScriptRoot\..\..\Source\Suffix.ps1"
$CheckPath = "$PSScriptRoot\..\..\Source\Public\OnPremAd\Find-IRTDomainController.ps1"
& "$PSScriptRoot\..\Test-ExplicitModuleImport.ps1" -Path $CheckPath
