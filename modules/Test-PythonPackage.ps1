function Test-PythonPackage {
    <#
    .SYNOPSIS
    Tests whether a python package (importable module) is available.

    .PARAMETER Name
    The python module name to import (e.g., 'requests' or 'pandas').

    .PARAMETER MinVersion
    Optional minimum version requirement (nuget-style: 1.2.3).

    .PARAMETER PythonPath
    Optional explicit path to python interpreter. if omitted, tries python, python3, then py -3.

    .OUTPUTS
    [pscustomobject] with Present (bool), Version (string), Python (string path/command)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string] $Name,

        [Parameter()]
        [string] $MinVersion,

        [Parameter()]
        [string] $PythonPath
    )

    begin {

        function Find-PythonInterpreter {
            param(
                [string]$ExplicitPath
            )

            # if explicit path provided and exists, use it
            if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
                return @{ Cmd = $ExplicitPath; PrefixArgs = @() }
            }

            # prefer 'python', then 'python3', then 'py -3' on windows
            $Candidates = @(
                @{ 
                    Cmd = (Get-Command -Name 'python' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @()
                }
                @{ 
                    Cmd = (Get-Command -Name 'python3' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @()
                }
                @{ 
                    Cmd = (Get-Command -Name 'py' -ErrorAction SilentlyContinue)?.Source
                    PrefixArgs = @('-3') 
                }
            ) | Where-Object { $_.Cmd }

            if (($Candidates | Measure-Object).Count -gt 0) {return $Candidates[0]}

            return $null
        }

        # python snippet: try import, then try to resolve a version
        # - prefers importlib.metadata (py>=3.8) using the package (distribution) name equal to module name
        # - falls back to module.__version__ if metadata not found
        $PyCode = @"
import sys, importlib
name=sys.argv[1]
try:
    m = importlib.import_module(name)
    ver = ""
    try:
        try:
            from importlib.metadata import version, PackageNotFoundError
        except Exception:
            from importlib_metadata import version, PackageNotFoundError  # backport if installed
        try:
            ver = version(name)
        except PackageNotFoundError:
            ver = getattr(m, "__version__", "") or ""
    except Exception:
        ver = getattr(m, "__Version__", "") or ""
    print(ver)
    sys.exit(0)
except Exception:
    sys.exit(1)
"@.Trim()
    }

    process {

        # find python interpreter
        $Py = Find-PythonInterpreter -ExplicitPath $PythonPath
        if (-not $Py) {
            Write-Output ([pscustomobject]@{
                Present = $false
                Version = $null
                Python  = $null
                Name    = $Name
                Reason  = 'no python interpreter found on path'
            })
            return
        }

        # build arg list with splatting
        $Arguments = @()
        if ($Py.PrefixArgs) {$Arguments += $Py.PrefixArgs}
        $Arguments += @('-c', $PyCode, $Name)

        # run python -c "<code>" <Name>
        $InvokeParams = @{
            FilePath     = $Py.Cmd
            ArgumentList = $Arguments
            NoNewWindow  = $true
            Wait         = $true
            PassThru     = $false
            ErrorAction  = 'SilentlyContinue'
        }

        # use call operator for cross-platform simplicity
        $Output = & $InvokeParams.FilePath @($InvokeParams.ArgumentList) 2>$null
        $Exit   = $LASTEXITCODE

        $Present = ($Exit -eq 0)
        $Version = if ($Present) { ($Output | Select-Object -First 1).ToString().Trim() } else { $null }

        # optional min version check
        $MeetsMin = $true
        if ($Present -and $MinVersion) {
            try {
                # attempt semantic comparison; if parse fails, treat as not comparable
                $vA = [Version]($Version -replace '[^0-9\.].*$', '')
                $vB = [Version]($MinVersion -replace '[^0-9\.].*$', '')
                $MeetsMin = ($vA -ge $vB)
            } catch {
                $MeetsMin = $false
            }
        }

        # final result
        Write-Output ([pscustomobject]@{
            Present         = $Present
            Version         = $Version
            MeetsMinVersion = if ($MinVersion) { $MeetsMin } else { $null }
            Name            = $Name
            Python          = $Py.Cmd + ($(if ($Py.PrefixArgs.Count) { ' ' + ($Py.PrefixArgs -join ' ') } else { '' }))
        })
    }
}