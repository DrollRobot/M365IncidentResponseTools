function Copy-ConditionalFormatting {
    <#
.SYNOPSIS
    Copies every conditional-formatting rule that touches a source range onto a destination range,
    using the EPPlus object model exposed by the ImportExcel module.

.DESCRIPTION
    For each rule on the source worksheet whose address intersects -SourceRange, the rule is
    recreated on the destination worksheet and its attributes (formula(s), text, rank/percent,
    std-dev, value objects for colour scales / data bars / icon sets, and the full dxf style)
    are copied across.

    Geometry is handled Format-Painter style: each rule's address is first clipped to -SourceRange,
    then shifted by the offset between the source range's top-left cell and the destination range's
    top-left cell. The size of -DestinationRange is therefore ignored - only its anchor (top-left)
    matters, so you may pass a full range ("H2:K20") or just the anchor cell ("H2").

    Rules are RECREATED rather than cloned, because EPPlus conditional-formatting rules are
    worksheet-scoped but the styles they reference are workbook-scoped; copying rule objects
    directly between packages produces invalid DxfId references.

.PARAMETER Source
    A file path (string) or an OfficeOpenXml.ExcelPackage object (e.g. from Open-ExcelPackage).
    If a path is given the package is opened here and closed WITHOUT saving when done.

.PARAMETER SourceSheet
    Source worksheet name. Optional when the source workbook has exactly one sheet.

.PARAMETER SourceRange
    A1-style range whose conditional formatting should be copied, e.g. "A2:D100".

.PARAMETER Destination
    The destination OfficeOpenXml.ExcelPackage object (or a file path). If an object is passed it
    is left open and is NOT saved - the caller is responsible for Close-ExcelPackage. If a path is
    passed it is opened here and saved + closed when done.

.PARAMETER DestinationSheet
    Destination worksheet name. Optional when the destination workbook has exactly one sheet.

.PARAMETER DestinationRange
    Destination anchor. Pass a full range or just the top-left cell, e.g. "H2".

.EXAMPLE
    $dst = Open-ExcelPackage -Path .\report.xlsx
    $params = @{
        Source           = '.\template.xlsx'
        SourceRange      = 'A2:D50'
        Destination      = $dst
        DestinationSheet = 'Data'
        DestinationRange = 'A2'
    }
    Copy-ConditionalFormatting @params
    Close-ExcelPackage $dst   # caller saves the destination

.NOTES
    * Relative references inside rule formulas are copied VERBATIM and are NOT re-based to the new
      location (this mirrors EPPlus, which does not adjust formulas when an address changes). Keep
      source and destination in the same columns/rows, or use absolute ($) references, to avoid
      surprises. A warning is emitted when a non-zero offset is applied.
    * Colour scales, data bars and icon sets are copied best-effort (value objects + colours).
    * Any rule that cannot be recreated is skipped with a warning; the rest still copy.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Source,
        [Parameter(Mandatory)] [string] $SourceRange,
        [Parameter(Mandatory)] [object] $Destination,
        [Parameter(Mandatory)] [string] $DestinationRange,
        [string] $SourceSheet,
        [string] $DestinationSheet
    )

    # ---------------------------------------------------------------- helpers ----
    function resolvePackage($in, [string]$role) {
        if ($in -is [string]) {
            if (-not (Test-Path -LiteralPath $in)) { throw "$role file not found: $in" }
            return @{ Package = (Open-ExcelPackage -Path $in); Opened = $true }
        }
        if ($in -isnot [OfficeOpenXml.ExcelPackage]) {
            $msg = "$role must be a file path or an OfficeOpenXml.ExcelPackage; " +
            "got [$($in.GetType().FullName)]."
            throw $msg
        }
        return @{ Package = $in; Opened = $false }
    }

    function resolveSheet($pkg, [string]$name, [string]$role) {
        $wb = $pkg.Workbook
        $names = @($wb.Worksheets | ForEach-Object Name)
        if ($name) {
            $ws = $wb.Worksheets[$name]
            if (-not $ws) {
                throw "$role worksheet '$name' not found. Available: $($names -join ', ')"
            }
            return $ws
        }
        if ($wb.Worksheets.Count -eq 1) { return $wb.Worksheets[1] }
        $msg = "$role workbook has $($wb.Worksheets.Count) sheets; specify the sheet name. " +
        "Available: $($names -join ', ')"
        throw $msg
    }

    # Return list of {FromRow,FromCol,ToRow,ToCol} for single- or multi-area addresses.
    function getAreas($address) {
        $out = New-Object System.Collections.Generic.List[object]
        $subs = $address.Addresses
        $list = if ($subs) { $subs } else { @($address) }
        foreach ($a in $list) {
            $out.Add([pscustomobject]@{
                    FromRow = $a.Start.Row; FromCol = $a.Start.Column
                    ToRow   = $a.End.Row; ToCol   = $a.End.Column
                })
        }
        return $out
    }

    function copyDxfColor($s, $d) {
        if (-not $s -or -not $d) { return }
        foreach ($p in 'Color', 'Theme', 'Index', 'Tint', 'Auto') {
            $sv = $s.$p
            if ($null -ne $sv) { try { $d.$p = $sv } catch {} }
        }
    }

    function copyDxfStyle($s, $d) {
        if (-not $s -or -not $d) { return }
        if ($s.NumberFormat -and $s.NumberFormat.Format) {
            try { $d.NumberFormat.Format = $s.NumberFormat.Format } catch {}
        }
        if ($s.Font -and $d.Font) {
            foreach ($p in 'Bold', 'Italic', 'Strike', 'Underline') {
                $sv = $s.Font.$p
                if ($null -ne $sv) { try { $d.Font.$p = $sv } catch {} }
            }
            copyDxfColor $s.Font.Color $d.Font.Color
        }
        if ($s.Fill -and $d.Fill) {
            $sv = $s.Fill.PatternType
            if ($null -ne $sv) { try { $d.Fill.PatternType = $sv } catch {} }
            copyDxfColor $s.Fill.BackgroundColor $d.Fill.BackgroundColor
            copyDxfColor $s.Fill.PatternColor    $d.Fill.PatternColor
        }
        if ($s.Border -and $d.Border) {
            foreach ($edge in 'Left', 'Right', 'Top', 'Bottom') {
                $sb = $s.Border.$edge; $db = $d.Border.$edge
                if ($sb -and $db) {
                    $sv = $sb.Style
                    if ($null -ne $sv) { try { $db.Style = $sv } catch {} }
                    copyDxfColor $sb.Color $db.Color
                }
            }
        }
    }

    # Copy a conditional-format value object (cfvo): used by colour scales, data bars, icon sets.
    function copyValueObject($s, $d) {
        if (-not $s -or -not $d) { return }
        foreach ($p in 'Type', 'Value', 'Formula', 'Color') {
            if ($s.PSObject.Properties[$p] -and $d.PSObject.Properties[$p]) {
                $sv = $s.$p
                if ($null -ne $sv) { try { $d.$p = $sv } catch {} }
            }
        }
    }

    function copyScalars($s, $d) {
        foreach ($p in 'StopIfTrue', 'Formula', 'Formula2', 'Text', 'Rank', 'Percent', 'StdDev') {
            if ($s.PSObject.Properties[$p] -and $d.PSObject.Properties[$p]) {
                $sv = $s.$p
                if ($null -ne $sv) { try { $d.$p = $sv } catch {} }
            }
        }
    }
    # -----------------------------------------------------------------------------

    $srcInfo = $null; $dstInfo = $null
    try {
        $srcInfo = resolvePackage $Source      'Source'
        $dstInfo = resolvePackage $Destination 'Destination'

        $srcSheet = resolveSheet -pkg $srcInfo.Package -name $SourceSheet -role 'Source'
        $dstSheet = resolveSheet -pkg $dstInfo.Package -name $DestinationSheet -role 'Destination'

        $srcAddr = [OfficeOpenXml.ExcelAddress]::new($SourceRange)
        $dstAddr = [OfficeOpenXml.ExcelAddress]::new($DestinationRange)

        $sr1 = $srcAddr.Start.Row; $sc1 = $srcAddr.Start.Column
        $sr2 = $srcAddr.End.Row; $sc2 = $srcAddr.End.Column

        $rowOffset = $dstAddr.Start.Row - $sr1
        $colOffset = $dstAddr.Start.Column - $sc1

        if (($rowOffset -ne 0 -or $colOffset -ne 0)) {
            $Offset = "rows: $rowOffset, cols: $colOffset"
            $WarnMsg = "Copy-ConditionalFormatting: Applying offset ($Offset). " +
            'Relative references inside rule formulas are copied ' +
            'as-is and will NOT be re-based.'
            Write-Warning $WarnMsg
        }

        $cf = $dstSheet.ConditionalFormatting
        $copied = 0

        # Snapshot source rules first to prevent mutate-while-enumerate on the same sheet.
        foreach ($rule in @($srcSheet.ConditionalFormatting)) {
            if (-not $rule.Address) { continue }

            # Build the destination address: clip each area to the source range, then offset.
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($a in (getAreas $rule.Address)) {
                $ir1 = [math]::Max($a.FromRow, $sr1); $ic1 = [math]::Max($a.FromCol, $sc1)
                $ir2 = [math]::Min($a.ToRow, $sr2); $ic2 = [math]::Min($a.ToCol, $sc2)
                if ($ir1 -le $ir2 -and $ic1 -le $ic2) {
                    $parts.Add([OfficeOpenXml.ExcelCellBase]::GetAddress(
                            ($ir1 + $rowOffset), ($ic1 + $colOffset),
                            ($ir2 + $rowOffset), ($ic2 + $colOffset)))
                }
            }
            if ($parts.Count -eq 0) { continue }   # rule does not touch the source range

            $newAddrString = $parts -join ' '
            $typeName = $rule.Type.ToString()

            try {
                $addr = [OfficeOpenXml.ExcelAddress]::new($newAddrString)
                $addName = "Add$typeName"

                # Most types take just the address. Icon sets need the icon-set type; the data bar
                # needs a colour (and its method is 'AddDatabar', not 'AddDataBar').
                $newRule =
                if ($typeName -in 'ThreeIconSet', 'FourIconSet', 'FiveIconSet') {
                    $cf.$addName($addr, $rule.IconSet)
                }
                elseif ($typeName -eq 'DataBar') {
                    $cf.AddDatabar($addr, $rule.Color)
                }
                else {
                    $cf.$addName($addr)
                }

                copyScalars $rule $newRule

                foreach ($vo in 'LowValue', 'MiddleValue', 'HighValue') {
                    if ($rule.PSObject.Properties[$vo] -and $newRule.PSObject.Properties[$vo]) {
                        copyValueObject $rule.$vo $newRule.$vo
                    }
                }
                foreach ($ic in 'Icon1', 'Icon2', 'Icon3', 'Icon4', 'Icon5') {
                    if ($rule.PSObject.Properties[$ic] -and $newRule.PSObject.Properties[$ic]) {
                        copyValueObject $rule.$ic $newRule.$ic
                    }
                }
                foreach ($p in 'Reverse', 'ShowValue') {
                    if ($rule.PSObject.Properties[$p] -and $newRule.PSObject.Properties[$p]) {
                        $sv = $rule.$p
                        if ($null -ne $sv) { try { $newRule.$p = $sv } catch {} }
                    }
                }

                if ($rule.PSObject.Properties['Style'] -and
                    $newRule.PSObject.Properties['Style'] -and $rule.Style) {
                    copyDxfStyle $rule.Style $newRule.Style
                }

                $copied++
                Write-Verbose "Copied '$typeName' rule -> $newAddrString"
            }
            catch {
                $warnMsg = ("Skipped rule (type '{0}', source '{1}'): {2}" -f
                    $typeName, $rule.Address.Address, $_.Exception.Message)
                Write-Warning $warnMsg
            }
        }

        Write-Verbose "Copied $copied conditional-formatting rule(s) to $($dstSheet.Name)."
    }
    finally {
        # Close only packages we opened: source is discarded; a path-based destination is saved.
        if ($srcInfo -and $srcInfo.Opened) {
            Close-ExcelPackage -ExcelPackage $srcInfo.Package -NoSave
        }
        if ($dstInfo -and $dstInfo.Opened) {
            Close-ExcelPackage -ExcelPackage $dstInfo.Package
        }
    }
}