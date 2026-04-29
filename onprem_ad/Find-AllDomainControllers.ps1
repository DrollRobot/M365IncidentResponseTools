New-Alias -Name 'FindDCs'              -Value 'Find-AllDomainControllers' -Force
New-Alias -Name 'FindDomainControllers' -Value 'Find-AllDomainControllers' -Force
New-Alias -Name 'Find-DCs'              -Value 'Find-AllDomainControllers' -Force

function Find-AllDomainControllers { 
    
    if ( -not ( Test-AdAvailable ) ) {
        Write-Error 'ActiveDirectory RSAT module not available.'
        return
    }

    Get-ADDomainController -Filter * | Select-Object Name
}


