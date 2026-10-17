#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Checks that every Export-Excel call in Source turns off link conversion.

.DESCRIPTION
    Export-Excel saves any value .NET reads as a full URL as a link. An IPv6
    address whose first block starts with a letter, such as fd00::, reads as a
    URL scheme, so sign-in logs and other exports saved these addresses as links.
    Every call must pass NoHyperLinkConversion, directly or in the hashtable it
    splats, so a new export cannot bring the links back.

    One It per Export-Excel call, generated during Discovery. Files are parsed,
    so a mention in a comment or a string is never a call.
#>

BeforeDiscovery {
    $SourceParams = @{
        Path      = $PSScriptRoot
        ChildPath = '..\..\Source'
    }
    $SourcePath = (Resolve-Path (Join-Path @SourceParams)).Path
    $script:Calls = foreach ($File in Get-ChildItem -Path $SourcePath -Filter '*.ps1' -Recurse) {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName, [ref]$null, [ref]$null)
        $Found = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and
                $Node.GetCommandName() -eq 'Export-Excel'
            }, $true)
        foreach ($Call in $Found) {
            @{
                Name   = "$($File.Name) line $($Call.Extent.StartLineNumber)"
                Path   = $File.FullName
                Offset = $Call.Extent.StartOffset
            }
        }
    }
}

Describe 'Export-Excel link conversion' -Tag 'unit', 'regression' {

    # Discovery variables are gone when tests run, so the count comes in as test data
    It 'finds Export-Excel calls in Source' -ForEach @{ CallCount = @($script:Calls).Count } {
        $CallCount | Should -BeGreaterThan 0
    }

    It '<Name> turns off link conversion' -ForEach $script:Calls {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $Path, [ref]$null, [ref]$null)
        $Call = $Ast.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and
                $Node.Extent.StartOffset -eq $Offset
            }, $true)

        $Named = @($Call.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst]
            } | ForEach-Object { $_.ParameterName })
        if ($Named -contains 'NoHyperLinkConversion') { return }

        $Splat = @($Call.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $_.Splatted
            })
        $Splat.Count | Should -BeGreaterThan 0 -Because 'the call passes no settings'

        # the splatted hashtable is the last one assigned to that variable before the call
        $Keys = foreach ($Variable in $Splat) {
            $SplatText = '$' + $Variable.VariablePath.UserPath
            $Assignment = $Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Extent.StartOffset -lt $Offset -and
                    $Node.Left.Extent.Text -eq $SplatText -and
                    $Node.Right.Extent.Text -like '@{*'
                }, $true) | Sort-Object { $_.Extent.StartOffset } | Select-Object -Last 1
            if (-not $Assignment) { continue }
            $Table = $Assignment.Right.Find({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.HashtableAst]
                }, $true)
            $Table.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text -replace '[''"]', '' }
        }
        $Keys | Should -Contain 'NoHyperLinkConversion'
    }
}
