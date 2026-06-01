function Merge-ListOnDate {
    # merges lists
    [OutputType([System.Collections.Generic.List[psobject]])]
    [CmdletBinding(DefaultParameterSetName = 'Ascending')]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Lists')]
        [System.Collections.Generic.List[psobject][]] $List,

        [Parameter(Mandatory = $true)]
        [string] $PropertyName,

        [Parameter(Mandatory, ParameterSetName = 'Ascending')]
        [switch] $Ascending,

        [Parameter(Mandatory, ParameterSetName = 'Descending')]
        [switch] $Descending
    )

    # validate at least one list exists
    if (-not $List -or $List.Count -eq 0) {
        return [System.Collections.Generic.List[psobject]]::new()
    }

    # determine direction bool once
    $IsAscending = $Ascending -and -not $Descending

    # build working lists (sorted if needed)
    $WorkingListParams = @{
        InputList   = $List
        KeyProperty = $PropertyName
        IsAscending = $IsAscending
    }
    $WorkingLists = Get-WorkingList @WorkingListParams

    # try to use PriorityQueue if available (PowerShell 7+ / .NET 6+)
    $PriorityQueueType = $null
    try {
        $PriorityQueueType = [System.Collections.Generic.PriorityQueue``2].MakeGenericType(
            [psobject], [long]
        )
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
        elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or
            $Value -is [double] -or $Value -is [single]
        ) {
            $Num = [double]$Value
            if ($Asc) { return [long][math]::Round($Num) }
            else {
                # crude reversal for numerics
                return [long][math]::Round([double]::MaxValue - $Num)
            }
        }
        else {
            return 0
        }
    }

    # if PriorityQueue is available and the key type is suitable, use it;
    # otherwise use portable k-way scan
    $UsePriorityQueue = $false
    if ($null -ne $PriorityQueueType) {
        # quick probe first non-null key
        $ProbeKey = $null
        foreach ($List in $WorkingLists) {
            if ($List.Count -gt 0) {
                $ProbeKey = $List[0].$PropertyName
                if ($null -ne $ProbeKey) { break }
            }
        }
        if ($ProbeKey -is [datetime] -or $ProbeKey -is [int] -or $ProbeKey -is [long] -or
            $ProbeKey -is [double] -or $ProbeKey -is [decimal] -or $ProbeKey -is [single]
        ) {
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
            $Key = $Item.$PropertyName
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
                    $NextKey = $NextItem.$PropertyName
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

        $PortIdx = $CurrentPortableIndexes[$SelectedListIndex]
        $MergedList.Add($WorkingLists[$SelectedListIndex][$PortIdx])
        $CurrentPortableIndexes[$SelectedListIndex] = $PortIdx + 1
    }

    return $MergedList
}
