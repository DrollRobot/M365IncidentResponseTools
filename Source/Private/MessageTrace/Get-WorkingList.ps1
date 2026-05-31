function Get-WorkingList {
    # helper: ensure each list is sorted; if not, sort it into a new list
    param(
        [System.Collections.Generic.List[psobject][]] $InputList,
        [string] $KeyProperty,
        [bool] $IsAscending
    )
    $InnerType = 'System.Collections.Generic.List[psobject]'
    $Working = New-Object "System.Collections.Generic.List[$InnerType]"
    foreach ($SingleList in $InputList) {
        if (-not $SingleList -or $SingleList.Count -eq 0) {
            $Working.Add([System.Collections.Generic.List[psobject]]::new())
            continue
        }

        $IsSortedParams = @{
            InputList   = $SingleList
            KeyProperty = $KeyProperty
            IsAscending = $IsAscending
        }
        if (Test-IsSorted @IsSortedParams) {
            # already sorted; reuse as-is
            $Working.Add($SingleList)
        } else {
            # not sorted; sort and materialize into a new strongly-typed List[psobject]
            $sortParams = @{
                Property   = $KeyProperty
                Descending = -not $IsAscending
            }
            $Sorted = @( $SingleList | Sort-Object @sortParams )
            $AsList = [System.Collections.Generic.List[psobject]]::new()
            foreach ($Item in $Sorted) { $AsList.Add($Item) }
            $Working.Add($AsList)
        }
    }
    return , $Working
}