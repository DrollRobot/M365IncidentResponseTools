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
    $Options = [ordered]@{
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
        Options = $Options
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
        [object] $Options,

        [string] $Title,

        [Parameter(ParameterSetName = 'List')]
        [switch] $List,

        [Parameter(ParameterSetName = 'Table')]
        [switch] $Table,

        [switch] $NoNewLines,

        [string] $TestAnswer
    )

    # variables

    # $Blue = @{ ForegroundColor = 'Blue' }
    $Red = @{ ForegroundColor = 'Red' }
    # $Cyan = @{ ForegroundColor = 'Cyan' }
    # $Green = @{ ForegroundColor = 'Green' }
    # $Magenta = @{ ForegroundColor = 'Magenta' }

    # determine input type
    if ( (
            $Options -is [array] -and 
            ( $Options | ForEach-Object { $_ -is [string] } )
        ) -or 
        $Options -is [System.Collections.Generic.List[string]]
    ) {
        $ArrayOrList = $true
    }
    elseif ( $Options -is [System.Collections.Specialized.OrderedDictionary] ) {
        # every key must be a string
        if ( ($Options.Keys | Where-Object { $_ -isnot [string] }).Count ) {
            throw 'Build-Menu: Hashtable keys must be strings.'
        }
        # every value must itself be a hashtable with at least a string key
        foreach ($Value in $Options.Values) {
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

    if ( -not $NoNewLines ) {
        Write-Host ''
    }

    if ( $ArrayOrList ) {
        
        # build menu with numbers counting from one
        for ( $i = 0; $i -lt @($Options).Count; $i++ ) {

            # add one so first index isn't 0
            $Index = $i + 1

            # variables
            $String = $Options[$i]

            # output
            Write-Host -NoNewLine "[${Index}] ${String}  "

            # for list format, add a newline every loop. for table format, only at end
            if ( $List -or 
                ( $Table -and 
                $Index -eq @($Options).Count - 1 )
            ) {
                Write-Host ''
            }
        }

    }
    else { # if hashtable

        # build menu with numbers from hashtable
        $Keys = $Options.Keys
        $LastKey = $Keys[-1]

        foreach ( $Key in $Keys ) {

            # variables
            $Option = $Options[$Key]
            $String = $Option.String

            # build params for output
            $Params = @{
                NoNewLine = $true
            }

            # if color was specified, add to params
            if ( $Option.ContainsKey('Color') -and $Option['Color'])  {
                $Params['ForegroundColor'] = $Option.Color
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

    if ( -not $NoNewLines ) {
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

        while ( -not ( $UserChoice -ge 1 -and $UserChoice -le @($Options).Count ) ) {
            Write-Host -NoNewLine @Red "Choice must be a number, 1 to $( @($Options).Count ). Enter Choice"
            $UserChoice = Read-Host
        }

        # convert choice number to index number
        $i = $UserChoice - 1

        # use index number to get string
        $Return = $Options[$i]

    }
    else { # if hashtable
        while ( $UserChoice -notin $Options.Keys ) {
            $OptionsString = @( $Options.Keys | Sort-Object ) -join ',' 
            Write-Host @Red "Choice must be in ${OptionsString}. Enter Choice"
            $UserChoice = Read-Host
        }

        $Return = $Options[$UserChoice].String
    }

    return $Return
}
