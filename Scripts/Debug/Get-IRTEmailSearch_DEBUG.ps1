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

# if (-not (Test-IRTConnection -Quiet)) {
#     Connect-IRT -TenantId $env:IRT_TEST_TENANT_ID
# }

Set-Location ([environment]::GetFolderPath('Desktop'))

# interactive manager: pick a search, then Start / Wait / Results / Purge / Delete
Get-IRTEmailSearch

# act on a specific search directly
# Get-IRTEmailSearch -Name 'From:sus@hacker.com'

# skip Graph folder resolution in the Results view
# Get-IRTEmailSearch -ResolveFolder $false
