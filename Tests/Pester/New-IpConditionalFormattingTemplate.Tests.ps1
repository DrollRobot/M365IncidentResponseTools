#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for New-IpConditionalFormattingTemplate.

.DESCRIPTION
    New-IpConditionalFormattingTemplate builds the default IP address color-coding rules
    that Add-IpInfoToSheet applies when no custom template is configured. It replaced a
    bundled IpAddressConditionalFormattingTemplate.xlsx, so these tests pin the rules that
    used to live in that file: their text, order, fill color and stop-at-first-match flag.

    The package is built in memory. Only the copy round-trip writes disposable workbooks
    under the temp directory. No network calls are made.

-- rule construction (unit) ----------------------------------------------

    'adds nine rules'
    'targets column A with ContainsText rules that stop at the first match'
        Add-ConditionalFormatting is mocked; these check the arguments only.

    'rethrows when a rule cannot be added'
        A half-built template must not be returned as if it were complete.

-- generated package (integration) ---------------------------------------

    'returns an ExcelPackage'
    'holds a single worksheet named IpAddress'
        Copy-ConditionalFormatting auto-selects the sheet only when there is one.

    'places every rule on column A'
        Add-IpInfoToSheet copies from A1:A1048576.

    'matches the expected text, in order'
    'fills each rule with the expected color'
    'stops at the first matching rule'
        Order matters because every rule sets StopIfTrue.

-- copy round-trip (integration) -----------------------------------------

    'copies all nine rules'
    'upgrades every fill to Solid'
    'keeps a background color on every rule'
        Add-ConditionalFormatting leaves PatternType at None; Copy-ConditionalFormatting
        must upgrade it or the saved workbook drops the fill.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'New-TempXlsxPath is a Pester test helper; ShouldProcess is not applicable.')]
param()

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        # Expected rules, in evaluation order. Colors are RGB hex.
        $script:ExpectedRules = @(
            @{ Text = 'microsoft'; Color = 'ADD8E6' }
            @{ Text = 'proofpoint'; Color = '59ABF8' }
            @{ Text = ' vpn'; Color = 'FFB6C1' }
            @{ Text = ' tor'; Color = 'FFB6C1' }
            @{ Text = ' proxy'; Color = 'FFB6C1' }
            @{ Text = ' hosting'; Color = 'FACD90' }
            @{ Text = ' cloud'; Color = 'FACD90' }
            @{ Text = ' datacenter'; Color = 'FACD90' }
            @{ Text = 'mobile'; Color = 'F2CEEF' }
        )

        function ConvertTo-RgbHex {
            param([Parameter(Mandatory)] $Color)
            $Color.R.ToString('X2') + $Color.G.ToString('X2') + $Color.B.ToString('X2')
        }

        function New-TempXlsxPath {
            $Dir = [System.IO.Path]::GetTempPath()
            $Name = [System.Guid]::NewGuid().ToString() + '.xlsx'
            Join-Path -Path $Dir -ChildPath $Name
        }
    }

    Describe 'New-IpConditionalFormattingTemplate' -Tag 'unit' {

        Context 'rule construction' {

            BeforeAll {
                Mock Add-ConditionalFormatting {}
                $script:Package = New-IpConditionalFormattingTemplate
            }

            AfterAll {
                $script:Package.Dispose()
            }

            It 'adds nine rules' {
                Should -Invoke Add-ConditionalFormatting -Times 9 -Exactly -Scope Context
            }

            It 'targets column A with ContainsText rules that stop at the first match' {
                $InvokeParams = @{
                    CommandName     = 'Add-ConditionalFormatting'
                    Times           = 9
                    Exactly         = $true
                    Scope           = 'Context'
                    ParameterFilter = {
                        $Address -eq 'A:A' -and
                        $RuleType -eq 'ContainsText' -and
                        $StopIfTrue
                    }
                }
                Should -Invoke @InvokeParams
            }
        }

        Context 'failure' {

            It 'rethrows when a rule cannot be added' {
                Mock Add-ConditionalFormatting { throw 'rule failed' }
                { New-IpConditionalFormattingTemplate } | Should -Throw '*rule failed*'
            }
        }
    }

    Describe 'New-IpConditionalFormattingTemplate' -Tag 'integration' {

        Context 'generated package' {

            BeforeAll {
                $script:Package = New-IpConditionalFormattingTemplate
                $script:Sheets = @($script:Package.Workbook.Worksheets)
                $script:Rules = @($script:Sheets[0].ConditionalFormatting)
            }

            AfterAll {
                $script:Package.Dispose()
            }

            It 'returns an ExcelPackage' {
                $script:Package | Should -BeOfType 'OfficeOpenXml.ExcelPackage'
            }

            It 'holds a single worksheet named IpAddress' {
                $script:Sheets.Count | Should -Be 1
                $script:Sheets[0].Name | Should -Be 'IpAddress'
            }

            It 'places every rule on column A' {
                foreach ($Rule in $script:Rules) {
                    $Rule.Address.Address | Should -Be 'A:A'
                }
            }

            It 'matches the expected text, in order' {
                $Actual = @($script:Rules | ForEach-Object Text)
                $Actual | Should -Be @($script:ExpectedRules | ForEach-Object { $_.Text })
            }

            It 'fills each rule with the expected color' {
                $Actual = @($script:Rules | ForEach-Object {
                        ConvertTo-RgbHex -Color $_.Style.Fill.BackgroundColor.Color
                    })
                $Actual | Should -Be @($script:ExpectedRules | ForEach-Object { $_.Color })
            }

            It 'stops at the first matching rule' {
                foreach ($Rule in $script:Rules) {
                    $Rule.StopIfTrue | Should -BeTrue
                }
            }
        }

        Context 'copy round-trip' {

            BeforeAll {
                $script:DstPath = New-TempXlsxPath
                $Dst = [OfficeOpenXml.ExcelPackage]::new()
                $null = $Dst.Workbook.Worksheets.Add('Sheet1')
                $Dst.SaveAs([System.IO.FileInfo]$script:DstPath)
                $Dst.Dispose()

                $Template = New-IpConditionalFormattingTemplate
                try {
                    $CopyParams = @{
                        Source           = $Template
                        SourceRange      = 'A1:A1048576'
                        Destination      = $script:DstPath
                        DestinationRange = 'C1'
                    }
                    Copy-ConditionalFormatting @CopyParams
                }
                finally {
                    $Template.Dispose()
                }

                $Saved = Open-ExcelPackage -Path $script:DstPath
                $script:CopiedRules = @($Saved.Workbook.Worksheets[1].ConditionalFormatting)
                Close-ExcelPackage -ExcelPackage $Saved -NoSave
            }

            AfterAll {
                Remove-Item -LiteralPath $script:DstPath -ErrorAction SilentlyContinue
            }

            It 'copies all nine rules' {
                $script:CopiedRules.Count | Should -Be 9
            }

            It 'upgrades every fill to Solid' {
                foreach ($Rule in $script:CopiedRules) {
                    $Rule.Style.Fill.PatternType | Should -Be 'Solid'
                }
            }

            It 'keeps a background color on every rule' {
                foreach ($Rule in $script:CopiedRules) {
                    $Rule.Style.Fill.BackgroundColor.Color | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
}
