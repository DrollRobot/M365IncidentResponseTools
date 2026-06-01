function Test-HasVisible($Value, [int]$CurrentDepth) {
    # returns $true if value would produce visible output at this depth

    if ($CurrentDepth -gt $Depth) { return $false }

    # if value looks like json
    $Value = Resolve-Json $Value

    if ($CurrentDepth -eq $Depth) {
        if ($null -eq $Value) { return (-not $OmitNullOrEmpty) }
        if (Test-IsScalar $Value) {
            if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
            return $true
        }
        return $true
    }

    if ($null -eq $Value) { return (-not $OmitNullOrEmpty) }

    if (Test-IsScalar $Value) {
        if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
        return $true
    }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($Key in $Value.Keys) {
            if (Test-HasVisible $Value[$Key] ($CurrentDepth + 1)) { return $true }
        }
        return $false
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($E in $Value) { if (Test-HasVisible $E ($CurrentDepth + 1)) { return $true } }
        return $false
    }

    $Names = Get-PropertyName $Value
    if ($ExcludeSet) { $Names = $Names | Where-Object { -not $ExcludeSet.Contains($_) } }
    foreach ($N in $Names) {
        try { $V = $Value.PSObject.Properties[$N].Value } catch { $V = $null }
        if (Test-HasVisible $V ($CurrentDepth + 1)) { return $true }
    }
    return $false
}
