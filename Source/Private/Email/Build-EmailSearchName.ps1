function Build-EmailSearchName {
    <#
    .SYNOPSIS
    Builds a human-readable compliance search name from email search criteria.

    .DESCRIPTION
    Pure helper for New-IRTEmailSearch. Generates a search name from the recipient
    and keyword criteria only. Date bounds are intentionally excluded so the name
    describes who/what is being searched, not when.

    Each populated property is rendered as 'Label:value' and the parts are joined
    with ' - ', e.g. 'From:sus@hacker.com - Subject:Payroll change. Click NOW'. When
    no name-eligible criteria are set, a timestamped fallback name is returned. The
    result is truncated to -MaxLength characters.

    .PARAMETER Criteria
    An ordered dictionary of search criteria. See Build-EmailSearchQuery for the
    recognized keys. Only From, To, Participants, Recipients, Subject, Body, and
    AttachmentName contribute to the name.

    .PARAMETER MaxLength
    Maximum length of the returned name. Default: 200.

    .EXAMPLE
    $Criteria = [ordered]@{ From = 'sus@hacker.com'; Subject = 'Payroll change' }
    Build-EmailSearchName -Criteria $Criteria
    Returns: From:sus@hacker.com - Subject:Payroll change

    .OUTPUTS
    System.String. The generated search name.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Criteria,

        [int] $MaxLength = 200
    )

    $JoinString = ', '

    # recipients and keywords only; dates are intentionally excluded. key = criteria
    # key, value = label shown in the name
    $NameProperties = [ordered]@{
        From           = 'From'
        To             = 'To'
        Participants   = 'Participants'
        Recipients     = 'Recipients'
        Subject        = 'Subject'
        Body           = 'Body'
        AttachmentName = 'Attachment'
    }

    $Parts = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $NameProperties.Keys) {

        $Values = @($Criteria[$Key] | Where-Object { $null -ne $_ -and "$_".Trim() -ne '' })
        if ($Values.Count -eq 0) {
            continue
        }

        $Label = $NameProperties[$Key]
        $ValueString = ($Values | ForEach-Object { "$_".Trim() }) -join ','
        $Parts.Add("${Label}:${ValueString}")
    }

    $Name = $Parts -join $JoinString

    # fallback when nothing name-eligible is set
    if (-not $Name) {
        $Name = "EmailSearch $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }

    # keep the name within the allowed length
    if ($Name.Length -gt $MaxLength) {
        $Name = $Name.Substring(0, $MaxLength)
    }

    return $Name
}
