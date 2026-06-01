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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console output for terminal display function.')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Position = 0, Mandatory)]
        [int] $Depth,
        [int] $IndentSize = 4,
        [Alias('NewLines')] [bool] $NewLine = $true,

        # hide nulls, empty strings, empty arrays/maps, and objects with no visible children
        [switch] $OmitNullOrEmpty,

        # property names to exclude anywhere (case-insensitive)
        [string[]] $ExcludeProperty
    )

    begin {

        $Script:Green = @{ForegroundColor = 'Green' }
        $Script:Red = @{ForegroundColor = 'Red' }

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
                $null = Out-Print ("[$Key]") $InputObject[$Key] 0
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
                $null = Out-Print $Name $Value 0
            }
            return
        }

        if ($InputObject -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($E in $InputObject) {
                $null = Out-Print "[$i]" $E 0
                $i++
            }
            return
        }

        Write-NameValue '<root>' "<$($InputObject.GetType().FullName)>" 0 $IndentSize
    }

    end {
        # empty line before and after, similar to Format-Table, Format-List
        if ($NewLine) {
            Write-Host ''
        }
    }
}
