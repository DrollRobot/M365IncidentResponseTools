function Build-Menu {
    <#
    .SYNOPSIS
    Takes a collection, presents a numbered menu, reads user input, returns user's selection.

    .DESCRIPTION
    For a simple menu, provide a list or array. Numbers will automatically be assigned.
    For a customized menu, provide a hashtable in the format below.

    .PARAMETER Options
    Provide collection of menu options. Accepts array of strings, Generic.List[string] or hashtable.

    .PARAMETER List
    Use -List for this menu format:
    [1] Do this
    [2] Do that

    .PARAMETER Table
    Use -Table for this format:
    [1] Do this  [2] Do that

    .EXAMPLE
    Input:
    $Option = [ordered]@{
        '1' = @{
            String = 'Do this'
            Color = 'Red'
        }
        '2' = @{
            String = 'Do that'
            Color = 'Green'
        }
    }
    $MenuParams = @{
        Title = "Choose action:"
        Options = $Option
        List = $true
    }
    $UserChoice = Build-Menu @MenuParams

    Output:
    Choose action:

    [1] Do this     # Foregroundcolor Red
    [2] Do that     # Foregroundcolor Green

    Enter choice:


    .NOTES
    Version: 1.1.2
    1.1.2 - Fixed bugs where script doesn't accept user input.
    1.1.0 - Added validation that hashtable keys are integers, not strings.
    1.01 - Changed hashtable format to allow colors.
    0.02 - Convert to allow building menu based on hashtable.
    #>
    param(
        [parameter( Mandatory )]
        [Alias('Options')]
        [object] $Option,

        [string] $Title,

        [Parameter(ParameterSetName = 'List')]
        [switch] $List,

        [Parameter(ParameterSetName = 'Table')]
        [switch] $Table,

        [switch] $NoNewLine,

        [string] $TestAnswer
    )

    # determine input type
    if ( (
            $Option -is [array] -and
            ( $Option | ForEach-Object { $_ -is [string] } )
        ) -or
        $Option -is [System.Collections.Generic.List[string]]
    ) {
        $ArrayOrList = $true
    }
    elseif ( $Option -is [System.Collections.Specialized.OrderedDictionary] ) {
        # every key must be a string
        if ( ($Option.Keys | Where-Object { $_ -isnot [string] }).Count ) {
            throw 'Build-Menu: Hashtable keys must be strings.'
        }
        # every value must itself be a hashtable with at least a string key
        foreach ($Value in $Option.Values) {
            if ($Value -isnot [hashtable] -or -not $Value.ContainsKey('String')) {
                throw 'Build-Menu: Each option must be a hashtable that contains a ''String'' key.'
            }
        }
    }
    else {
        throw "Build-Menu: Unsupported input type."
    }

    # display title
    if ( $Title ) {
        Write-Host ''
        Write-Host $Title
    }

    if ( -not $NoNewLine ) {
        Write-Host ''
    }

    if ( $ArrayOrList ) {

        # build menu with numbers counting from one
        for ( $i = 0; $i -lt @($Option).Count; $i++ ) {

            # add one so first index isn't 0
            $Index = $i + 1

            # variables
            $String = $Option[$i]

            # output
            Write-Host -NoNewLine "[${Index}] ${String}  "

            # for list format, add a newline every loop. for table format, only at end
            if ( $List -or
                ( $Table -and
                $Index -eq @($Option).Count - 1 )
            ) {
                Write-Host ''
            }
        }

    }
    else { # if hashtable

        # build menu with numbers from hashtable
        $Keys = $Option.Keys
        $LastKey = $Keys[-1]

        foreach ( $Key in $Keys ) {

            # variables
            $OptionItem = $Option[$Key]
            $String = $OptionItem.String

            # build params for output
            $Params = @{
                NoNewLine = $true
            }

            # if color was specified, add to params
            if ( $OptionItem.ContainsKey('Color') -and $OptionItem['Color'])  {
                $Params['ForegroundColor'] = $OptionItem.Color
            }

            Write-Host "[${Key}] ${String}  " @Params

            # for list format, add a newline every loop. for table format, only at end
            if ( $List -or
                ( $Table -and
                $Key -eq $LastKey
            ) ) {
                Write-Host ''
            }
        }
    }

    if ( -not $NoNewLine ) {
        Write-Host ''
    }

    # get input from user
    if ( $TestAnswer ) {
        $UserChoice = $TestAnswer
    }
    else {
        $UserChoice = Read-Host 'Enter choice'
    }

    # validate answer and return string
    if ( $ArrayOrList ) {

        while ( -not ( $UserChoice -ge 1 -and $UserChoice -le @($Option).Count ) ) {
            Write-Host -NoNewLine @Red "Choice must be a number, 1 to $( @($Option).Count ). Enter Choice"
            $UserChoice = Read-Host
        }

        # convert choice number to index number
        $i = $UserChoice - 1

        # use index number to get string
        $Return = $Option[$i]

    }
    else { # if hashtable
        while ( $UserChoice -notin $Option.Keys ) {
            $OptionsString = @( $Option.Keys | Sort-Object ) -join ','
            Write-IRT "Choice must be in ${OptionsString}. Enter Choice" -Level Error
            $UserChoice = Read-Host
        }

        $Return = $Option[$UserChoice].String
    }

    return $Return
}
