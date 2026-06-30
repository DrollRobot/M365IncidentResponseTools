# resolve the module root so paths keep working if this folder moves
. "$PSScriptRoot\Find-ModuleRoot.ps1"
$RepoRoot = (Find-ModuleRoot -Path $PSScriptRoot).Path
$ModulePath = "$RepoRoot\Source\M365IncidentResponseTools.psd1" # source
# $ModulePath = "$RepoRoot\M365IncidentResponseTools.psd1" # built
Write-Host "Importing from: $ModulePath" -ForegroundColor Green
Import-Module $ModulePath -Force

# debug output on
# Set-PSFConfig -FullName 'PSFramework.Message.Info.Maximum' -Value 8
# $InformationPreference = 'Continue'

# debug output off
$InformationPreference = 'SilentlyContinue'

# scan source folder
# & "$RepoRoot\Tests\Test-ExplicitModuleImport.ps1" -Path $RepoRoot -Recurse

# scan specific files
# & "$RepoRoot\Tests\Test-ExplicitModuleImport.ps1" `
#     -Path "$RepoRoot\Source\Public\Email\Get-IRTMessageTrace.ps1"
# & "$RepoRoot\Tests\Test-ExplicitModuleImport.ps1" -Path "$RepoRoot\Source\Suffix.ps1"
$CheckPath = "$RepoRoot\Source\Public\OnPremAd\Find-IRTDomainController.ps1"
& "$RepoRoot\Tests\Test-ExplicitModuleImport.ps1" -Path $CheckPath
