function Merge-ListsOnDate {
    # merges lists
    [CmdletBinding(DefaultParameterSetName = 'Ascending')]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[psobject][]] $Lists,

        [Parameter(Mandatory = $true)]
        [string] $PropertyName,

        [Parameter(Mandatory, ParameterSetName = 'Ascending')]
        [switch] $Ascending,

        [Parameter(Mandatory, ParameterSetName = 'Descending')]
        [switch] $Descending
    )

    # helper: check if a list is sorted on property in the requested direction
    function Test-IsSorted {
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

    # helper: ensure each list is sorted; if not, sort it into a new list
    function Get-WorkingLists {
        param(
            [System.Collections.Generic.List[psobject][]] $InputLists,
            [string] $KeyProperty,
            [bool] $IsAscending
        )
        $Working = New-Object 'System.Collections.Generic.List[System.Collections.Generic.List[psobject]]'
        foreach ($SingleList in $InputLists) {
            if (-not $SingleList -or $SingleList.Count -eq 0) {
                $Working.Add([System.Collections.Generic.List[psobject]]::new())
                continue
            }

            if (Test-IsSorted -InputList $SingleList -KeyProperty $KeyProperty -IsAscending $IsAscending) {
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
        return ,$Working
    }

    # validate at least one list exists
    if (-not $Lists -or $Lists.Count -eq 0) {
        return [System.Collections.Generic.List[psobject]]::new()
    }

    # determine direction bool once
    $IsAscending = [bool]$Ascending

    # build working lists (sorted if needed)
    $WorkingLists = Get-WorkingLists -InputLists $Lists -KeyProperty $PropertyName -IsAscending $IsAscending

    # try to use PriorityQueue if available (PowerShell 7+ / .NET 6+)
    $PriorityQueueType = $null
    try {
        $PriorityQueueType = [System.Collections.Generic.PriorityQueue``2].MakeGenericType([psobject], [long])
    } catch {
        $PriorityQueueType = $null
    }

    # if property looks like DateTime, prefer ticks for priority; otherwise fall back at runtime
    $GetPriority = {
        param($Value, [bool] $Asc)
        if ($Value -is [datetime]) {
            $Ticks = [long]$Value.Ticks
            if ($Asc) { return $Ticks }
            else { return [long]::MaxValue - $Ticks }
        }
        elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
            $Num = [double]$Value
            if ($Asc) { return [long][math]::Round($Num) }
            else { return [long][math]::Round([double]::MaxValue - $Num) } # crude reversal for numerics
        }
        else {
            # fallback: try string collation using ordinal bytes (less ideal); reverse by prefixing weight
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
            $Hash  = [System.BitConverter]::ToInt64((New-Object byte[] 8), 0)
            # the above is a placeholder to force fallback; return 0 so we trip the non-PQ path
            return 0
        }
    }

    # if PriorityQueue is available and the key type is suitable, use it; otherwise use portable k-way scan
    $UsePriorityQueue = $false
    if ($PriorityQueueType -ne $null) {
        # quick probe first non-null key
        $ProbeKey = $null
        foreach ($List in $WorkingLists) {
            if ($List.Count -gt 0) {
                $ProbeKey = $List[0].$PropertyName
                if ($ProbeKey -ne $null) { break }
            }
        }
        if ($ProbeKey -is [datetime] -or $ProbeKey -is [int] -or $ProbeKey -is [long] -or $ProbeKey -is [double] -or $ProbeKey -is [decimal] -or $ProbeKey -is [single]) {
            $UsePriorityQueue = $true
        }
    }

    $MergedList = [System.Collections.Generic.List[psobject]]::new()

    if ($UsePriorityQueue) {
        # priority-queue merge (O(N log k))
        $Queue = [Activator]::CreateInstance($PriorityQueueType)

        # track current indexes per list
        $CurrentIndexes = [System.Collections.Generic.List[int]]::new()
        foreach ($L in $WorkingLists) { $CurrentIndexes.Add(0) }

        # enqueue first element from each list
        for ($ListIndex = 0; $ListIndex -lt $WorkingLists.Count; $ListIndex++) {
            $IndexInList = $CurrentIndexes[$ListIndex]
            if ($IndexInList -ge $WorkingLists[$ListIndex].Count) { continue }
            $Item = $WorkingLists[$ListIndex][$IndexInList]
            $Key  = $Item.$PropertyName
            $Priority = & $GetPriority $Key $IsAscending
            # if priority equals zero due to unknown type, bail to portable path
            if ($Priority -eq 0 -and -not ($Key -is [datetime])) {
                $UsePriorityQueue = $false
                break
            }
            # store a small envelope with list index and item index
            $Envelope = [pscustomobject]@{
                ListIndex = $ListIndex
                ItemIndex = $IndexInList
                Item      = $Item
            }
            $null = $Queue.Enqueue($Envelope, $Priority)
        }

        if ($UsePriorityQueue) {
            while ($Queue.Count -gt 0) {
                $OutEnvelope = $null
                $OutPriority = 0L
                $null = $Queue.TryDequeue([ref]$OutEnvelope, [ref]$OutPriority)
                $MergedList.Add($OutEnvelope.Item)

                # advance the corresponding list and enqueue next
                $ListIndex = $OutEnvelope.ListIndex
                $CurrentIndexes[$ListIndex] = $CurrentIndexes[$ListIndex] + 1
                $NextIndex = $CurrentIndexes[$ListIndex]
                if ($NextIndex -lt $WorkingLists[$ListIndex].Count) {
                    $NextItem = $WorkingLists[$ListIndex][$NextIndex]
                    $NextKey  = $NextItem.$PropertyName
                    $NextPriority = & $GetPriority $NextKey $IsAscending
                    $NextEnvelope = [pscustomobject]@{
                        ListIndex = $ListIndex
                        ItemIndex = $NextIndex
                        Item      = $NextItem
                    }
                    $null = $Queue.Enqueue($NextEnvelope, $NextPriority)
                }
            }

            return $MergedList
        }
        # else fall through to portable path
    }

    # portable k-way scan (works everywhere; O(N * k))
    $CurrentPortableIndexes = [System.Collections.Generic.List[int]]::new()
    foreach ($L in $WorkingLists) { $CurrentPortableIndexes.Add(0) }

    while ($true) {
        $SelectedListIndex = -1
        $SelectedValue = $null

        for ($ListIndex = 0; $ListIndex -lt $WorkingLists.Count; $ListIndex++) {
            $IndexInList = $CurrentPortableIndexes[$ListIndex]
            if ($IndexInList -ge $WorkingLists[$ListIndex].Count) { continue }

            $Candidate = $WorkingLists[$ListIndex][$IndexInList]
            $CandidateValue = $Candidate.$PropertyName

            if ($SelectedListIndex -eq -1) {
                $SelectedListIndex = $ListIndex
                $SelectedValue = $CandidateValue
                continue
            }

            if ($IsAscending) {
                if ($CandidateValue -lt $SelectedValue) {
                    $SelectedListIndex = $ListIndex
                    $SelectedValue = $CandidateValue
                }
            } else {
                if ($CandidateValue -gt $SelectedValue) {
                    $SelectedListIndex = $ListIndex
                    $SelectedValue = $CandidateValue
                }
            }
        }

        if ($SelectedListIndex -eq -1) { break }

        $MergedList.Add($WorkingLists[$SelectedListIndex][$CurrentPortableIndexes[$SelectedListIndex]])
        $CurrentPortableIndexes[$SelectedListIndex] = $CurrentPortableIndexes[$SelectedListIndex] + 1
    }

    return $MergedList
}


function Test-MergeSortedListsOnDate {
    [CmdletBinding()]
    param(
        # show merged outputs (off by default to keep output minimal)
        [switch] $ShowMerged
    )

    # helper: build a strongly-typed list[psobject] from an array of datetimes
    function New-DateList {
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
            $Prev = $List[$I-1].$PropertyName
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
    $ListOne  = New-DateList -Dates @(
        [datetime]'2025-01-01',
        [datetime]'2025-01-03',
        [datetime]'2025-01-05'
    ) -Tag 'L1'

    $ListTwo  = New-DateList -Dates @(
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
    $AscLast  = if ($MergedAsc.Count) { $MergedAsc[-1].When } else { $null }
    $DescFirst = if ($MergedDesc.Count) { $MergedDesc[0].When } else { $null }
    $DescLast  = if ($MergedDesc.Count) { $MergedDesc[-1].When } else { $null }

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