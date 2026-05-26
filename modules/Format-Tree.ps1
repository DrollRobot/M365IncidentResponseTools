# suppress PSScriptAnalyzer warnings for all functions
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', '')]
param()

#region Format-Tree
function Format-Tree {
<#
displays a simple tree view of any object (ps 5.1+)
- property names are light green on ps 7+; values default color
- pass -OmitNullOrEmpty to hide nulls, empty strings, empty containers, and empty objects
- pass -ExcludeProperty to omit properties by name anywhere in the tree (case-insensitive)
- multiline values align continuation lines under the value column
- no artificial root line; first properties start at zero indentation
#>
    [Alias('FTree', 'FTr')]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Depth',
        Justification = 'Used by Out-Print helper function via PowerShell dynamic scoping.')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Position=0, Mandatory)]
        [int] $Depth,
        [int] $IndentSize = 4,
        [Alias('NewLines')] [bool] $NewLine = $true,

        # hide nulls, empty strings, empty arrays/maps, and objects with no visible children
        [switch] $OmitNullOrEmpty,

        # property names to exclude anywhere (case-insensitive)
        [string[]] $ExcludeProperty
    )

    begin {

        $Script:Green = @{ForegroundColor = 'Green'}
        $Script:Red = @{ForegroundColor = 'Red'}

        # case-insensitive exclude set
        $ExcludeSet = $null
        if ($ExcludeProperty) {
            $ExcludeSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase
            )
            foreach ($n in $ExcludeProperty) {
                [void]$ExcludeSet.Add($n)
            }
        }

        # empty line before and after, similar to Format-Table, Format-List
        if ($NewLine) {
            Write-Host ''
        }
    }

    process {

        # root handling
        if (Test-IsScalar $InputObject) {
            if (-not ($OmitNullOrEmpty -and (Test-IsEmptyScalar $InputObject))) {
                Write-Host ([string]$InputObject)
            }
            return
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            foreach ($Key in ($InputObject.Keys | Sort-Object)) {
                Out-Print ("[$Key]") $InputObject[$Key] 0 | Out-Null
            }
            return
        }

        $RootNames = Get-PropertyName $InputObject
        if (($RootNames | Measure-Object).Count -gt 0) {
            if ($ExcludeSet) {
                $RootNames = $RootNames | Where-Object { -not $ExcludeSet.Contains($_) }
            }
            foreach ($Name in $RootNames) {
                try {
                    $Value = $InputObject.PSObject.Properties[$Name].Value
                }
                catch {
                    $Value = $null
                }
                Out-Print $Name $Value 0 | Out-Null
            }
            return
        }

        if ($InputObject -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($E in $InputObject) {
                Out-Print ("[{0}]" -f $i) $E 0 | Out-Null
                $i++
            }
            return
        }

        Write-NameValue '<root>' ('<{0}>' -f $InputObject.GetType().FullName) 0 $IndentSize
    }

    end {
        # empty line before and after, similar to Format-Table, Format-List
        if ($NewLine) {
            Write-Host ''
        }
    }
}

function Get-Indent([int]$CurrentDepth, [int]$Size) {
    ' ' * ($CurrentDepth * $Size)
}

function Get-PropertyName($Obj) {
    $Obj.PSObject.Properties |
        Where-Object { $_.IsGettable -and $_.MemberType -in 'NoteProperty','Property','AliasProperty' } |
        Select-Object -ExpandProperty Name -Unique |
        Sort-Object
}

