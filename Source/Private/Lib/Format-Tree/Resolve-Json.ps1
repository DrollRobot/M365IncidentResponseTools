function Resolve-Json($Value) {

    ### if it's a string that looks like json, try to parse it
    ### (handles one level of json-in-a-string)
    # if the value is anything other than string, return it
    if ($Value -isnot [string]) { return $Value }
    $String = $Value.Trim()
    if (-not (
            ($String.StartsWith('{') -and $String.EndsWith('}')) -or
            ($String.StartsWith('[') -and $String.EndsWith(']'))
        )
    ) {
        return $Value
    }

    try {
        # convert from json
        $Parsed = $String | ConvertFrom-Json -ErrorAction Stop
        # if the parsed result is itself a json-looking string, try one more pass
        if ($Parsed -is [string]) {
            $Inner = $Parsed.Trim()
            if (
                ($Inner.StartsWith('{') -and $Inner.EndsWith('}')) -or
                ($Inner.StartsWith('[') -and $Inner.EndsWith(']'))
            ) {
                try { return ($Inner | ConvertFrom-Json -ErrorAction Stop) }
                catch { return $Parsed }
            }
        }
        return $Parsed
    } catch { return $Value }
}
