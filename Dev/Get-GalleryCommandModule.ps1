function Get-GalleryCommandModule {
    <#
    .SYNOPSIS
        Searches the PowerShell Gallery for the modules that provide the given commands.

    .DESCRIPTION
        Looks up each command name against the PowerShell Gallery and reports the modules
        that export it, with their versions. Uses Find-PSResource when available and falls
        back to Find-Module otherwise.

    .PARAMETER Name
        One or more command names to search for. Accepts pipeline input.

    .PARAMETER Trace
        Emits diagnostic trace output describing the search backend and results.

    .EXAMPLE
        Get-GalleryCommandModule -Name Get-MgUser, Connect-ExchangeOnline

        Returns the gallery modules and versions that provide each command.
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

        $useResourceGet = [bool] (Get-Command -Name Find-PSResource -ErrorAction SilentlyContinue)
        if ($useResourceGet) {
            Write-Trace "${FunctionName}: using Find-PSResource"
        }
        else {
            Write-Trace "${FunctionName}: Find-PSResource unavailable, using Find-Module"
        }
    }

    process {
        foreach ($commandName in $Name) {
            Write-Trace "${FunctionName}: searching for '$commandName'"

            if ($useResourceGet) {
                $found = Find-PSResource -CommandName $commandName -ErrorAction SilentlyContinue
            }
            else {
                $found = Find-Module -Command $commandName -ErrorAction SilentlyContinue
            }

            if (-not $found) {
                Write-Trace "${FunctionName}: no module found for '$commandName'"
                continue
            }

            foreach ($result in $found) {
                [PSCustomObject]@{
                    Name    = $commandName
                    Module  = $result.Name
                    Version = $result.Version
                }
            }
        }
    }
}
