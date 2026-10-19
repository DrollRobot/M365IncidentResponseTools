#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Copy-IRTFunction.

.DESCRIPTION
    The copied functions are pasted onto servers that do not have the module, and
    usually do not have PSFramework. Copy-IRTFunction is run once with Set-Clipboard,
    Format-Powershell, and Write-IRT mocked, and the copied script is parsed.

    'finds every function in its list'
        A renamed or deleted function is left out with only a warning.

    'copies every module function the copied functions call'
        Get-LocalAdSyncService and Get-IRTClipboardSearch were left out, so a pasted
        Disable-IRTAdUser failed with CommandNotFoundException.

    'copies no function that uses PSFramework'
        Get-LocalAdSyncService and Get-IRTClipboardSearch imported PSFramework, which
        fails on servers without it.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Copy-IRTFunction' -Tag 'unit' {

        BeforeAll {
            Mock Format-Powershell { $Content }
            Mock Set-Clipboard { $script:CopiedScript = $Value }
            Mock Write-IRT { }

            Copy-IRTFunction

            $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $script:CopiedScript, [ref] $null, [ref] $null)
            $script:Defined = $Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true).Name
            $script:Commands = $Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
        }

        AfterAll {
            Remove-Variable -Name 'CopiedScript' -Scope 'Script' -ErrorAction Ignore
        }

        It 'finds every function in its list' {
            $InvokeParams = @{
                CommandName     = 'Write-IRT'
                ParameterFilter = { $Level -eq 'Warn' }
                Times           = 0
                Exactly         = $true
                Scope           = 'Describe'
            }
            Should -Invoke @InvokeParams
        }

        It 'copies every module function the copied functions call' -Tag 'regression' {
            $ModuleFunctions = (Get-ChildItem -Path 'Function:' |
                    Where-Object ModuleName -EQ 'M365IncidentResponseTools').Name
            $ModuleAliases = @{}
            foreach ($Alias in Get-Alias) {
                if ($ModuleFunctions -contains $Alias.Definition) {
                    $ModuleAliases[$Alias.Name] = $Alias.Definition
                }
            }

            $Missing = foreach ($Cmd in $script:Commands) {
                $Name = $Cmd.GetCommandName()
                if (-not $Name) { continue }
                if ($ModuleAliases[$Name]) { $Name = $ModuleAliases[$Name] }
                if ($ModuleFunctions -contains $Name -and $script:Defined -notcontains $Name) {
                    $Name
                }
            }
            $Missing | Select-Object -Unique | Should -BeNullOrEmpty
        }

        It 'copies no function that uses PSFramework' -Tag 'regression' {
            $PsfCommands = (Get-Command -Module 'PSFramework').Name
            $Found = foreach ($Cmd in $script:Commands) {
                $Name = $Cmd.GetCommandName()
                if ($PsfCommands -contains $Name) {
                    $Name
                    continue
                }
                $PsfArgs = $Cmd.CommandElements | Select-Object -Skip 1 | Where-Object {
                    $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $_.Value -eq 'PSFramework'
                }
                if ($PsfArgs) { "$Name PSFramework" }
            }
            $Found | Select-Object -Unique | Should -BeNullOrEmpty
        }
    }
}
