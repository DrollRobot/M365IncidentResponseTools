function Test-IsSorted {
    # helper: check if a list is sorted on property in the requested direction
    param(
        [System.Collections.Generic.List[psobject]] $InputList,
        [string] $KeyProperty,
        [bool] $IsAscending
    )
    if ($InputList.Count -lt 2) { return $true }
    $Previous = $InputList[0].$KeyProperty
    for ($Index = 1; $Index -lt $InputList.Count; $Index++) {
        $Current = $InputList[$Index].$KeyProperty
        if ($IsAscending) {
            if ($Current -lt $Previous) { return $false }
        } else {
            if ($Current -gt $Previous) { return $false }
        }
        $Previous = $Current
    }
    return $true
}
