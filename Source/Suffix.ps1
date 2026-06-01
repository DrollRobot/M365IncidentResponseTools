# ModuleBuilder Notes: Code in this file will be appended to the built .psm1 file.

# output info stream to host
$InformationPreference = 'Continue'

# when removing module from session, restore original prompt function if it was modified
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($Global:IRT_OriginalPrompt) {
        ${function:global:prompt} = $Global:IRT_OriginalPrompt
    }
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
        # maybe this instead? md docs inconsistent:
        # https://compliance.dod.microsoft.com/powershell-liveid
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

# Load user config on module import
Import-IRTConfig

# Set the default MSAL cache path if the config does not override it.
if (-not $Global:IRT_Config.MsalCachePath) {
    $JpParams = @{
        Path                = $env:LOCALAPPDATA
        ChildPath           = 'M365IncidentResponseTools'
        AdditionalChildPath = 'IRT-Cache.bin'
    }
    $Global:IRT_Config.MsalCachePath = Join-Path @JpParams
}

# Set the default IP address CF template path when the config does not override it.
if (-not $Global:IRT_Config.IPConditionalFormattingTemplatePath) {
    $IpcftJoin = @{
        Path                = $PSScriptRoot
        ChildPath           = 'Data'
        AdditionalChildPath = 'IpAddressConditionalFormattingTemplate.xlsx'
    }
    $Global:IRT_Config.IPConditionalFormattingTemplatePath = Join-Path @IpcftJoin
}

# Check ip_info availability once at module load and cache in config.
$Global:IRT_Config.IpInfoAvailable = (Test-PythonPackage -Name 'ip_info').Present

# Load static reference data (error codes, UAL operation metadata, UAL user types).
Import-ReferenceData

# Set terminal title on module load.
Set-TerminalTitle '[IRT]'

# verbose: output module load time
if ($Global:IRT_LoadStopwatch) {
    $Global:IRT_LoadStopwatch.Stop()
    $Elapsed = $Global:IRT_LoadStopwatch.Elapsed.TotalSeconds
    Write-Verbose "Module loaded in $($Elapsed.ToString('N2'))s."
    Remove-Variable -Name 'IRT_LoadStopwatch' -Scope Global
}
