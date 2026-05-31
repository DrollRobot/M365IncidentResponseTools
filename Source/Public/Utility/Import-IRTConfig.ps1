function Import-IRTConfig {
    <#
    .SYNOPSIS
    Loads the current IRT configuration.

    .DESCRIPTION
    Reads the user configuration from $env:APPDATA\<ModuleName>\config.json.
    If the file does not exist, copies the template from the module root and loads it.
    The parsed config is cached in $Global:IRT_Config.

    .PARAMETER Force
    Re-read the config file even if $Global:IRT_Config is already populated.
    #>
    [Alias('ImportConfig', 'IRTConfig')]
    [CmdletBinding()]
    param(
        [switch] $Force
    )

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir = Join-Path -Path $env:APPDATA -ChildPath $ModuleName
    $ConfigPath = Join-Path -Path $ConfigDir -ChildPath 'Config.json'
    $TemplatePath = Join-Path -Path $ModuleRoot -ChildPath 'Data\ConfigTemplate.json'

    if (-not (Test-Path $ConfigPath)) {
        if (-not (Test-Path $ConfigDir)) {
            $null = New-Item -ItemType Directory -Path $ConfigDir -Force
        }
        Copy-Item -Path $TemplatePath -Destination $ConfigPath
        Write-IRT "Created default config at: $ConfigPath"
    }

    if ($Force -or -not $Global:IRT_Config) {
        $Global:IRT_Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }

    # Backfill any new keys from the template that the user's config doesn't have yet
    $Template = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json
    $Updated = $false
    foreach ($Property in $Template.PSObject.Properties) {
        if (-not ($Global:IRT_Config.PSObject.Properties.Name -contains $Property.Name)) {
            $AddParams = @{
                NotePropertyName  = $Property.Name
                NotePropertyValue = $Property.Value
            }
            $Global:IRT_Config | Add-Member @AddParams
            $Updated = $true
        }
    }
    if ($Updated) {
        $Global:IRT_Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding utf8
    }

    # Resolve null path values to their defaults (in-memory only; defaults are not written back)
    if (-not $Global:IRT_Config.TenantsSheetPath) {
        $TenantDir = Join-Path -Path $env:APPDATA -ChildPath 'M365IncidentResponseTools'
        $TenantPath = Join-Path -Path $TenantDir -ChildPath 'tenants.xlsx'
        $Global:IRT_Config.TenantsSheetPath = $TenantPath
    }
}