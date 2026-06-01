function Format-SentinelDate {
    param(
        [pscustomobject]$Obj
    )
    # helper: normalize sentinel dates (year 1) to $null
    foreach ($Name in 'Birthday', 'HireDate') {
        $Prop = $Obj.PSObject.Properties[$Name]
        if (-not $Prop) { continue }
        $Value = $Prop.Value
        $IsEmptyDate = $false

        if ($Value -is [datetime]) {
            if ($Value.Year -le 1) { $IsEmptyDate = $true }
        } elseif ($Value) {
            try {
                $dt = [datetime]::Parse($Value)
                if ($dt.Year -le 1) { $IsEmptyDate = $true }
            } catch { }
        }

        if ($IsEmptyDate) { $Obj.$Name = $null }
    }
}
