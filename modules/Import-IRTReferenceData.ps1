function Import-IRTReferenceData {
    <#
    .SYNOPSIS
    Loads static reference data files into module global variables.

    .DESCRIPTION
    Reads the three bundled data files into globals used by sign-in log, unified audit log,
    and other functions. Called automatically at module import.

    Call this manually after editing any of the data files to pick up changes without
    reloading the entire module.

    Globals populated:
      $Global:IRT_EntraErrorTable   - Hashtable[int -> row] from entra_error_codes.csv
      $Global:IRT_UalOperationsData - Array of rows from unified_audit_log-all_operations.xlsx
      $Global:IRT_UalUserTypeTable  - Hashtable[int -> 'UserType member name'] from unified_audit_log-user_type.csv
      $Global:IRT_TenantInfoTable   - Hashtable[TenantId -> row] from APPDATA\<ModuleName>\tenant_owner_info.csv

    The AllOperations path can be overridden by setting AllOperationsSheetPath in config.json.

    .EXAMPLE
    Import-IRTReferenceData
    Re-reads all reference data files. Use after editing entra_error_codes.csv, the AllOperations
    workbook, unified_audit_log-user_type.csv, or tenant_owner_info.csv.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase

    # Entra ID sign-in error codes (int-keyed synchronized hashtable for runspace safety)
    $EntraErrorPath = Join-Path $ModuleRoot 'data\entra_error_codes.csv'
    $EntraTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $EntraErrorPath)) {
        $EntraTable[[int]$Row.Error] = $Row
    }
    $Global:IRT_EntraErrorTable = $EntraTable

    # UAL operation risk metadata (xlsx, path configurable via IRT_Config.AllOperationsSheetPath)
    $AllOperationsFileName = 'unified_audit_log-all_operations.xlsx'
    $AllOperationsConfig = $Global:IRT_Config.AllOperationsSheetPath
    $AllOperationsPath = if ($AllOperationsConfig) {
        $AllOperationsConfig
    } else {
        Join-Path $ModuleRoot "data\${AllOperationsFileName}"
    }
    if (Test-Path -LiteralPath $AllOperationsPath) {
        $Global:IRT_UalOperationsData = @(Import-Excel -Path $AllOperationsPath -WorksheetName 'Operations')
    } else {
        $Global:IRT_UalOperationsData = @()
        Write-Warning "Import-IRTReferenceData: AllOperations sheet not found at: $AllOperationsPath"
    }

    # UAL user type lookup
    $UserTypePath = Join-Path $ModuleRoot 'data\unified_audit_log-user_type.csv'
    $UserTypeTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $UserTypePath)) {
        $UserTypeTable[[int]$Row.Value] = $Row.'UserType member name'
    }
    $Global:IRT_UalUserTypeTable = $UserTypeTable

    # Tenant owner info cache (keyed by TenantId GUID string)
    $ModuleName = $MyInvocation.MyCommand.ModuleName
    $TenantCachePath = Join-Path $env:APPDATA $ModuleName 'tenant_owner_info.csv'
    $TenantTable = [hashtable]::Synchronized(@{})
    if (Test-Path -LiteralPath $TenantCachePath) {
        foreach ($Row in (Import-Csv -Path $TenantCachePath)) {
            $TenantTable[$Row.TenantId] = $Row
        }
    }
    $Global:IRT_TenantInfoTable = $TenantTable
}
