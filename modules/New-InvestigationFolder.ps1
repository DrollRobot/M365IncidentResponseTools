New-Alias -Name 'NewDir' -Value "New-InvestigationFolder" -Force
New-Alias -Name 'NewFolder' -Value "New-InvestigationFolder" -Force

function New-InvestigationFolder {
	<#
	.SYNOPSIS
	Makes a new directory based on client and user info

	.NOTES
	Version: 1.0.2
	#>
	[CmdletBinding(SupportsShouldProcess)]
	param (
		[Parameter( Position = 0 )]
		[Alias('UserObjects')]
		[psobject[]] $UserObject,

		[string] $Ticket
	)

	begin {

		# script variables
		$CurrentPath = Get-Location
		$FileNameStrings = [System.Collections.Generic.List[string]]::new()

		# get client domain
		$Params = @{
			ErrorAction = 'Stop'
		}
		try {
			$DefaultDomain = Get-MgDomain @Params | Where-Object { $_.IsDefault -eq $true }
		}
		catch {}

		if ( $DefaultDomain ) {
			$DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
		}
		else {
			$DomainName = Read-Host "Enter client name"
		}

		# get datetime string for filename
		$DateString = Get-Date -Format "yy-MM-dd_HH-mm"

		# if not passed directly, find global
		if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

			# get from global variables
			$ScriptUserObjects = Get-IRTUserObject

		}
		else {
			$ScriptUserObjects = $UserObject
		}
	}

	process {

		### build string array
		# domain name
		if ( $DomainName ) {
			$FileNameStrings.Add( $DomainName )
		}

		# user name
		if ( @( $ScriptUserObjects ).Count -eq 1 ) {

			$UserEmail = $ScriptUserObjects.UserPrincipalName
			$UserName = $UserEmail -split '@' | Select-Object -First 1
			$FileNameStrings.Add( $UserName )
		}
		elseif (  @( $ScriptUserObjects ).Count -gt 1 ) {

			$FileNameStrings.Add( 'MultipleUsers' )
		}
		else {
			$UserName = Read-Host "Enter username:"
			$FileNameStrings.Add( $UserName )
		}

		# ticket number
		if (-not [string]::IsNullOrWhiteSpace($Ticket)) {
			$FileNameStrings.Add($Ticket)
		}

		# date
		$FileNameStrings.Add( $DateString )

		# investigation
		$FileNameStrings.Add( 'Investigation' )

		# build folder name
		$FolderName = $FileNameStrings -join '_'

		# create folder
		$FolderPath = Join-Path -Path $CurrentPath -ChildPath $FolderName
		if ($PSCmdlet.ShouldProcess($FolderPath, 'Create directory')) {
			New-Item -ItemType Container -Path $FolderPath -Confirm:$false | Out-Null

			# move to folder
			Set-Location -Path $FolderPath
		}
	}
}