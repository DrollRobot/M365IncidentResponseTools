New-Alias -Name 'GetAdmins' -Value 'Get-AdminRole' 

function Get-AdminRole {
    [CmdletBinding()]
    param(
        [switch] $Cached,
        [switch] $Script,
        [switch] $Excel,
        [string[]] $Highlight,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont,
        [boolean] $Open = $true
    )

    begin {

        $CustomObjects = [System.Collections.Generic.List[pscustomobject]]::new()
        $WorksheetName = 'AdminRoles'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString = Get-Date -Format $FileNameDateFormat

        $Blue = @{ ForegroundColor = 'Blue' }

        # ensure ById caches are populated for Get-UnknownObject lookups
        Request-GraphUser -Return 'none' -Cached:$Cached
        Request-GraphGroup -Return 'none' -Cached:$Cached
        Request-GraphServicePrincipal -Return 'none' -Cached:$Cached
        Request-DirectoryRole -Return 'none' -Cached:$Cached
    }

    process {

        $RoleObjects = Request-DirectoryRole -Cached:$Cached
        $MemberIds = $RoleObjects.Members.Id | Sort-Object -Unique

        foreach ( $MemberId in $MemberIds ) {

            $MemberRoles = ( $RoleObjects | Where-Object { $MemberId -in $_.Members.Id } ).DisplayName -join ', '
            $Object = Get-UnknownObject -Id $MemberId
            $CustomObject = New-RoleMemberObject -Id $MemberId -Role $MemberRoles -RoleSource 'Direct Assignment' -GraphObject $Object
            $CustomObjects.Add( $CustomObject )

            # expand group members inline (nested groups not possible with M365 role assignments)
            if ( $CustomObject.ObjectType -eq 'Group' ) {
                foreach ( $GroupMemberId in ( Get-MgGroupMember -GroupId $MemberId ).Id ) {
                    $GroupMember = Get-UnknownObject -Id $GroupMemberId
                    $CustomObjects.Add( ( New-RoleMemberObject -Id $GroupMemberId -Role $MemberRoles -RoleSource "Group: $($Object.DisplayName)" -GraphObject $GroupMember ) )
                }
            }
        }
    }

    end {

        $CustomObjects = $CustomObjects | Sort-Object @{ Expression = 'ObjectType'; Descending = $true }, @{ Expression = 'AccountEnabled'; Descending = $true }

        # add highlight match column
        if ( $Highlight ) {
            $HighlightPattern = $Highlight -join '|'
            foreach ( $Obj in $CustomObjects ) {
                $IsMatch = (
                    ( $Obj.Id -match $HighlightPattern ) -or
                    ( $Obj.DisplayName -match $HighlightPattern ) -or
                    ( $Obj.PSObject.Properties['UserPrincipalName'] -and $Obj.UserPrincipalName -match $HighlightPattern ) -or
                    ( $Obj.PSObject.Properties['Description'] -and $Obj.Description -match $HighlightPattern )
                )
                $Obj | Add-Member -MemberType NoteProperty -Name 'Match' -Value $( if ( $IsMatch ) { '>>>' } else { '' } )
            }
        }

        if ( $Script ) {
            return $CustomObjects
        }

        # display properties per object type
        $DisplayProperties = [ordered]@{
            'User'             = @( 'AccountEnabled', 'DisplayName', 'UserPrincipalName', 'RoleSource', 'Roles' )
            'ServicePrincipal' = @( 'AccountEnabled', 'DisplayName', 'ServicePrincipalType', 'RoleSource', 'Roles' )
            'Group'            = @( 'DisplayName', 'RoleSource', 'Roles' )
        }
        $TypeLabels = @{
            'User'             = 'Users with admin roles:'
            'ServicePrincipal' = 'Service Principals with admin roles:'
            'Group'            = 'Groups with admin roles:'
        }

        if ( $Highlight ) {
            foreach ( $TypeKey in @( $DisplayProperties.Keys ) ) {
                $DisplayProperties[$TypeKey] = @( 'Match' ) + $DisplayProperties[$TypeKey]
            }
        }

        if ( -not $Excel ) {
            foreach ( $TypeKey in $DisplayProperties.Keys ) {
                Write-Host @Blue "`n$($TypeLabels[$TypeKey])"
                $TypeObjects = $CustomObjects | Where-Object { $_.ObjectType -eq $TypeKey }
                if ( $TypeObjects ) {
                    $TypeObjects | Format-Table -AutoSize -Property $DisplayProperties[$TypeKey] | Out-Host
                }
                else {
                    Write-Host "None"
                }
            }
        }

        if ( $Excel ) {

            $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
            $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
            $ExcelOutputPath = "AdminRoles_${DomainName}_${FileDateString}.xlsx"
            $TitleDateString = Get-Date -Format 'MM/dd/yy HH:mm'

            Write-Host @Blue "Exporting Excel: ${ExcelOutputPath}"

            $Workbook = $null
            $LabelRow = 3

            foreach ( $TypeKey in $DisplayProperties.Keys ) {

                $TypeObjects = @( $CustomObjects | Where-Object { $_.ObjectType -eq $TypeKey } )
                $Columns = $DisplayProperties[$TypeKey]

                if ( $TypeObjects.Count -gt 0 ) {

                    $SectionParams = @{
                        WorkSheetname = $WorksheetName
                        TableName     = "Table${TypeKey}"
                        TableStyle    = $TableStyle
                        StartRow      = $LabelRow + 1
                        AutoSize      = $true
                        Passthru      = $true
                    }
                    if ( $null -eq $Workbook ) {
                        $SectionParams['Path'] = $ExcelOutputPath
                    }
                    else {
                        $SectionParams['ExcelPackage'] = $Workbook
                    }

                    try {
                        $Workbook = $TypeObjects | Select-Object -Property $Columns | Export-Excel @SectionParams
                    }
                    catch {
                        Write-Error "Unable to write Excel section: ${TypeKey}"
                        if ( $Workbook ) { $Workbook | Close-ExcelPackage }
                        return
                    }

                    $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
                    $TableStartRow = $LabelRow + 1
                    $TableEndRow = $LabelRow + 1 + $TypeObjects.Count

                    # section label (written after export so worksheet exists)
                    $Worksheet.Cells[$LabelRow, 1].Value = $TypeLabels[$TypeKey]
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12

                    # conditional formatting: Match column
                    if ( $Highlight ) {
                        $MatchColId = ( $Worksheet.Tables["Table${TypeKey}"].Columns | Where-Object { $_.Name -eq 'Match' } ).Id
                        if ( $MatchColId ) {
                            $MatchCol = $MatchColId | Convert-DecimalToExcelColumn
                            $MatchFmtParams = @{
                                Worksheet       = $Worksheet
                                Address         = "${MatchCol}${TableStartRow}:${MatchCol}${TableEndRow}"
                                RuleType        = 'ContainsText'
                                ConditionValue  = '>>>'
                                BackgroundColor = 'LightPink'
                            }
                            Add-ConditionalFormatting @MatchFmtParams
                        }
                    }

                    # conditional formatting: AccountEnabled = FALSE
                    $AEColId = ( $Worksheet.Tables["Table${TypeKey}"].Columns | Where-Object { $_.Name -eq 'AccountEnabled' } ).Id
                    if ( $AEColId ) {
                        $AECol = $AEColId | Convert-DecimalToExcelColumn
                        $AEFmtParams = @{
                            Worksheet       = $Worksheet
                            Address         = "${AECol}${TableStartRow}:${AECol}${TableEndRow}"
                            RuleType        = 'ContainsText'
                            ConditionValue  = 'FALSE'
                            BackgroundColor = 'LightBlue'
                        }
                        Add-ConditionalFormatting @AEFmtParams
                    }

                    $LabelRow = $TableEndRow + 2

                }
                else {

                    # write label and (none) directly if workbook already exists
                    if ( $null -ne $Workbook ) {
                        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
                        $Worksheet.Cells[$LabelRow, 1].Value = $TypeLabels[$TypeKey]
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12
                        $Worksheet.Cells[$LabelRow + 1, 1].Value = '(none)'
                    }
                    $LabelRow += 3
                }
            }

            if ( $null -eq $Workbook ) {
                Write-Host "No admin role members found. No Excel file written."
                return
            }

            # column widths
            $ColumnWidths = @{
                'Match'             = 8
                'Enabled'           = 12
                'DisplayName'       = 30
                'UserPrincipalName' = 40
                'RoleSource'        = 30
                'Roles'             = 80
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = ($Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # font across entire used range
            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
            $SheetEnd = $Worksheet.Dimension.End.Address
            Set-ExcelRange -Worksheet $Worksheet -Range "A1:${SheetEnd}" -FontName $Font

            # sheet title (written last so font override sticks)
            $Worksheet.Cells[1, 1].Value = "Admin roles for ${DomainName} as of ${TitleDateString}"
            $Worksheet.Cells[1, 1].Style.Font.Bold = $true
            $Worksheet.Cells[1, 1].Style.Font.Size = 16

            # save and close
            if ( $Open ) {
                Write-Host "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }
    }
}

function New-RoleMemberObject {
    param(
        [string] $Id,
        [Alias('Roles')] [string] $Role,
        [string] $RoleSource,
        $GraphObject
    )

    switch ( $GraphObject.ObjectType ) {
        'User' {
            return [pscustomobject]@{
                ObjectType        = 'User'
                Id                = $Id
                Enabled           = $GraphObject.AccountEnabled
                DisplayName       = $GraphObject.DisplayName
                UserPrincipalName = $GraphObject.UserPrincipalName
                RoleSource        = $RoleSource
                Roles             = $Role
            }
        }
        'ServicePrincipal' {
            return [pscustomobject]@{
                ObjectType           = 'ServicePrincipal'
                Id                   = $Id
                Enabled              = $GraphObject.AccountEnabled
                DisplayName          = $GraphObject.DisplayName
                ServicePrincipalType = $GraphObject.ServicePrincipalType
                Description          = $GraphObject.Description
                RoleSource           = $RoleSource
                Roles             = $Role
            }
        }
        'Group' {
            return [pscustomobject]@{
                ObjectType  = 'Group'
                Id          = $Id
                DisplayName = $GraphObject.DisplayName
                Description = $GraphObject.Description
                RoleSource  = $RoleSource
                Roles             = $Role
            }
        }
        default {
            Write-Error "Unknown object type '$($GraphObject.ObjectType)' for Id: ${Id}"
        }
    }
}


function Get-UnknownObject {
    <#
	.SYNOPSIS
	Looks up an object by Id using cached ById hashtables. Falls back to Get-MgDirectoryObject if not found in cache.

	.NOTES
	Version: 2.0.0
    2.0.0 - Rewrote to use Request-* cached ById hashtables instead of direct Graph calls.
	#>
    [CmdletBinding()]
    param(
        [string] $Id
    )

    process {

        # try cached lookups first
        if ( $Global:IRT_UsersById -and $Global:IRT_UsersById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_UsersById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'User' -Force
            return $Obj
        }
        if ( $Global:IRT_GroupsById -and $Global:IRT_GroupsById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_GroupsById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'Group' -Force
            return $Obj
        }
        if ( $Global:IRT_ServicePrincipalsById -and $Global:IRT_ServicePrincipalsById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_ServicePrincipalsById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'ServicePrincipal' -Force
            return $Obj
        }

        # fallback to direct Graph lookup
        try {
            $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Id -ErrorAction Stop
            $DirectoryObject | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'Unknown' -Force
            return $DirectoryObject
        }
        catch {
            Write-Error "Unable to find object with Id: ${Id}"
        }
    }
}


# TESTING
# Get-AdminRole