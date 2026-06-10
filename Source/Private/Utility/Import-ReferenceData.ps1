function Import-ReferenceData {
    <#
    .SYNOPSIS
    Loads static reference data files into module global variables.

    .DESCRIPTION
    Reads the three bundled data files into globals used by sign-in log, unified audit log,
    and other functions. Called automatically at module import.

    Call this manually after editing any of the data files to pick up changes without
    reloading the entire module.

    Globals populated:
      $Global:IRT_EntraErrorTable   - Hashtable[int -> row] from EntraErrorCodes.csv
      $Global:IRT_UalOperationsData - Array of rows from UALAllOperations.xlsx
      $Global:IRT_UalUserTypeTable  - Hashtable[int -> 'UserType member name']
        from UALUserType.csv
      $Global:IRT_TenantInfoTable   - Hashtable[TenantId -> row]
        from APPDATA\<ModuleName>\TenantOwnerInfo.csv

    The AllOperations path can be overridden by setting AllOperationsSheetPath in config.json.

    .EXAMPLE
    Import-ReferenceData
    Re-reads all reference data files. Use after editing EntraErrorCodes.csv, the AllOperations
    workbook, UALUserType.csv, or TenantOwnerInfo.csv.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    Import-IRTModule -Name 'ImportExcel', 'PSFramework'

    $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase

    # Entra ID sign-in error codes (int-keyed synchronized hashtable for runspace safety)
    $EntraErrorPath = Join-Path -Path $ModuleRoot -ChildPath 'Data\EntraErrorCodes.csv'
    $EntraTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $EntraErrorPath)) {
        $EntraTable[[int]$Row.Error] = $Row
    }
    $Global:IRT_EntraErrorTable = $EntraTable

    # UAL operation risk metadata (xlsx, path configurable via IRT_Config.AllOperationsSheetPath)
    $AllOperationsPath = $Global:IRT_Config.AllOperationsSheetPath
    if (-not $AllOperationsPath) {
        $AopsJoin = @{
            Path      = $ModuleRoot
            ChildPath = 'Data\UALAllOperations.xlsx'
        }
        $AllOperationsPath = Join-Path @AopsJoin
        $Global:IRT_Config.AllOperationsSheetPath = $AllOperationsPath
    }
    if (Test-Path -LiteralPath $AllOperationsPath) {
        $IeParams = @{
            Path          = $AllOperationsPath
            WorksheetName = 'Operations'
        }
        $Global:IRT_UalOperationsData = @(Import-Excel @IeParams)
        Write-PSFMessage -Level 8 -Message (
            "Import-ReferenceData: Loaded $($Global:IRT_UalOperationsData.Count) " +
            "UAL operation(s) from '$AllOperationsPath'.")
    } else {
        $Global:IRT_UalOperationsData = @()
        Write-PSFMessage -Level Warning -Message (
            'Import-ReferenceData: AllOperations sheet not found at: ' +
            $AllOperationsPath)
    }

    # UAL user type lookup
    $UserTypePath = Join-Path -Path $ModuleRoot -ChildPath 'Data\UALUserType.csv'
    $UserTypeTable = [hashtable]::Synchronized(@{})
    foreach ($Row in (Import-Csv -Path $UserTypePath)) {
        $UserTypeTable[[int]$Row.Value] = $Row.'UserType member name'
    }
    $Global:IRT_UalUserTypeTable = $UserTypeTable

    # Tenant owner info cache (keyed by TenantId GUID string)
    $ModuleName = $MyInvocation.MyCommand.ModuleName
    $TcJoin = @{
        Path                = $env:APPDATA
        ChildPath           = $ModuleName
        AdditionalChildPath = 'TenantOwnerInfo.csv'
    }
    $TenantCachePath = Join-Path @TcJoin
    $TenantTable = [hashtable]::Synchronized(@{})
    if (Test-Path -LiteralPath $TenantCachePath) {
        foreach ($Row in (Import-Csv -Path $TenantCachePath)) {
            $TenantTable[$Row.TenantId] = $Row
        }
    }
    $Global:IRT_TenantInfoTable = $TenantTable
    Write-PSFMessage -Level 8 -Message (
        "Import-ReferenceData: Complete - " +
        "EntraErrors=$($Global:IRT_EntraErrorTable.Count), " +
        "UalOps=$($Global:IRT_UalOperationsData.Count), " +
        "UserTypes=$($Global:IRT_UalUserTypeTable.Count), " +
        "TenantCache=$($Global:IRT_TenantInfoTable.Count)")
}
