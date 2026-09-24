function New-IpConditionalFormattingTemplate {
    <#
    .SYNOPSIS
    Builds the default IP address conditional-formatting template in memory.

    .DESCRIPTION
    Returns an unsaved workbook whose only worksheet carries the default IP address
    color-coding rules on column A. Add-IpInfoToSheet copies these rules onto each
    enriched IP address column when IPConditionalFormattingTemplatePath is not set.

    The rules are defined here in code rather than shipped as a bundled .xlsx template.
    Changing a rule is an edit to the list below, which reviews as a readable diff, and
    takes effect without regenerating a file.

    Each rule is a "contains text" match that fills the cell background. Rules are
    evaluated in order and stop at the first match, so an address tagged with both
    "microsoft" and " hosting" is colored as Microsoft.

    Nothing is written to disk. The caller owns the returned package and must dispose of
    it.

    .EXAMPLE
    $Template = New-IpConditionalFormattingTemplate
    try {
        $CopyParams = @{
            Source           = $Template
            SourceRange      = 'A1:A1048576'
            Destination      = $Package
            DestinationSheet = 'SignInLogs'
            DestinationRange = 'D:D'
        }
        Copy-ConditionalFormatting @CopyParams
    }
    finally {
        $Template.Dispose()
    }

    Applies the default IP address color-coding to column D of the SignInLogs sheet.

    .OUTPUTS
    OfficeOpenXml.ExcelPackage. An unsaved package holding one worksheet, IpAddress,
    with the rules applied to column A.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory workbook; changes no state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseOutputTypeCorrectly', '',
        Justification = 'Type literal fails before ImportExcel loads; PSSA ignores string form.')]
    [CmdletBinding()]
    [OutputType('OfficeOpenXml.ExcelPackage')]
    param ()

    begin {
        Import-IRTModule -Name 'ImportExcel', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name

        # Rules apply in this order and stop at the first match. The leading space on
        # most tokens keeps them from matching the end of a longer word (' tor' does
        # not match 'monitor').
        $Rules = @(
            @{ Text = 'microsoft'; Color = 'LightBlue' }
            @{ Text = 'proofpoint'; Color = '#59ABF8' }
            @{ Text = ' vpn'; Color = 'LightPink' }
            @{ Text = ' tor'; Color = 'LightPink' }
            @{ Text = ' proxy'; Color = 'LightPink' }
            @{ Text = ' hosting'; Color = '#FACD90' }
            @{ Text = ' cloud'; Color = '#FACD90' }
            @{ Text = ' datacenter'; Color = '#FACD90' }
            @{ Text = 'mobile'; Color = '#F2CEEF' }
        )
    }

    process {

        $Package = [OfficeOpenXml.ExcelPackage]::new()
        try {
            $Worksheet = $Package.Workbook.Worksheets.Add('IpAddress')

            foreach ($Rule in $Rules) {
                $CFParams = @{
                    Worksheet       = $Worksheet
                    Address         = 'A:A'
                    RuleType        = 'ContainsText'
                    ConditionValue  = $Rule.Text
                    BackgroundColor = [System.Drawing.ColorTranslator]::FromHtml($Rule.Color)
                    StopIfTrue      = $true
                }
                Add-ConditionalFormatting @CFParams
            }
        }
        catch {
            $Package.Dispose()
            throw
        }

        $RuleCount = $Worksheet.ConditionalFormatting.Count
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: built in-memory template with ${RuleCount} rules")

        $Package
    }
}
