function Test-IsScalar($Value) {
    # treat common primitives as scalars (and helpful extras)
    $Value -is [string] -or $Value -is [bool] -or
    $Value -is [int] -or $Value -is [long] -or
    $Value -is [double] -or $Value -is [decimal] -or
    $Value -is [datetime] -or $Value -is [guid] -or
    $Value -is [timespan] -or $Value -is [uri] -or
    $Value -is [version] -or $Value -is [enum]
}
