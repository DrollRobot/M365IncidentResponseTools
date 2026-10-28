function Set-ServicePrincipalEnabled {
    <#
    .SYNOPSIS
    Sets the accountEnabled property on service principal(s). Called by
    Disable-IRTServicePrincipal and Enable-IRTServicePrincipal.

    .DESCRIPTION
    Internal helper. Updates accountEnabled on each service principal through Graph, then
    reads the object back and shows its new state. A failed update is reported as an
    error and the next service principal is processed.

    Falls back to the service principals selected with Find-IRTServicePrincipal, in
    $Global:IRT_ServicePrincipalObjects, when no -ServicePrincipalObject is passed.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects, as returned by Find-IRTServicePrincipal. Only
    the Id is needed; AppDisplayName or DisplayName is used in messages.

    .PARAMETER Enabled
    $true to enable the service principals, $false to disable them.

    .EXAMPLE
    Set-ServicePrincipalEnabled -ServicePrincipalObject $Sp -Enabled $false
    Disables one service principal.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter( Position = 0 )]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [Parameter( Mandatory )]
        [bool] $Enabled
    )

    begin {
        Update-IRTToken -Service 'Graph'
        Import-IRTModule -Name 'Microsoft.Graph.Applications', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name

        # if not passed directly, find global
        if ( -not $ServicePrincipalObject -or $ServicePrincipalObject.Count -eq 0 ) {
            $ScriptSPObjects = @( Get-GlobalServicePrincipalObject )
            if ( -not $ScriptSPObjects -or $ScriptSPObjects.Count -eq 0 ) {
                throw "No service principal objects passed or found in global variables."
            }
        }
        else {
            $ScriptSPObjects = $ServicePrincipalObject
        }

        # variables
        $GetProperties = @(
            'accountEnabled'
            'appDisplayName'
            'appId'
            'displayName'
            'id'
            'servicePrincipalType'
        )
        $DisplayProperties = @(
            'AccountEnabled'
            'AppDisplayName'
            'ServicePrincipalType'
            'AppId'
            'Id'
        )

        # set action string
        if ( $Enabled ) {
            $Action = 'Enable'
        }
        else {
            $Action = 'Disable'
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: ${Action} $($ScriptSPObjects.Count) service principal(s).")
    }

    process {

        foreach ( $ScriptSPObject in $ScriptSPObjects ) {

            $SpName = if ( $ScriptSPObject.AppDisplayName ) {
                $ScriptSPObject.AppDisplayName
            }
            else {
                $ScriptSPObject.DisplayName
            }
            $SpId = $ScriptSPObject.Id

            if ( -not $SpId ) {
                Write-IRT "No object ID for: $SpName. Skipping." -Level Warn
                continue
            }

            # disable/enable service principal
            Write-IRT "$($Action.TrimEnd('e'))ing service principal: $SpName"
            if ( $PSCmdlet.ShouldProcess($SpName, "$Action service principal") ) {
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Update-MgServicePrincipal $SpId accountEnabled=$Enabled")
                $UpdateParams = @{
                    ServicePrincipalId = $SpId
                    AccountEnabled     = $Enabled
                    ErrorAction        = 'Stop'
                }
                try {
                    Update-MgServicePrincipal @UpdateParams
                }
                catch {
                    $Msg = "Failed to $($Action.ToLower()) ${SpName}: $($_.Exception.Message)"
                    Write-IRT $Msg -Level Error
                    continue
                }
            }

            # get updated object
            Write-IRT "Getting updated service principal properties."
            $GetParams = @{
                ServicePrincipalId = $SpId
                Property           = $GetProperties
                ErrorAction        = 'Stop'
            }
            try {
                $NewSPObject = Get-MgServicePrincipal @GetParams
            }
            catch {
                $Msg = "Failed to get service principal ${SpName}: $($_.Exception.Message)"
                Write-IRT $Msg -Level Error
                continue
            }

            # display updated object
            $NewSPObject | Format-Table $DisplayProperties
        }
    }
}
