#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for New-TenantSheet.

.DESCRIPTION
    New-TenantSheet generates the tenants worksheet that Connect-IRTTenant reads. It
    replaced a bundled TenantsTemplate.xlsx, so these tests pin the column layout that
    used to live in that file: renaming or reordering a column here is a breaking change
    for every existing user worksheet.

    All tests write disposable workbooks under the temp directory. No network calls are
    made. ImportExcel must be available; it is loaded when tests.ps1 imports the module
    manifest.

-- guard rails (unit) ----------------------------------------------------

    'throws when the worksheet already exists'
        The function must never clobber a user's populated tenant list.

    'does not call Export-Excel when the file already exists'
        The throw must happen before any write is attempted.

    'writes nothing under -WhatIf'
        ShouldProcess must gate both the directory creation and the workbook write.

-- generated workbook (integration) --------------------------------------

    'creates the workbook file'
    'creates the parent directory when it does not exist'
        First run happens against a fresh $env:APPDATA config directory.

    'names the worksheet tenants'
    'names the table Tenants'

    'writes the four expected columns in order'
        TenantName, Aliases, TenantId, PasswordURLs. This is the contract with
        Connect-IRTTenant.

    'writes three sample rows'
    'writes sample aliases that Connect-IRTTenant can match'
        Connect-IRTTenant matches with "^($($Tenant.Aliases))$", so the sample
        patterns must survive that anchoring.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        function Get-TempSheetPath {
            $Dir = [System.IO.Path]::GetTempPath()
            $Name = [System.Guid]::NewGuid().ToString()
            Join-Path -Path $Dir -ChildPath "${Name}\tenants.xlsx"
        }
    }

    Describe 'New-TenantSheet' -Tag 'unit' {

        Context 'the worksheet already exists' {

            BeforeAll {
                $script:ExistingPath = Get-TempSheetPath
                $script:ExistingDir = Split-Path -Path $script:ExistingPath -Parent
                $null = New-Item -ItemType Directory -Path $script:ExistingDir -Force
                Set-Content -LiteralPath $script:ExistingPath -Value 'not a real workbook'

                Mock Export-Excel {}
            }

            AfterAll {
                $RemoveParams = @{
                    LiteralPath = $script:ExistingDir
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = 'SilentlyContinue'
                }
                Remove-Item @RemoveParams
            }

            It 'throws when the worksheet already exists' {
                { New-TenantSheet -Path $script:ExistingPath } |
                    Should -Throw '*already exists*'
            }

            It 'does not call Export-Excel when the file already exists' {
                Should -Invoke Export-Excel -Times 0 -Scope Context
            }
        }

        Context 'WhatIf' {

            BeforeAll {
                $script:WhatIfPath = Get-TempSheetPath
                Mock Export-Excel {}

                New-TenantSheet -Path $script:WhatIfPath -WhatIf
            }

            It 'writes nothing under -WhatIf' {
                Test-Path -LiteralPath $script:WhatIfPath | Should -BeFalse
            }

            It 'does not create the parent directory under -WhatIf' {
                $Parent = Split-Path -Path $script:WhatIfPath -Parent
                Test-Path -LiteralPath $Parent | Should -BeFalse
            }

            It 'does not call Export-Excel under -WhatIf' {
                Should -Invoke Export-Excel -Times 0 -Scope Context
            }
        }
    }

    Describe 'New-TenantSheet' -Tag 'integration' {

        BeforeAll {
            $script:SheetPath = Get-TempSheetPath
            $script:SheetDir = Split-Path -Path $script:SheetPath -Parent

            $script:Result = New-TenantSheet -Path $script:SheetPath
            $script:Rows = @(Import-Excel -Path $script:SheetPath)

            $Package = Open-ExcelPackage -Path $script:SheetPath
            $script:SheetNames = @($Package.Workbook.Worksheets.Name)
            $Worksheet = $Package.Workbook.Worksheets['tenants']
            $script:TableNames = @($Worksheet.Tables.Name)
            Close-ExcelPackage -ExcelPackage $Package -NoSave
        }

        AfterAll {
            $RemoveParams = @{
                LiteralPath = $script:SheetDir
                Recurse     = $true
                Force       = $true
                ErrorAction = 'SilentlyContinue'
            }
            Remove-Item @RemoveParams
        }

        Context 'file creation' {

            It 'creates the workbook file' {
                Test-Path -LiteralPath $script:SheetPath | Should -BeTrue
            }

            It 'creates the parent directory when it does not exist' {
                Test-Path -LiteralPath $script:SheetDir | Should -BeTrue
            }

            It 'returns the created file' {
                $script:Result.FullName | Should -Be $script:SheetPath
            }
        }

        Context 'workbook structure' {

            It 'names the worksheet tenants' {
                $script:SheetNames | Should -Contain 'tenants'
            }

            It 'names the table Tenants' {
                $script:TableNames | Should -Contain 'Tenants'
            }
        }

        Context 'column layout' {

            It 'writes the four expected columns in order' {
                $Columns = $script:Rows[0].psobject.Properties.Name
                $Columns | Should -Be @('TenantName', 'Aliases', 'TenantId', 'PasswordURLs')
            }
        }

        Context 'sample rows' {

            It 'writes three sample rows' {
                $script:Rows.Count | Should -Be 3
            }

            It 'writes a tenant id in each row' {
                foreach ($Row in $script:Rows) {
                    $Row.TenantId | Should -Match '^[0-9a-f-]{36}$'
                }
            }

            It 'writes sample aliases that Connect-IRTTenant can match' {
                $Contoso = $script:Rows | Where-Object { $_.TenantName -eq 'Contoso Inc' }
                'contoso' -match "^($($Contoso.Aliases))$" | Should -BeTrue
            }
        }
    }
}
