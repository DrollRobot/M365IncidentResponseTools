function Get-PropertyName($Obj) {
    $Obj.PSObject.Properties |
        Where-Object {
            $_.IsGettable -and
            $_.MemberType -in 'NoteProperty', 'Property', 'AliasProperty'
        } |
        Select-Object -ExpandProperty Name -Unique |
        Sort-Object
}