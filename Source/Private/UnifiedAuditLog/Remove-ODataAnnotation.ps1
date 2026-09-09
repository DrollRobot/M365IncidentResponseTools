function Remove-ODataAnnotation {
    <#
    .SYNOPSIS
    Recursively strips OData annotation keys from a Graph response object.

    .DESCRIPTION
    Internal helper. Graph decorates response objects with OData annotation keys that
    describe the wire type rather than the event: a bare '@odata.type', and a
    '<Property>@odata.type' companion for many properties. A single audit record's
    auditData can carry a dozen of them.

    They are noise once the object has been deserialized, and they would otherwise be
    serialized straight into the workbook's Raw column, so they are removed before the
    record is handed on. Nested dictionaries and arrays are cleaned too, since the
    annotations appear at every level.

    Anything that is not a dictionary or an array is returned unchanged.

    .PARAMETER InputObject
    The object to clean. Usually a hashtable from Invoke-MgGraphRequest.

    .EXAMPLE
    ```powershell
    $Clean = Remove-ODataAnnotation -InputObject $Record.auditData
    ```
    Returns the audit data without any '@odata.*' keys.

    .OUTPUTS
    The same shape as the input, without OData annotation keys.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns a cleaned copy; changes no state.')]
    [CmdletBinding()]
    [OutputType([object], [System.Collections.Specialized.OrderedDictionary], [object[]])]
    param(
        [object] $InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $Clean = [ordered]@{}
        foreach ($Key in $InputObject.Keys) {
            # drops both the bare '@odata.type' and per-property 'Foo@odata.type' keys
            if ([string]$Key -like '*@odata.*') { continue }
            $Clean[$Key] = Remove-ODataAnnotation -InputObject $InputObject[$Key]
        }
        return $Clean
    }

    # a string is enumerable, so test it before the generic collection branch
    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $Items = @()
        foreach ($Item in $InputObject) {
            $Items += , (Remove-ODataAnnotation -InputObject $Item)
        }
        # A bare `return $Items` unwraps a single-element array into the element itself,
        # which would turn "Actor": [{...}] into "Actor": {...}. The sheet builders read
        # AuditData.Actor[0].ID to resolve service principal names, so that indexer has
        # to keep working for a one-element array. The comma keeps it an array.
        return , $Items
    }

    return $InputObject
}
