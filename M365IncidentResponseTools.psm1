
# output info stream to host
$InformationPreference = 'Continue'

# when removing module from session, restore original prompt function if it was modified
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($Global:IRT_OriginalPrompt) {
        ${function:global:prompt} = $Global:IRT_OriginalPrompt
    }
}

# Load user config on module import
Import-IRTConfig

# dot-source all module scripts
$Folders = @(
    "$PSScriptRoot\connect"
    "$PSScriptRoot\devices"
    "$PSScriptRoot\entra_logs"
    "$PSScriptRoot\mailbox"
    "$PSScriptRoot\message_trace"
    "$PSScriptRoot\modules"
    "$PSScriptRoot\onprem_ad"
    "$PSScriptRoot\roles"
    "$PSScriptRoot\service_principals"
    "$PSScriptRoot\unified_audit_log"
    "$PSScriptRoot\users"
)
# Excluded: module_init/ (not meant to be run in script scope)
# Excluded: debug/ (dev-only scripts, not exported functions)
$ExcludeFiles = @(
    'Install-Dependencies.ps1'
)
foreach ($Folder in $Folders) {
    Get-ChildItem -Path $Folder -Filter "*.ps1" -Recurse |
        Where-Object { $_.Name -notin $ExcludeFiles } |
        ForEach-Object { . $_.FullName }
}
