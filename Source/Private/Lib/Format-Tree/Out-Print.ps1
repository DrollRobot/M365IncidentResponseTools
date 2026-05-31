function Out-Print {
    param(
        [Parameter(Position = 0)]
        [string] $Name,
        [Parameter(Position = 1)]
        $Value,
        [Parameter(Position = 2)]
        [int] $CurrentDepth
    )

    # print node (returns $true if anything was printed)
    if ($CurrentDepth -gt $Depth) { return $false }

    $Value = Resolve-Json $Value

    if ($null -eq $Value) {
        if (-not $OmitNullOrEmpty) {
            Write-NameValue $Name '<null>' $CurrentDepth $IndentSize
            return $true
        }
        return $false
    }

    if (Test-IsScalar $Value) {
        if ($OmitNullOrEmpty -and (Test-IsEmptyScalar $Value)) { return $false }
        Write-NameValue $Name ([string]$Value) $CurrentDepth $IndentSize
        return $true
    }

    # non-scalar at/over the depth limit -> print "NAME: ...""
    if ($CurrentDepth -ge $Depth) {
        Write-NameEllipsis $Name $CurrentDepth $IndentSize
        return $true
    }

    if ($Value -is [System.Collections.IDictionary]) {
        # one more level would exceed limit -> collapse whole map to ellipsis
        if (($CurrentDepth + 1) -ge $Depth) {
            Write-NameEllipsis $Name $CurrentDepth $IndentSize
            return $true
        }

        $Printed = $false

        if (($CurrentDepth + 1) -ge $Depth) {
            $indent = Get-Indent $CurrentDepth $IndentSize
            Write-Host -NoNewline $indent
            Write-Host -NoNewline @Green ($Name + ': ')
            Write-Host @Red '...'
            return $true
        }
        foreach ($Key in ($Value.Keys | Sort-Object)) {
            if (Test-HasVisible $Value[$Key] ($CurrentDepth + 1)) {
                if (-not $Printed) {
                    Write-NameValue $Name '' $CurrentDepth $IndentSize
                    $Printed = $true
                }
                $null = Out-Print ("[$Key]") $Value[$Key] ($CurrentDepth + 1)
            }
        }
        return $Printed
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        # one more level would exceed limit -> collapse whole map to ellipsis
        if (($CurrentDepth + 1) -ge $Depth) {
            Write-NameEllipsis $Name $CurrentDepth $IndentSize
            return $true
        }

        $Visible = @()
        foreach ($E in $Value) {
            if (Test-HasVisible $E ($CurrentDepth + 1)) {
                $Visible += , $E
            }
        }
        if ($Visible.Count -eq 0) {
            return $false
        }
        Write-NameValue $Name "[$($Visible.Count)]" $CurrentDepth $IndentSize
        for ($i = 0; $i -lt $Visible.Count; $i++) {
            $null = Out-Print "[$i]" $Visible[$i] ($CurrentDepth + 1)
        }
        return $true
    }

    $Names = Get-PropertyName $Value
    if ($ExcludeSet) { $Names = $Names | Where-Object { -not $ExcludeSet.Contains($_) } }

    $Pairs = @()
    foreach ($N in $Names) {
        try { $V = $Value.PSObject.Properties[$N].Value } catch { $V = $null }
        if (Test-HasVisible $V ($CurrentDepth + 1)) { $Pairs += , @($N, $V) }
    }
    if ($Pairs.Count -eq 0) { return $false }

    Write-NameValue $Name '' $CurrentDepth $IndentSize
    foreach ($P in $Pairs) { $null = Out-Print $P[0] $P[1] ($CurrentDepth + 1) }
    return $true
}