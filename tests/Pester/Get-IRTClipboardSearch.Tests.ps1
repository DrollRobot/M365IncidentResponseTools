#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for the Get-IRTClipboardSearch private helper.

.DESCRIPTION
    Get-IRTClipboardSearch reads the clipboard and returns one trimmed, non-empty
    search string per line. Get-Clipboard, Import-IRTModule, and Write-PSFMessage
    are mocked so no clipboard I/O or module loads occur. Tests run InModuleScope so
    the private function and its mocked dependencies resolve inside the module.

    Covers: one term per array line, line-ending normalization for a single
    multi-line string, whitespace trimming, blank-line removal, single-line input,
    and the empty/whitespace-only clipboard throw paths.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTClipboardSearch' -Tag 'unit' {

        BeforeEach {
            Mock Import-IRTModule { }
            Mock Write-PSFMessage { }
        }

        It 'returns one term per array line, in order' {
            Mock Get-Clipboard { @('Test', 'test2', 'TAST3') }
            $Result = Get-IRTClipboardSearch
            ($Result -join '|') | Should -Be 'Test|test2|TAST3'
        }

        It 'splits a single multi-line string on CRLF and LF' {
            Mock Get-Clipboard { "Test`r`ntest2`nTAST3" }
            $Result = Get-IRTClipboardSearch
            ($Result -join '|') | Should -Be 'Test|test2|TAST3'
        }

        It 'trims surrounding whitespace from each line' {
            Mock Get-Clipboard { @('  Test  ', "`ttest2`t") }
            $Result = Get-IRTClipboardSearch
            ($Result -join '|') | Should -Be 'Test|test2'
        }

        It 'drops blank and whitespace-only lines' {
            Mock Get-Clipboard { @('Test', '', '   ', 'test2') }
            $Result = Get-IRTClipboardSearch
            ($Result -join '|') | Should -Be 'Test|test2'
        }

        It 'returns a single term for single-line input' {
            Mock Get-Clipboard { 'OnlyOne' }
            $Result = Get-IRTClipboardSearch
            @($Result).Count | Should -Be 1
            @($Result)[0] | Should -Be 'OnlyOne'
        }

        It 'throws when the clipboard is empty' {
            Mock Get-Clipboard { $null }
            { Get-IRTClipboardSearch } | Should -Throw
        }

        It 'throws when the clipboard holds only whitespace' {
            Mock Get-Clipboard { @('   ', '') }
            { Get-IRTClipboardSearch } | Should -Throw
        }
    }
}