function Out-Print {
    param(
        [Parameter(Position=0)]
        [string] $Name,
        [Parameter(Position=1)]
        $Value,
        [Parameter(Position=2)]
        [int] $CurrentDepth
    )

    # print node (returns $true if anything was printed)
    if ($CurrentDepth -gt $Depth) { return $false }

    $Value = Resolve-Json $Value

    if ($null -eq $Value) {
        if (-not $OmitNullOrEmpty) { Write-NameValue $Name '<null>' $CurrentDepth $IndentSize; return $true }
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
                if (-not $Printed) { Write-NameValue $Name '' $CurrentDepth $IndentSize; $Printed = $true }
                Out-Print ("[$Key]") $Value[$Key] ($CurrentDepth + 1) | Out-Null
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
                $Visible += ,$E
            }
        }
        if ($Visible.Count -eq 0) {
            return $false
        }
        Write-NameValue $Name ("[{0}]" -f $Visible.Count) $CurrentDepth $IndentSize
        for ($i = 0; $i -lt $Visible.Count; $i++) {
            Out-Print ("[{0}]" -f $i) $Visible[$i] ($CurrentDepth + 1) | Out-Null
        }
        return $true
    }

    $Names = Get-PropertyName $Value
    if ($ExcludeSet) { $Names = $Names | Where-Object { -not $ExcludeSet.Contains($_) } }

    $Pairs = @()
    foreach ($N in $Names) {
        try { $V = $Value.PSObject.Properties[$N].Value } catch { $V = $null }
        if (Test-HasVisible $V ($CurrentDepth + 1)) { $Pairs += ,@($N,$V) }
    }
    if ($Pairs.Count -eq 0) { return $false }

    Write-NameValue $Name '' $CurrentDepth $IndentSize
    foreach ($P in $Pairs) { Out-Print $P[0] $P[1] ($CurrentDepth + 1) | Out-Null }
    return $true
}

function Resolve-Json($Value) {

    ### if it's a string that looks like json, try to parse it (handles one level of json-in-a-string)
    # if the value is anything other than string, return it
    if ($Value -isnot [string]) { return $Value }
    $String = $Value.Trim()
    # if the string starts and ends with brackets or braces, set LooksLikeJson to true
    $LooksLikeJson = ($String.StartsWith('{') -and $String.EndsWith('}')) -or ($String.StartsWith('[') -and $String.EndsWith(']'))
    if (-not $LooksLikeJson) { return $Value }

    try {
        # convert from json
        $Parsed = $String | ConvertFrom-Json -ErrorAction Stop
        # if the parsed result is itself a json-looking string, try one more pass
        if ($Parsed -is [string]) {
            $Inner = $Parsed.Trim()
            $InnerLooksLike = ($Inner.StartsWith('{') -and $Inner.EndsWith('}')) -or ($Inner.StartsWith('[') -and $Inner.EndsWith(']'))
            if ($InnerLooksLike) {
                try { return ($Inner | ConvertFrom-Json -ErrorAction Stop) } catch { return $Parsed }
            }
        }
        return $Parsed
    } catch { return $Value }
}


function Test-IsEmptyScalar($Value) { ($Value -is [string]) -and [string]::IsNullOrWhiteSpace($Value) }

function Test-IsScalar($Value) {
    # treat common primitives as scalars (and helpful extras)
    $Value -is [string]   -or $Value -is [bool]     -or
    $Value -is [int]      -or $Value -is [long]     -or
    $Value -is [double]   -or $Value -is [decimal]  -or
    $Value -is [datetime] -or $Value -is [guid]     -or
    $Value -is [timespan] -or $Value -is [uri]      -or
    $Value -is [version]  -or $Value -is [enum]
}

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
        foreach ($Key in $Value.Keys) { if (Test-HasVisible $Value[$Key] ($CurrentDepth + 1)) { return $true } }
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

function Write-NameEllipsis([string]$Name, [int]$CurrentDepth, [int]$Size) {
    $indent = Get-Indent $CurrentDepth $Size
    Write-Host -NoNewline $indent
    Write-Host -NoNewline @Green ($Name + ': ')
    Write-Host @Red '...'
}

function Write-NameValue([string]$Name, [string]$ValueText, [int]$CurrentDepth, [int]$Size) {
    $Indent      = Get-Indent $CurrentDepth $Size
    $PlainPrefix = $Indent + $Name + ': '
    $ContIndent  = ' ' * ($PlainPrefix.Length)
    $Lines = [regex]::Split($ValueText, '(?:\r\n|\n|\r)'); if ($Lines.Count -eq 0) { $Lines = @('') }

    if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSStyle) {
        $First = $Indent + $PSStyle.Foreground.BrightGreen + $Name + $PSStyle.Reset + ': ' + $Lines[0]
        Write-Host $First
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            Write-Host ($ContIndent + $Lines[$i])
        }
    } else {
        Write-Host @Green ($PlainPrefix + $Lines[0])
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            Write-Host ($ContIndent + $Lines[$i])
        }
    }
}
