
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

# Initialize shared global caches as synchronized hashtables.
# Using Synchronized everywhere costs nothing measurable and is safe for runspace sharing.
# Existing data is preserved on module re-import (-Force).
foreach ($VarName in 'IRT_IpInfo', 'IRT_MessageTraceTable') {
    $Current = Get-Variable -Name $VarName -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if (-not ($Current -is [hashtable] -and $Current.IsSynchronized)) {
        $Existing = if ($Current -is [hashtable]) { $Current } else { @{} }
        Set-Variable -Name $VarName -Scope Global -Value ([hashtable]::Synchronized($Existing))
    }
}

# Cloud endpoint definitions used by OIDC probing and all Connect-IRT* functions.
# Ordered so OIDC probing tries Commercial first, then USGov, then China.
$Global:IRT_CloudEnvironments = [ordered]@{
    Commercial = @{
        LoginHost      = 'https://login.microsoftonline.com'
        Graph          = 'https://graph.microsoft.com'
        GraphEnv       = 'Global'
        Exchange       = 'https://outlook.office365.com/.default'
        ExchangeEnv    = 'O365Default'
        IPPS           = 'https://ps.compliance.protection.outlook.com/powershell-liveid/'
        IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
    }
    USGov      = @{
        LoginHost      = 'https://login.microsoftonline.us'
        Graph          = 'https://graph.microsoft.us'
        GraphEnv       = 'USGov'
        Exchange       = 'https://outlook.office365.us/.default'
        ExchangeEnv    = 'O365USGovGCCHigh'
        IPPS           = 'https://ps.compliance.protection.office365.us/powershell-liveid/'
        IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
    }
    USGovDoD   = @{
        LoginHost      = 'https://login.microsoftonline.us'
        Graph          = 'https://dod-graph.microsoft.us'
        GraphEnv       = 'USGovDoD'
        Exchange       = 'https://outlook-dod.office365.us/.default'
        ExchangeEnv    = 'O365USGovDoD'
        IPPS           = 'https://l5.ps.compliance.protection.office365.us/powershell-liveid/'
        # maybe this instead? md docs inconsistent: https://compliance.dod.microsoft.com/powershell-liveid
        IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
    }
    China      = @{
        LoginHost      = 'https://login.chinacloudapi.cn'
        Graph          = 'https://microsoftgraph.chinacloudapi.cn'
        GraphEnv       = 'China'
        Exchange       = 'https://partner.outlook.cn/.default'
        ExchangeEnv    = 'O365China'
        IPPS           = 'https://ps.compliance.protection.partner.outlook.cn/powershell-liveid'
        IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
    }
}

# Check ip_info availability once at module load and cache in config.
$Global:IRT_Config | Add-Member @{
    NotePropertyName  = 'IpInfoAvailable'
    NotePropertyValue = (Test-PythonPackage -Name 'ip_info').Present
} -Force

# Load static reference data (error codes, UAL operation metadata, UAL user types).
Import-IRTReferenceData
