function Test-MergeSortedListsOnDate {
    [CmdletBinding()]
    param(
        # show merged outputs (off by default to keep output minimal)
        [switch] $ShowMerged
    )

    # helper: build a strongly-typed list[psobject] from an array of datetimes
    function New-DateList {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '')]
        param(
            [datetime[]] $Dates,
            [string] $Tag
        )
        $Out = [System.Collections.Generic.List[psobject]]::new()
        foreach ($D in $Dates) {
            # each item carries a date-like property and a tag so you can spot provenance
            $Out.Add([pscustomobject]@{ When = $D; Tag = $Tag })
        }
        return $Out
    }

    # helper: check a list is sorted on the given property in the given direction
    function Test-IsSortedOn {
        param(
            [System.Collections.Generic.List[psobject]] $List,
            [string] $PropertyName,
            [bool] $Ascending
        )
        if ($List.Count -lt 2) { return $true }
        for ($I = 1; $I -lt $List.Count; $I++) {
            $Prev = $List[$I - 1].$PropertyName
            $Curr = $List[$I].$PropertyName
            if ($Ascending) {
                if ($Curr -lt $Prev) { return $false }
            } else {
                if ($Curr -gt $Prev) { return $false }
            }
        }
        return $true
    }

    # build three lists; one intentionally unsorted to validate auto-sort behavior
    $ListOne = New-DateList -Dates @(
        [datetime]'2025-01-01',
        [datetime]'2025-01-03',
        [datetime]'2025-01-05'
    ) -Tag 'L1'

    $ListTwo = New-DateList -Dates @(
        [datetime]'2025-01-02',
        [datetime]'2025-01-04'
    ) -Tag 'L2'

    # intentionally out of order
    $ListThree = New-DateList -Dates @(
        [datetime]'2025-01-07',
        [datetime]'2025-01-06'
    ) -Tag 'L3'

    $AllInputCount = $ListOne.Count + $ListTwo.Count + $ListThree.Count

    # run ascending merge
    $AscParams = @{
        Lists        = @($ListOne, $ListTwo, $ListThree)
        PropertyName = 'When'
        Ascending    = $true
    }
    $MergedAsc = Merge-SortedListsOnDate @AscParams

    # run descending merge
    $DescParams = @{
        Lists        = @($ListOne, $ListTwo, $ListThree)
        PropertyName = 'When'
        Descending   = $true
    }
    $MergedDesc = Merge-SortedListsOnDate @DescParams

    # perform simple assertions
    $Failures = [System.Collections.Generic.List[string]]::new()

    if ($MergedAsc.Count -ne $AllInputCount) {
        $Failures.Add("ascending: expected $AllInputCount items, got $($MergedAsc.Count)")
    }
    if ($MergedDesc.Count -ne $AllInputCount) {
        $Failures.Add("descending: expected $AllInputCount items, got $($MergedDesc.Count)")
    }

    if (-not (Test-IsSortedOn -List $MergedAsc -PropertyName 'When' -Ascending $true)) {
        $Failures.Add('ascending: merge result is not sorted ascending on When')
    }
    if (-not (Test-IsSortedOn -List $MergedDesc -PropertyName 'When' -Ascending $false)) {
        $Failures.Add('descending: merge result is not sorted descending on When')
    }

    # spot-check boundaries
    $AscFirst = if ($MergedAsc.Count) { $MergedAsc[0].When } else { $null }
    $AscLast = if ($MergedAsc.Count) { $MergedAsc[-1].When } else { $null }
    $DescFirst = if ($MergedDesc.Count) { $MergedDesc[0].When } else { $null }
    $DescLast = if ($MergedDesc.Count) { $MergedDesc[-1].When } else { $null }

    if ($AscFirst -ne [datetime]'2025-01-01' -or $AscLast -ne [datetime]'2025-01-07') {
        $Failures.Add('ascending: first/last boundary dates are incorrect')
    }
    if ($DescFirst -ne [datetime]'2025-01-07' -or $DescLast -ne [datetime]'2025-01-01') {
        $Failures.Add('descending: first/last boundary dates are incorrect')
    }

    # build result object
    $Result = [pscustomobject]@{
        Passed           = ($Failures.Count -eq 0)
        FailureCount     = $Failures.Count
        Failures         = if ($Failures.Count) { $Failures } else { @() }
        TotalInputItems  = $AllInputCount
        AscendingCount   = $MergedAsc.Count
        DescendingCount  = $MergedDesc.Count
        AscendingFirst   = $AscFirst
        AscendingLast    = $AscLast
        DescendingFirst  = $DescFirst
        DescendingLast   = $DescLast
        ShowMergedHint   = 're-run with -ShowMerged to see merged outputs'
    }

    if ($ShowMerged) {
        # when requested, also emit the merged lists (as properties to avoid noisy pipeline output)
        $Result | Add-Member -NotePropertyName 'MergedAscending'  -NotePropertyValue $MergedAsc
        $Result | Add-Member -NotePropertyName 'MergedDescending' -NotePropertyValue $MergedDesc
    }

    # return the summary object; no extraneous screen output
    Write-Output $Result
}