function Add-IpInfoToSheet {
    <#
    .SYNOPSIS
    Enriches IP address cells in an Excel worksheet with ip_info lookup data.

    .DESCRIPTION
    Reads IP addresses from the specified column(s) of an already-exported worksheet,
    queries ip_info for any not yet cached in $Global:IRT_IpInfo, then rewrites each
    cell as "ip1, ip2 [padding]\n\ntable1\n\ntable2". Handles comma-separated multi-IP
    cells (e.g., UAL rows with multiple source addresses).

    Does nothing if $Global:IRT_Config.IpInfoAvailable is $false or the worksheet has
    no table.

    .PARAMETER Worksheet
    An OfficeOpenXml worksheet object (e.g., from $Workbook.Workbook.Worksheets['Name']).

    .PARAMETER ColumnName
    One or more column names to enrich. Columns not present in the worksheet are
    silently skipped.

    .EXAMPLE
    Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'IpAddress'

    .EXAMPLE
    Add-IpInfoToSheet -Worksheet $Worksheet -ColumnName 'FromIP', 'ToIP'

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [AllowNull()]
        [Parameter(Mandatory)]
        $Worksheet,

        [Parameter(Mandatory)]
        [string[]] $ColumnName
    )

    if (-not $Global:IRT_Config.IpInfoAvailable) { return }
    if ($null -eq $Worksheet) { return }
    if ($Worksheet.Tables.Count -eq 0) { return }

    $Table = $Worksheet.Tables[0]
    $TableStartCol = $Table.Address.Start.Column
    $DataStartRow = $Table.Address.Start.Row + 1  # row 1 is the header
    $DataEndRow = $Table.Address.End.Row

    if ($DataEndRow -lt $DataStartRow) { return }

    # Build column-index map for requested columns that exist in this worksheet.
    $ColMap = @{}
    foreach ($Name in $ColumnName) {
        $TableCol = $Table.Columns | Where-Object { $_.Name -eq $Name }
        if ($TableCol) {
            $ColMap[$Name] = $TableStartCol + $TableCol.Id - 1
        }
    }
    if ($ColMap.Count -eq 0) { return }

    # First pass: collect all unique IPs across all target columns.
    $AllIps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($AbsCol in $ColMap.Values) {
        for ($Row = $DataStartRow; $Row -le $DataEndRow; $Row++) {
            $CellValue = $Worksheet.Cells[$Row, $AbsCol].Value
            if (-not $CellValue) { continue }
            foreach ($Part in ($CellValue -split ', ')) {
                $IpObj = $null
                if ([System.Net.IPAddress]::TryParse($Part.Trim(), [ref]$IpObj)) {
                    [void]$AllIps.Add($IpObj.ToString())
                }
            }
        }
    }
    if ($AllIps.Count -eq 0) { return }

    # Query ip_info for any IPs not already in the cache.
    $IpInfoTable = $Global:IRT_IpInfo
    $UnseenIps = @($AllIps | Where-Object { -not $IpInfoTable.ContainsKey($_) })
    if ($UnseenIps.Count -gt 0) {
        $env:PYTHONUTF8 = '1'
        $RawOutput = @(& ip_info --apis bulk --output_format jsontable --ip_addresses $UnseenIps)
        if ($LASTEXITCODE -ne 0) {
            Write-IRT "ip_info query failed (exit $LASTEXITCODE)." -Level Error
            return
        }
        $JsonStart = -1
        for ($i = 0; $i -lt $RawOutput.Length; $i++) {
            if ($RawOutput[$i] -match '^\{') { $JsonStart = $i; break }
        }
        if ($JsonStart -ge 0) {
            $JsonText = ($RawOutput[$JsonStart..($RawOutput.Length - 1)]) -join "`n"
            $JsonData = $JsonText | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($JsonData) {
                foreach ($Prop in $JsonData.PSObject.Properties) {
                    $IpInfoTable[$Prop.Name] = $Prop.Value
                }
            }
        }
    }

    # Second pass: rewrite cells with enriched content.
    foreach ($Name in $ColMap.Keys) {
        $AbsCol = $ColMap[$Name]
        for ($Row = $DataStartRow; $Row -le $DataEndRow; $Row++) {
            $Cell = $Worksheet.Cells[$Row, $AbsCol]
            $CellValue = $Cell.Value
            if (-not $CellValue) { continue }

            $ValidIps = [System.Collections.Generic.List[string]]::new()
            foreach ($Part in ($CellValue -split ', ')) {
                $IpObj = $null
                if ([System.Net.IPAddress]::TryParse($Part.Trim(), [ref]$IpObj)) {
                    [void]$ValidIps.Add($IpObj.ToString())
                }
            }
            if ($ValidIps.Count -eq 0) { continue }

            $CellLines = [System.Collections.Generic.List[string]]::new()
            $CellLines.Add(($ValidIps -join ', ') + (' ' * 20))
            foreach ($Ip in $ValidIps) {
                if ($IpInfoTable.ContainsKey($Ip)) {
                    $CellLines.Add($IpInfoTable[$Ip])
                }
            }

            # Only rewrite if we actually have enrichment data to add.
            if ($CellLines.Count -gt 1) {
                $Cell.Value = $CellLines -join "`n`n"
            }
        }
    }

    # Apply conditional formatting rules from the template for each enriched column.
    # ExcelWorkbook.Package is not a public property in the bundled EPPlus build.
    # Retrieve it via the non-public _package backing field so CF can be applied.
    $BindFlags = [System.Reflection.BindingFlags]'NonPublic,Instance'
    $PkgField = $Worksheet.Workbook.GetType().GetField('_package', $BindFlags)
    $DestPackage = if ($PkgField) { $PkgField.GetValue($Worksheet.Workbook) } else { $null }

    if ($null -ne $DestPackage) {
        foreach ($Name in $ColMap.Keys) {
            $ColLetter = $ColMap[$Name] | Convert-DecimalToExcelColumn
            $CopyParams = @{
                Source           = $Global:IRT_Config.IPConditionalFormattingTemplatePath
                SourceRange      = 'A1:A1048576'
                Destination      = $DestPackage
                DestinationSheet = $Worksheet.Name
                DestinationRange = "${ColLetter}:${ColLetter}"
            }
            Copy-ConditionalFormatting @CopyParams
        }
    }
}