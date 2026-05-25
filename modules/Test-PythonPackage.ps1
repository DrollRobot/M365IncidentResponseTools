function Test-PythonPackage {
    <#
    .SYNOPSIS
    Tests whether a python package is available via python import or uv tool install.

    .PARAMETER Name
    The python module name to import (e.g., 'requests' or 'pandas').

    .PARAMETER MinVersion
    Optional minimum version requirement (nuget-style: 1.2.3).

    .PARAMETER PythonPath
    Optional explicit path to python interpreter. if omitted, tries python, python3, then py -3.

    .OUTPUTS
    [pscustomobject] with Present (bool), Source (string), Version (string), Python (string path/command)
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

        function Find-UvTool {
            param([string]$ToolName)

            $uvCmd = Get-Command -Name 'uv' -ErrorAction SilentlyContinue
            if (-not $uvCmd) { return $null }

            # normalize per PEP 503: lowercase, collapse runs of [-_.] to a single hyphen
            $normalizedName = ($ToolName -replace '[_.\-]+', '-').ToLower()

            try {
                $listOutput = & $uvCmd.Source tool list 2>$null
                if ($LASTEXITCODE -ne 0) { return $null }

                $version  = $null
                $distName = $null
                foreach ($line in $listOutput) {
                    if ($line -match '^(\S+)\s+v(.+)$') {
                        $candidate = ($Matches[1] -replace '[_.\-]+', '-').ToLower()
                        if ($candidate -eq $normalizedName) {
                            $distName = $Matches[1]
                            $version  = $Matches[2].Trim()
                            break
                        }
                    }
                }

                if (-not $version) { return $null }

                # locate the venv python inside the tool environment
                $toolDir = (& $uvCmd.Source tool dir 2>$null)
                if ($LASTEXITCODE -ne 0 -or -not $toolDir) {
                    return @{ Version = $version; Python = $null }
                }
                $toolDir = $toolDir.Trim()

                # try likely directory names for the tool's venv
                $dirCandidates = @($distName, $ToolName, $normalizedName) | Select-Object -Unique

                $pythonPath = $null
                foreach ($dir in $dirCandidates) {
                    $testPath = if ($IsWindows -or $env:OS -match 'Windows') {
                        Join-Path $toolDir $dir 'Scripts' 'python.exe'
                    } else {
                        Join-Path $toolDir $dir 'bin' 'python'
                    }
                    if (Test-Path -LiteralPath $testPath) {
                        $pythonPath = $testPath
                        break
                    }
                }

                return @{ Version = $version; Python = $pythonPath }
            } catch {
                return $null
            }
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

        # === python import check ===
        $Py = Find-PythonInterpreter -ExplicitPath $PythonPath
        $PyPresent = $false
        $PyVersion = $null
        $PyCmd     = $null

        if ($Py) {
            $Arguments = @()
            if ($Py.PrefixArgs) { $Arguments += $Py.PrefixArgs }
            $Arguments += @('-c', $PyCode, $Name)

            $Output = & $Py.Cmd @Arguments 2>$null
            $Exit   = $LASTEXITCODE

            $PyPresent = ($Exit -eq 0)
            $PyVersion = if ($PyPresent) { ($Output | Select-Object -First 1).ToString().Trim() } else { $null }
            $PyCmd     = $Py.Cmd + ($(if ($Py.PrefixArgs.Count) { ' ' + ($Py.PrefixArgs -join ' ') } else { '' }))
        }

        # === uv tool check ===
        $UvTool    = Find-UvTool -ToolName $Name
        $UvPresent = $null -ne $UvTool
        $UvVersion = if ($UvPresent) { $UvTool.Version } else { $null }
        $UvPython  = if ($UvPresent) { $UvTool.Python  } else { $null }

        # overall result
        $Present = $PyPresent -or $UvPresent

        $Source = if ($PyPresent -and $UvPresent) { 'both'    }
                  elseif ($PyPresent)              { 'python'  }
                  elseif ($UvPresent)              { 'uv-tool' }
                  else                             { $null     }

        # effective version (prefer python import, fall back to uv tool)
        $Version = if ($PyVersion) { $PyVersion } elseif ($UvVersion) { $UvVersion } else { $null }

        # effective python interpreter
        # if found via import, use that interpreter; if only via uv tool, use the venv python
        $Python = if ($PyPresent) { $PyCmd    }
                  elseif ($UvPython)  { $UvPython }
                  elseif ($PyCmd)     { $PyCmd    }
                  else                { $null     }

        # optional min version check
        $MeetsMin = $true
        if ($Present -and $MinVersion -and $Version) {
            try {
                # attempt semantic comparison; if parse fails, treat as not comparable
                $vA = [Version]($Version -replace '[^0-9\.].*$', '')
                $vB = [Version]($MinVersion -replace '[^0-9\.].*$', '')
                $MeetsMin = ($vA -ge $vB)
            } catch {
                $MeetsMin = $false
            }
        }

        Write-Output ([pscustomobject]@{
            Present         = $Present
            Source          = $Source
            Version         = $Version
            MeetsMinVersion = if ($MinVersion) { $MeetsMin } else { $null }
            Name            = $Name
            Python          = $Python
        })
    }
}
