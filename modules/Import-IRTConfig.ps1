#region Import-IRTConfig
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

    $ModuleName   = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot   = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir    = Join-Path $env:APPDATA $ModuleName
    $ConfigPath   = Join-Path $ConfigDir 'config.json'
    $TemplatePath = Join-Path $ModuleRoot 'module_init' 'config_TEMPLATE.json'

    if (-not (Test-Path $ConfigPath)) {
        if (-not (Test-Path $ConfigDir)) {
            New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
        }
        Copy-Item -Path $TemplatePath -Destination $ConfigPath
        Write-IRT "Created default config at: $ConfigPath"
    }

    if ($Force -or -not $Global:IRT_Config) {
        $Global:IRT_Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }

    # Backfill any new keys from the template that the user's config doesn't have yet
    $Template = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json
    $Updated  = $false
    foreach ($Property in $Template.PSObject.Properties) {
        if (-not ($Global:IRT_Config.PSObject.Properties.Name -contains $Property.Name)) {
            $Global:IRT_Config | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value
            $Updated = $true
        }
    }
    if ($Updated) {
        $Global:IRT_Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding utf8
    }
}


#region Open-IRTConfig
function Open-IRTConfig {
    <#
    .SYNOPSIS
    Opens the IRT config.json file for editing.
    #>
    [Alias('OpenConfig')]
    [CmdletBinding()]
    param()

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $ConfigPath = Join-Path $env:APPDATA $ModuleName 'config.json'

    if (-not (Test-Path $ConfigPath)) {
        Import-IRTConfig
    }

    Invoke-Item $ConfigPath
}


