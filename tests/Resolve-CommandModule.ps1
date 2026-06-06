#Requires -Version 7.0

function Resolve-CommandModule {
    <#
    .SYNOPSIS
        Finds the module that provides one or more command names.

    .DESCRIPTION
        Looks up each supplied command name with Get-Command and reports the module that
        provides it, the module's location on disk, and a best-effort classification of
        the command's source. Aliases are followed to the command they ultimately resolve
        to, so the reported module reflects the real implementation rather than the alias.

        The Source classification is a heuristic based on where the module lives, not on
        installation metadata, because the originating repository (for example, the
        PowerShell Gallery) is not recorded on the resolved command. The classifications
        are:

            Installed - Module resides outside $PSHOME; an explicit import is appropriate.
            Builtin   - Module ships with PowerShell (module base under $PSHOME) and is
                        already available; no explicit import is needed.
            None      - The command resolved but belongs to no module, such as a function
                        defined locally or a language element.
            NotFound  - No command of that name could be resolved in the current session.

    .PARAMETER Name
        One or more command names to resolve. Accepts pipeline input.

    .PARAMETER Trace
        Emits diagnostic trace output describing each resolution, including alias
        following and the source classification applied.

    .EXAMPLE
        Resolve-CommandModule -Name Get-MgUser

        Resolves a single command and reports its module, path, and source.

    .EXAMPLE
        Find-ScriptCommand -Path .\Connect-IRTGraph.ps1 | Resolve-CommandModule

        Resolves every command found in a file, classifying each by source.

    .OUTPUTS
        PSCustomObject with the properties: Name, Module, ModulePath, Source.

    .NOTES
        Source is a heuristic and does not distinguish gallery-installed modules from
        other locally installed ones; it only separates PowerShell-shipped modules from
        everything else. To build an import list from the results, filter to
        Source -eq 'Installed' and select the unique Module values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]] $Name,

        [switch] $Trace
    )

    begin {
        if ($Trace) { $InformationPreference = 'Continue' }
        function Write-Trace {
            param([Parameter(Mandatory)][string] $Message)
            Write-Information $Message -Tags 'Trace'
        }

        $FunctionName = $MyInvocation.MyCommand.Name
    }

    process {
        foreach ($commandName in $Name) {
            $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue

            if (-not $command) {
                Write-Trace "${FunctionName}: not found, skipping '$commandName'"
                [PSCustomObject]@{
                    Name       = $commandName
                    Module     = $null
                    ModulePath = $null
                    Source     = 'NotFound'
                }
                continue
            }

            while ($command.CommandType -eq 'Alias') {
                Write-Trace ("${FunctionName}: '$commandName' is an alias for " +
                    "'$($command.ResolvedCommand)'")
                $command = $command.ResolvedCommand
            }

            $module = $command.Module

            if (-not $module) {
                $source = 'None'
            }
            elseif ($module.ModuleBase -and $module.ModuleBase -like "$PSHOME*") {
                $source = 'Builtin'
            }
            else {
                $source = 'Installed'
            }

            Write-Trace "${FunctionName}: '$commandName' -> $($module.Name) [$source]"
            [PSCustomObject]@{
                Name       = $commandName
                Module     = $module.Name
                ModulePath = $module.ModuleBase
                Source     = $source
            }
        }
    }
}
