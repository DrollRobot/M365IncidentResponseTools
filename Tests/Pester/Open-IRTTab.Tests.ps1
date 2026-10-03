#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Open-IRTTab.

.DESCRIPTION
    Open-IRTTab opens a Windows Terminal tab, or a tmux window on Linux and macOS.
    wt and tmux are replaced by global stub functions for the duration of the file and
    mocked, so nothing is launched. WT_SESSION and TMUX are set per test and restored.

-- host detection ----------------------------------------------------------

    'opens a Windows Terminal tab inside Windows Terminal'
    'opens a background tmux window inside tmux'
        Linux and macOS had no way to open a tab at all.
    'reports an error outside both, unless -Quiet'
#>

BeforeAll {
    # Stubs shadow any real wt or tmux so Mock can bind their arguments.
    function global:wt {
        param([Parameter(ValueFromRemainingArguments)] $Arguments)
        $null = $Arguments
    }
    function global:tmux {
        param([Parameter(ValueFromRemainingArguments)] $Arguments)
        $null = $Arguments
    }
    $script:SavedWt = $env:WT_SESSION
    $script:SavedTmux = $env:TMUX
}

AfterAll {
    Remove-Item -Path 'Function:\wt', 'Function:\tmux' -ErrorAction SilentlyContinue
    $env:WT_SESSION = $script:SavedWt
    $env:TMUX = $script:SavedTmux
}

InModuleScope M365IncidentResponseTools {

    Describe 'Open-IRTTab' -Tag 'unit' {

        BeforeEach {
            $env:WT_SESSION = $null
            $env:TMUX = $null
            Mock wt { }
            Mock tmux { }
            Mock Write-IRT { }
            Mock Get-Command { [pscustomobject]@{ Name = 'tmux' } } -ParameterFilter {
                $Name -eq 'tmux'
            }
        }

        It 'opens a Windows Terminal tab inside Windows Terminal' {
            $env:WT_SESSION = 'test-session'
            Open-IRTTab
            Should -Invoke wt -Times 1 -Exactly -ParameterFilter {
                $Arguments -contains 'new-tab'
            }
            Should -Invoke tmux -Times 0 -Exactly
        }

        It 'opens a background tmux window inside tmux' -Tag 'regression' {
            $env:TMUX = '/tmp/tmux-1000/default,1,0'
            Open-IRTTab -Title 'Second'
            Should -Invoke tmux -Times 1 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'new-window' -and $Arguments -contains '-d' -and
                $Arguments -contains 'Second' -and $Arguments -contains 'pwsh'
            }
            Should -Invoke wt -Times 0 -Exactly
        }

        It 'reports an error outside both, unless -Quiet' {
            { Open-IRTTab -ErrorAction Stop } | Should -Throw '*Windows Terminal*tmux*'
            { Open-IRTTab -Quiet -ErrorAction Stop } | Should -Not -Throw
            Should -Invoke wt -Times 0 -Exactly
            Should -Invoke tmux -Times 0 -Exactly
        }

        It 'treats TMUX as unusable when tmux is not installed' {
            $env:TMUX = '/tmp/tmux-1000/default,1,0'
            Mock Get-Command { } -ParameterFilter { $Name -eq 'tmux' }
            Open-IRTTab -Quiet
            Should -Invoke tmux -Times 0 -Exactly
        }
    }
}