#region Set-IRTConfig
function Set-IRTConfig {
    <#
    .SYNOPSIS
    Interactively updates IRT configuration settings.

    .DESCRIPTION
    Presents a menu of configuration settings. When the user selects a setting,
    shows a description and available options, then saves the new value.

    .PARAMETER Reset
    Reset config to the template defaults without showing the menu.
    #>
    [Alias('SetConfig')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $Reset
    )

    $ModuleName   = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot   = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir    = Join-Path $env:APPDATA $ModuleName
    $ConfigPath   = Join-Path $ConfigDir 'config.json'
    $TemplatePath = Join-Path $ModuleRoot 'module_init' 'config_TEMPLATE.json'

    if ($Reset) {
        if ($PSCmdlet.ShouldProcess($ConfigPath, 'Reset to template defaults')) {
            if (-not (Test-Path $ConfigDir)) {
                New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
            }
            Copy-Item -Path $TemplatePath -Destination $ConfigPath -Force
            $Global:IRT_Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            Write-IRT "Config reset to defaults."
            return
        }
        return
    }

    Import-IRTConfig
    $Config = $Global:IRT_Config

    # define settings metadata
    $Settings = [ordered]@{
        PasswordBrowser = @{
            Summary     = 'Browser for opening password URLs in Tenants CSV'
            Description = 'Which browser to use when opening password URLs from the Tenants CSV. ' +
                          'Set to "default" to use the system default browser.'
            Options     = @('default', 'msedge', 'chrome', 'firefox', 'brave')
        }
        Browser = @{
            Summary     = 'Browser for opening other URLs'
            Description = 'Which browser to use when opening device code prompts, OWA links, and other web pages. (where possible)' +
                          'Set to "default" to use the system default browser.'
            Options     = @('default', 'msedge', 'chrome', 'firefox', 'brave')
        }
        ExcelTableStyle = @{
            Summary     = 'Excel table style'
            Description = 'The table style applied to Excel worksheets exported by IRT. ' +
                          'Uses ImportExcel style names (e.g. Dark1-Dark11, Medium1-Medium28, Light1-Light21).'
            Options     = @(
                'Dark1','Dark2','Dark3','Dark4','Dark5','Dark6','Dark7','Dark8','Dark9','Dark10','Dark11',
                'Medium1','Medium2','Medium3','Medium4','Medium5','Medium6','Medium7',
                'Light1','Light2','Light3','Light4','Light5','Light6','Light7'
            )
        }
        ExcelFont = @{
            Summary     = 'Excel font name'
            Description = 'The font used across all Excel output. Monospace fonts like Consolas work best for log data. ' +
                'Enter any font name installed on your system.'
            Options     = $null  # free text
        }
        ExportXml = @{
            Summary     = 'Export raw XML with log pulls'
            Description = 'When enabled, log commands (sign-in logs, UAL, message trace) will save ' +
                'the raw XML response alongside the parsed Excel output.'
            Options     = @('true', 'false')
        }
        AllOperationsSheetPath = @{
            Summary     = 'All Operations sheet path'
            Description = 'Path to the unified_audit_log-all_operations.xlsx file used for operation lookups. ' +
                'Leave blank (null) to use the default file bundled with the module. Set to an absolute path to ' +
                'use a custom file outside the module.'
            Options     = $null  # free text / file path
        }
        TenantsSheetPath = @{
            Summary     = 'Tenants worksheet path'
            Description = 'Path to the tenants.xlsx file used by Connect-IRTTenant. ' +
                'Leave blank (null) to use the default location: $env:APPDATA\M365IncidentResponseTools\tenants.xlsx. ' +
                'Set to an absolute path to use a custom file.'
            Options     = $null  # free text / file path
        }
        MaxRunspaces = @{
            Summary     = 'Maximum runspaces for parallel operations'
            Description = 'Maximum number of runspaces used for parallel processing.'
            Options     = $null  # free text / integer
        }
        MaxExchangeConnections = @{
            Summary     = 'Maximum concurrent Exchange connections'
            Description = 'Maximum number of concurrent Exchange Online connections. (Recommend 10 or lower:' +
                'https://techcommunity.microsoft.com/blog/exchange/more-efficient-bulk-operations-with-powershell-parallelism/4409693)'
            Options     = $null  # free text / integer
        }
        PromptColor = @{
            Summary     = 'Prompt color'
            Description = 'Foreground color used for the IRT prompt labels (e.g. "[IRT]", "Graph:", "Exchange:").'
            Options     = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
        }
        InfoColor = @{
            Summary     = 'Informational message color'
            Description = 'Foreground color used for informational messages throughout IRT.'
            Options     = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
        }
        WarnColor = @{
            Summary     = 'Warning message color'
            Description = 'Foreground color used for warning messages throughout IRT.'
            Options     = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
        }
        ErrorColor = @{
            Summary     = 'Error message color'
            Description = 'Foreground color used for error messages throughout IRT.'
            Options     = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
        }
    }

    # main menu loop
    while ($true) {
        $MenuOptions = [ordered]@{}
        $KeyMap = [ordered]@{}
        $i = 1
        foreach ($Key in $Settings.Keys) {
            $CurrentVal = $Config.$Key
            $MenuOptions["$i"] = @{
                String = "{0,-22} {1,2} {2}" -f $Settings[$Key].Summary, '=', $CurrentVal
                Color  = 'White'
            }
            $KeyMap["$i"] = $Key
            $i++
        }
        $MenuOptions["$i"] = @{ String = 'Reset to defaults'; Color = 'Yellow' }
        $ResetIndex = "$i"
        $i++
        $MenuOptions["$i"] = @{ String = 'Done'; Color = 'Green' }
        $DoneIndex = "$i"

        $Choice = Build-Menu -Options $MenuOptions -Title 'IRT Configuration' -List

        if ($Choice -eq $MenuOptions[$DoneIndex].String) {
            break
        }

        if ($Choice -eq $MenuOptions[$ResetIndex].String) {
            Set-IRTConfig -Reset
            $Config = $Global:IRT_Config
            continue
        }

        # Find which setting was selected
        $SelectedKey = $null
        foreach ($mi in $KeyMap.Keys) {
            if ($Choice -eq $MenuOptions[$mi].String) {
                $SelectedKey = $KeyMap[$mi]
                break
            }
        }
        if (-not $SelectedKey) { continue }

        $Setting = $Settings[$SelectedKey]
        $CurrentVal = $Config.$SelectedKey

        Write-Host ''
        Write-IRT $Setting.Description
        Write-IRT "Current value: $CurrentVal"
        Write-Host ''

        if ($Setting.Options) {
            # Build a selection menu from predefined options
            $NewValue = Build-Menu -Options $Setting.Options -Title 'Select a value:' -List
        }
        else {
            # Free text input; for path settings blank clears back to null (restores default)
            if ($SelectedKey -in 'AllOperationsSheetPath', 'TenantsSheetPath') {
                $NewValue = Read-Host "Enter new value (blank to clear and use module default)"
            }
            else {
                $NewValue = Read-Host "Enter new value (blank to keep current)"
                if ([string]::IsNullOrWhiteSpace($NewValue)) {
                    Write-IRT "Keeping current value: $CurrentVal"
                    continue
                }
            }
        }

        # Convert blank/null path settings back to null
        if ($SelectedKey -in 'AllOperationsSheetPath', 'TenantsSheetPath') {
            if ([string]::IsNullOrWhiteSpace($NewValue)) { $NewValue = $null }
        }

        # Convert string to bool for ExportXml
        if ($SelectedKey -eq 'ExportXml') {
            $NewValue = $NewValue -eq 'true'
        }

        # Convert string to int for integer settings
        if ($SelectedKey -in 'MaxRunspaces', 'MaxExchangeConnections') {
            $NewValue = [int]$NewValue
        }

        $Config.$SelectedKey = $NewValue

        if ($PSCmdlet.ShouldProcess($ConfigPath, "Set $SelectedKey = $NewValue")) {
            $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding utf8
            $Global:IRT_Config = $Config
            Write-IRT "$SelectedKey updated to: $NewValue"
        }
    }
}

