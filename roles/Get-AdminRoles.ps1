New-Alias -Name 'GetAdmins' -Value 'Get-AdminRoles' -Force

function Get-AdminRoles {
    [CmdletBinding()]
    param(
        [switch] $Script,
        [switch] $Excel,
        [string[]] $Highlight,
        [string] $TableStyle = 'Dark8',
        [boolean] $Open = $true,
        [string] $TenantId
    )

    begin {

        $CustomObjects      = [System.Collections.Generic.List[pscustomobject]]::new()
        $WorksheetName      = 'AdminRoles'
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileDateString     = Get-Date -Format $FileNameDateFormat

        $Blue = @{ ForegroundColor = 'Blue' }
    }

    process {

        $RoleObjects = Get-MgDirectoryRole -ExpandProperty Members
        $MemberIds   = $RoleObjects.Members.Id | Sort-Object -Unique

        foreach ( $MemberId in $MemberIds ) {

            $MemberRoles  = ( $RoleObjects | Where-Object { $MemberId -in $_.Members.Id } ).DisplayName -join ', '
            $Object       = Get-UnknownObject -Id $MemberId
            $CustomObject = New-RoleMemberObject -Id $MemberId -Roles $MemberRoles -RoleSource 'Direct Assignment' -GraphObject $Object
            $CustomObjects.Add( $CustomObject )

            # expand group members inline (nested groups not possible with M365 role assignments)
            if ( $CustomObject.ObjectType -eq 'Group' ) {
                foreach ( $GroupMemberId in ( Get-MgGroupMember -GroupId $MemberId ).Id ) {
                    $GroupMember = Get-UnknownObject -Id $GroupMemberId
                    $CustomObjects.Add( ( New-RoleMemberObject -Id $GroupMemberId -Roles $MemberRoles -RoleSource "Group: $($Object.DisplayName)" -GraphObject $GroupMember ) )
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
            'ServicePrincipal' = @( 'AccountEnabled', 'ServicePrincipalType', 'DisplayName', 'RoleSource', 'Roles' )
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

            $DefaultDomain   = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
            $DomainName      = $DefaultDomain.Id -split '\.' | Select-Object -First 1
            $ExcelOutputPath = "AdminRoles_${DomainName}_${FileDateString}.xlsx"
            $TitleDateString = Get-Date -Format 'MM/dd/yy HH:mm'

            Write-Host @Blue "Exporting Excel: ${ExcelOutputPath}"

            $Workbook = $null
            $LabelRow = 3

            foreach ( $TypeKey in $DisplayProperties.Keys ) {

                $TypeObjects = @( $CustomObjects | Where-Object { $_.ObjectType -eq $TypeKey } )
                $Columns     = $DisplayProperties[$TypeKey]

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

                    $Worksheet     = $Workbook.Workbook.Worksheets[$WorksheetName]
                    $TableStartRow = $LabelRow + 1
                    $TableEndRow   = $LabelRow + 1 + $TypeObjects.Count

                    # section label (written after export so worksheet exists)
                    $Worksheet.Cells[$LabelRow, 1].Value           = $TypeLabels[$TypeKey]
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                    $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12

                    # conditional formatting: Match column
                    if ( $Highlight ) {
                        $MatchColId = ( $Worksheet.Tables["Table${TypeKey}"].Columns | Where-Object { $_.Name -eq 'Match' } ).Id
                        if ( $MatchColId ) {
                            $MatchCol = $MatchColId | Convert-DecimalToExcelColumn
                            Add-ConditionalFormatting -Worksheet $Worksheet -Address "${MatchCol}${TableStartRow}:${MatchCol}${TableEndRow}" -RuleType 'ContainsText' -ConditionValue '>>>' -BackgroundColor 'LightYellow'
                        }
                    }

                    # conditional formatting: AccountEnabled = FALSE
                    $AEColId = ( $Worksheet.Tables["Table${TypeKey}"].Columns | Where-Object { $_.Name -eq 'AccountEnabled' } ).Id
                    if ( $AEColId ) {
                        $AECol = $AEColId | Convert-DecimalToExcelColumn
                        Add-ConditionalFormatting -Worksheet $Worksheet -Address "${AECol}${TableStartRow}:${AECol}${TableEndRow}" -RuleType 'ContainsText' -ConditionValue 'FALSE' -BackgroundColor 'LightBlue'
                    }

                    $LabelRow = $TableEndRow + 2

                }
                else {

                    # write label and (none) directly if workbook already exists
                    if ( $null -ne $Workbook ) {
                        $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
                        $Worksheet.Cells[$LabelRow, 1].Value           = $TypeLabels[$TypeKey]
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Bold = $true
                        $Worksheet.Cells[$LabelRow, 1].Style.Font.Size = 12
                        $Worksheet.Cells[$LabelRow + 1, 1].Value       = '(none)'
                    }
                    $LabelRow += 3
                }
            }

            if ( $null -eq $Workbook ) {
                Write-Host "No admin role members found. No Excel file written."
                return
            }

            # font across entire used range
            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]
            $SheetEnd  = $Worksheet.Dimension.End.Address
            Set-ExcelRange -Worksheet $Worksheet -Range "A1:${SheetEnd}" -FontName 'Consolas'

            # sheet title (written last so font override sticks)
            $Worksheet.Cells[1, 1].Value           = "Admin roles for ${DomainName} as of ${TitleDateString}"
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
        [string] $Roles,
        [string] $RoleSource,
        $GraphObject
    )

    switch ( $GraphObject.GetType().Name ) {
        'MicrosoftGraphUser' {
            return [pscustomobject]@{
                ObjectType        = 'User'
                Id                = $Id
                AccountEnabled    = $GraphObject.AccountEnabled
                DisplayName       = $GraphObject.DisplayName
                UserPrincipalName = $GraphObject.UserPrincipalName
                RoleSource        = $RoleSource
                Roles             = $Roles
            }
        }
        'MicrosoftGraphServicePrincipal' {
            return [pscustomobject]@{
                ObjectType           = 'ServicePrincipal'
                Id                   = $Id
                AccountEnabled       = $GraphObject.AccountEnabled
                ServicePrincipalType = $GraphObject.ServicePrincipalType
                DisplayName          = $GraphObject.DisplayName
                Description          = $GraphObject.Description
                RoleSource           = $RoleSource
                Roles                = $Roles
            }
        }
        'MicrosoftGraphGroup' {
            return [pscustomobject]@{
                ObjectType  = 'Group'
                Id          = $Id
                DisplayName = $GraphObject.DisplayName
                Description = $GraphObject.Description
                RoleSource  = $RoleSource
                Roles       = $Roles
            }
        }
        default {
            Write-Error "Unknown object type: $($GraphObject.GetType().Name)"
        }
    }
}


function Get-UnknownObject {
    <#
	.SYNOPSIS
	Uses Get-MgDirectoryObject to find object type, then uses dedicated command for that type to return object.	
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param(
        [string] $Id
    )

    begin {
        # variables
        $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Id
        $ObjectType = $DirectoryObject.AdditionalProperties.'@odata.type' -replace '#microsoft\.graph\.', ''
        $UserGetProperties = @(
            'AccountEnabled'
            'DisplayName'
            'Id'
            'UserPrincipalName'
        )
        $ServicePrincipalGetProperties = @(
            'AccountEnabled'
            'Description'
            'DisplayName'
            'Id'
            'ServicePrincipalType'
        )
        $GroupGetProperties = @(
            'Description'
            'DisplayName'
            'Id'
        )
    }

    process {

        switch ( $ObjectType ) {
            'group' {
                $Object = Get-MgGroup -GroupId $Id -Property $GroupGetProperties
                return $Object
            }
            'servicePrincipal' {
                $Object = Get-MgServicePrincipal -ServicePrincipalId $Id -Property $ServicePrincipalGetProperties
                return $Object
            }
            'user' {
                $Object = Get-MgUser -UserId $Id -Property $UserGetProperties
                return $Object
            }
            default {
                Write-Error "Unknown object type: ${ObjectType}"
            }
        }
    }
}
