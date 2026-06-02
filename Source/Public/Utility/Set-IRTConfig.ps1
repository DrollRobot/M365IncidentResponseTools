function Set-IRTConfig {
    <#
    .SYNOPSIS
    Interactively updates IRT configuration settings.

    .DESCRIPTION
    Presents a menu of configuration settings. When the user selects a setting,
    shows a description and available options, then saves the new value.

    .PARAMETER Reset
    Reset config to the template defaults without showing the menu.

    # FIXME paths that have not been explicitly set should show 'default',
    # not the default path. Maybe?
    # FIXME why some stuff in appdata/local and some in roaming?
    #>
    [Alias('SetIRTConfig', 'Set-IRTConfigs', 'SetIRTConfigs')]
    [Alias('Set-Config', 'SetConfig', 'Set-Configs', 'SetConfigs')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $Reset
    )

    $ModuleName = $MyInvocation.MyCommand.Module.Name
    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
    $ConfigDir = Join-Path -Path $env:APPDATA -ChildPath $ModuleName
    $ConfigPath = Join-Path -Path $ConfigDir -ChildPath 'config.json'
    $TplJoin = @{
        Path                = $ModuleRoot
        ChildPath           = 'Data'
        AdditionalChildPath = 'ConfigTemplate.json'
    }
    $TemplatePath = Join-Path @TplJoin

    if ($Reset) {
        if ($PSCmdlet.ShouldProcess($ConfigPath, 'Reset to template defaults')) {
            if (-not (Test-Path $ConfigDir)) {
                $null = New-Item -ItemType Directory -Path $ConfigDir -Force
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
            Description = 'Which browser to use when opening OWA links and ' +
            'other web pages. (where possible) ' +
            'Set to "default" to use the system default browser.'
            Options     = @('default', 'msedge', 'chrome', 'firefox', 'brave')
        }
        ExcelTableStyle = @{
            Summary     = 'Excel table style'
            Description = 'The table style applied to Excel worksheets exported by IRT. ' +
            'Uses ImportExcel style names (e.g. Dark1-Dark11, ' +
            'Medium1-Medium28, Light1-Light21).'
            Options     = @(
                'Dark1', 'Dark2', 'Dark3', 'Dark4', 'Dark5', 'Dark6',
                'Dark7', 'Dark8', 'Dark9', 'Dark10', 'Dark11',
                'Medium1', 'Medium2', 'Medium3', 'Medium4', 'Medium5', 'Medium6', 'Medium7',
                'Light1', 'Light2', 'Light3', 'Light4', 'Light5', 'Light6', 'Light7'
            )
        }
        ExcelFont = @{
            Summary     = 'Excel font name'
            Description = 'The font used across all Excel output. ' +
            'Monospace fonts like Consolas work best for log data. ' +
            'Enter any font name installed on your system.'
            Options     = $null  # free text
        }
        ExportXml = @{
            Summary     = 'Export raw XML with log pulls'
            Description = 'When enabled, log commands ' +
            '(sign-in logs, UAL, message trace) will save ' +
            'the raw XML response alongside the parsed Excel output.'
            Options     = @('true', 'false')
        }
        AllOperationsSheetPath = @{
            Summary     = 'All Operations sheet path'
            Description = 'Path to the UALAllOperations.xlsx file ' +
            'used for operation lookups. ' +
            'Leave blank (null) to use the default file bundled with the module. ' +
            'Set to an absolute path to use a custom file outside the module.'
            Options     = $null  # free text / file path
        }
        TenantsSheetPath = @{
            Summary     = 'Tenants worksheet path'
            Description = 'Path to the tenants.xlsx file used by Connect-IRTTenant. ' +
            'Leave blank (null) to use the default location: ' +
            '$env:APPDATA\M365IncidentResponseTools\tenants.xlsx. ' +
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
            Description = 'Maximum number of concurrent Exchange Online connections. ' +
            '(Recommend 10 or lower: https://techcommunity.microsoft.com/blog/exchange/' +
            'more-efficient-bulk-operations-with-powershell-parallelism/4409693)'
            Options     = $null  # free text / integer
        }
        PromptColor = @{
            Summary     = 'Prompt color'
            Description = 'Foreground color used for the IRT prompt labels ' +
            '(e.g. "[IRT]", "Graph:", "Exchange:").'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        InfoColor = @{
            Summary     = 'Informational message color'
            Description = 'Foreground color used for informational messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        WarnColor = @{
            Summary     = 'Warning message color'
            Description = 'Foreground color used for warning messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        ErrorColor = @{
            Summary     = 'Error message color'
            Description = 'Foreground color used for error messages throughout IRT.'
            Options     = @(
                'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta',
                'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan',
                'Red', 'Magenta', 'Yellow', 'White'
            )
        }
        EnableTokenCache = @{
            Summary         = 'Persistent MSAL token cache'
            Description     = 'When enabled, refresh tokens are written to an ' +
            'encrypted file on disk, so Connect-IRT skips the browser prompt ' +
            'across PowerShell sessions (up to ~90 days, until the refresh token ' +
            'expires or is revoked). On first use, the required ' +
            'Microsoft.Identity.Client.Extensions.Msal DLL is downloaded from ' +
            'nuget.org. Run Clear-IRTTokenCache to wipe the cache.'
            SecurityWarning = 'SECURITY WARNING: The cache file is DPAPI-encrypted and ' +
            'bound to your Windows user account, but any process running as that ' +
            'user can decrypt it. Do not enable this on shared or multi-user ' +
            'machines. Always run Clear-IRTTokenCache when you finish an investigation.'
            Options         = @('true', 'false')
        }
        MsalCachePath = @{
            Summary     = 'MSAL token cache file path'
            Description = 'Absolute path for the DPAPI-encrypted MSAL token cache file. ' +
            'Leave blank (null) to use the default path set in ' +
            'M365IncidentResponseTools.psm1. ' +
            'Override to an isolated path for testing or multi-instance scenarios. ' +
            'Takes effect on the next Connect-IRT call.'
            Options     = $null  # free text / file path
        }
        IPConditionalFormattingTemplatePath = @{
            Summary     = 'IP address CF template path'
            Description = 'Absolute path to an Excel file whose first sheet A columncontains the ' +
            'conditional-formatting rules to apply to IP address columns. ' +
            'Leave blank (null) to use the default template bundled with the module ' +
            '(Data/IpAddressConditionalFormattingTemplate.xlsx). ' +
            'Replace with a custom file to change color-coding without editing code.'
            Options     = $null  # free text / file path
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
                String = "$($Settings[$Key].Summary.PadRight(22)) $('='.PadLeft(2)) $CurrentVal"
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

        Write-IRT ''
        Write-IRT $Setting.Description
        if ($Setting.SecurityWarning) {
            Write-IRT ''
            Write-IRT $Setting.SecurityWarning -Level Error
        }
        Write-IRT "Current value: $CurrentVal"
        Write-IRT ''

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

        # Convert string to bool for boolean settings
        if ($SelectedKey -in 'ExportXml', 'EnableTokenCache') {
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
