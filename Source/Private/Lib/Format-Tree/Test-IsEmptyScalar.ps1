function Test-IsEmptyScalar($Value) {
    ($Value -is [string]) -and [string]::IsNullOrWhiteSpace($Value)
}
