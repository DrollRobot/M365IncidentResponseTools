function Add-IpAddressConditionalFormatting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Worksheet,

        [Parameter(Mandatory)]
        [string]$ColumnName
    )

    $IpAddressColumn = ($Worksheet.Tables[0].Columns | Where-Object {$_.Name -eq $ColumnName}).Id | Convert-DecimalToExcelColumn

    # microsoft
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue  = 'microsoft'
        BackgroundColor = 'LightBlue'
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # vpn
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue  = ' vpn'
        BackgroundColor = 'LightPink'
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # tor
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue = ' tor'
        BackgroundColor = 'LightPink'
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # proxy
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue = ' proxy'
        BackgroundColor = 'LightPink'
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # hosting
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue  = ' hosting'
        BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#FACD90')
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # cloud
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue  = ' cloud'
        BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#FACD90')
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
    # mobile
    $CFParams = @{
        Worksheet       = $WorkSheet
        Address         = "${IpAddressColumn}:${IpAddressColumn}"
        RuleType        = 'ContainsText'
        ConditionValue  = 'mobile'
        BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#F2CEEF')
        StopIfTrue = $true
    }
    Add-ConditionalFormatting @CFParams
}
