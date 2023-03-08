function ConvertTo-Elements {
<#
    .SYNOPSIS
        Converts TDG to OU path and OU path to TDG

    .DESCRIPTION
        Support function to convert TDG names or OU paths into components for consumption by public functions

    .PARAMETER SourceValue
        Source value to be converted

    .PARAMETER Domain
        Optional domain to use as part of conversion

    .EXAMPLE
        PS C:\> $result = $Objects | ConvertTo-Elements

    .EXAMPLE
        Another example of how to use this cmdlet

    .NOTES
        Help Last Updated: 11/8/2022

        Cmdlet Version: 1.2
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding()]
    [OutputType("System.Array")]
    Param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string[]]
        $SourceValue,

        [Parameter(Mandatory=$false)]
        [String[]]
        $Domain
    )

    begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""
        Write-Verbose "`t`t`t`t`t`t`t`tSourceValue - $SourceValue"

        if(!($ObjInfo)){
            Write-Verbose "`t`t`t`t`t`t`t`tObjInfo - Not Set - Setting"
            $ObjInfo = Import-ADDModuleData -DataSet AllObjInfo

            if($ObjInfo){
                Write-Verbose "`t`t`t`t`t`t`t`tObjInfo Count - $($ObjInfo.count)"
            }else{
                Write-Verbose "`t`t`t`t`t`t`t`tObjInfo - Not Set - Failed"
            }
        }

        if($MaxLevel){
            Write-Debug "`t`t`t`t`t`t`t`tMaxLevel - $MaxLevel"
            switch ($MaxLevel) {
                {$_ -ge 1} {
                    $OUOrgLevel1 = $($OUOrg | Where-Object{$_.OU_orglvl -eq 3}).OU_name
                }

                {$_ -ge 2} {
                    $OUOrgLevel2 = $($OUOrg | Where-Object{$_.OU_orglvl -eq 4}).OU_name
                }
            }
        }

        Write-Debug "`t`t`t`t`t`t`t`tClear Runtime Variables"
        $DomDN              = $null
        $DomFull            = $null
        $TierID             = $null
        $FocusID            = $null
        $TargetType         = $null
        $Descriptor         = $null
        $ObjType            = $null
        $ObjTypeDBID        = $null
        $ObjTypeRefID       = $null
        $ObjSubType         = $null
        $ObjSubTypeDBID     = $null
        $ObjSubTypeRefID    = $null
        $OrgLvl1            = $null
        $OrgLvl2            = $null
        $OrgLvl3            = $null

        Write-Debug "`t`t`t`t`t`tConvertTo-Elements: Initialize Array"
        $OutputCollection = @()
        Write-Verbose "`n`n"
    }

    process {
        foreach($input in $SourceValue){
            Write-Verbose "`t`t`t`t`t`t`t`tInput: $input"

            if($input -match $OUdnRegEx){
                if($input -like "LDAP://*"){
                    $Value = $input -replace "LDAP://",""
                }else {
                    $Value = $input
                }

                #region Detect-ProcessOUPath
                Write-Verbose "`t`t`t`t`t`t`t`tSourceValue matches OUdnRegEx"
                Write-Verbose ""

                $PathElements = $Value.Split(",") -replace "OU="
                Write-Verbose "`t`t`t`t`t`t`t`tOriginal PathElements Count:`t$($PathElements.count)"
                $PathElements = $PathElements | Where-Object{$_ -notlike "DC=*"}

                switch ($($PathElements.Count)) {
                    {$_ -ge 1} {
                        $ItemLevel1 = ($PathElements[$PathElements.count - 1])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE 1 Source Value:`t$ItemLevel1"
                        switch ($ItemLevel1) {
                            {$_ -match ($TierHash.Keys -join '|')} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE1:`tElement 0 matches Tier"
                                $TierID = $TierHash[$ItemLevel1]
                            }

                            Default {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE1:`tElement 0 does not match Tier"
                                $TierID = $null
                            }
                        }
                    }

                    {$_ -ge 2} {
                        $ItemLevel2 = ($PathElements[$PathElements.count - 2])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2 Source Value:`t$ItemLevel2"
                        switch ($ItemLevel2) {
                            {$_ -match ($FocusHash.Values -join '|')} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 1 matches Focus"
                                $FocusID = $ItemLevel2
                            }

                            Default {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 1 does not match Focus"
                                $FocusID = $null
                            }
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected FocusID:`t$FocusID"
                    }

                    {$_ -ge 3} {
                        $ItemLevel3 = ($PathElements[$PathElements.count - 3])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3 Source Value:`t$ItemLevel3"
                        if($OUOrgLevel1){
                            switch ($ItemLevel3) {
                                {$_ -match $($OUOrgLevel1 -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 matches Level 1 Org"
                                    $OrgLvl1 = $ItemLevel3
                                }

                                {$_ -match $OUGlobal} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 matches Global Level 1 Org"
                                    $OrgLvl1 = $ItemLevel3
                                }

								{$_ -match 'Provision|Deprovision'} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 matches Staging Level 1 Org"
									$OrgLvl1 = $ItemLevel3
								}
								
                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 does not match Level 1 Org"
                                    $OrgLvl1 = $null
                                }
                            }

                        }else{
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tNo Level 1 Org Data Available"
                            $OrgLvl1 = $null
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl1:`t$OrgLvl1"
                    }

                    {$_ -ge 4} {
                        $ItemLevel4 = ($PathElements[$PathElements.count - 4])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4 Source Value:`t$ItemLevel4"

                        if($MaxLevel -eq 1){
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4 MaxLevel:`t1 (Object Type)"

                            switch ($ItemLevel4) {
                                {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_TypeOU} | Select-Object OBJ_TypeOU -Unique).OBJ_TypeOU -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 matches Object Type"

                                    $ObjType = $ItemLevel4

                                    $ObjTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_id

                                    $ObjTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_refid
                                }

                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 does not match Object Type"
                                    $ObjTypeDBID = 0
                                    $ObjType = $null
                                    $ObjTypeRefID = $null
                                }
                            }
                            Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Type Elements"
                            Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tType`tRefID"
                            Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjTypeDBID`t$ObjType`t$ObjTypeRefID"

                        }else{
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4 MaxLevel:`tGT 1 (OrgLvl2)"

                            switch ($ItemLevel4) {
                                {$_ -match $($OUOrgLevel2 -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 matches Level 2 Org"
                                    $OrgLvl2 = $ItemLevel4
                                }

                                {$_ -match $OUGlobal} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 matches Global Level 2 Org"
                                    $OrgLvl2 = $ItemLevel4
                                }

                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 does not match Level 2 Org"
                                    $OrgLvl2 = $null
                                }
                            }

                            Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl2:`t$OrgLvl2"
                        }
                    }

                    {$_ -ge 5} {
                        $ItemLevel5 = ($PathElements[$PathElements.count - 5])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5 Source Value:`t$ItemLevel5"

                        switch ($MaxLevel) {
                            {$_ -eq 1} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5 MaxLevel:`t1 (Object Sub-Type)"

                                switch ($ItemLevel5) {
                                    {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_SubTypeOU} | Select-Object OBJ_SubTypeOU -Unique).OBJ_SubTypeOU -join "|")} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Object Sub-Type"

                                        $ObjSubType = $ItemLevel5

                                        $ObjSubTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_id

                                        $ObjSubTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_refid
                                    }

                                    Default {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 does not match Object Sub-Type"
                                        $ObjSubTypeDBID = 0
                                        $ObjSubType = $null
                                        $ObjSubTypeRefID = $null
                                    }
                                }
                                Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Sub-Type Elements"
                                Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tSub-Type`tRefID"
                                Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjSubTypeDBID`t$ObjSubType`t$ObjSubTypeRefID"

                            }

                            {$_ -eq 2} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5 MaxLevel:`t2 (Object Type)"
                                switch ($ItemLevel5) {
                                    {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_TypeOU} | Select-Object OBJ_TypeOU -Unique).OBJ_TypeOU -join "|")} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Object Type"

                                        $ObjType = $ItemLevel5

                                        $ObjTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_id

                                        $ObjTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_refid
                                    }

                                    Default {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 does not match Object Type"
                                        $ObjTypeDBID = 0
                                        $ObjType = $null
                                        $ObjTypeRefID = $null
                                    }
                                }
                                Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Type Elements"
                                Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tType`tRefID"
                                Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjTypeDBID`t$ObjType`t$ObjTypeRefID"

                            }

                            {$_ -eq 3} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5 MaxLevel:`t3 (OrgLvl3)"
                                switch ($ItemLevel5) {
                                    {$_ -match $($OUOrgLevel3 -join "|")} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Level 3 Org"
                                        $OrgLvl3 = $ItemLevel5
                                    }

                                    {$_ -match $OUGlobal} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Global Level 3 Org"
                                        $OrgLvl3 = $ItemLevel5
                                    }

                                    Default {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 does not match Level 3 Org"
                                        $OrgLvl3 = $null
                                    }
                                }

                                Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl3:`t$OrgLvl3"
                            }

                        }
                    }

                    {$_ -ge 6} {
                        $ItemLevel6 = ($PathElements[$PathElements.count - 6])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6 Source Value:`t$ItemLevel6"

                        switch ($MaxLevel) {
                            {$_ -eq 2} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6 MaxLevel:`t2 (Object Sub-Type)"

                                switch ($ItemLevel6) {
                                    {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_SubTypeOU} | Select-Object OBJ_SubTypeOU -Unique).OBJ_SubTypeOU -join "|")} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6:`tElement 5 matches Object Sub-Type"

                                        $ObjSubType = $ItemLevel6

                                        $ObjSubTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_id

                                        $ObjSubTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_refid
                                    }

                                    Default {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6:`tElement 5 does not match Object Sub-Type"
                                        $ObjSubTypeDBID = 0
                                        $ObjSubType = $null
                                        $ObjSubTypeRefID = $null
                                    }
                                }
                                Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Sub-Type Elements"
                                Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tSub-Type`tRefID"
                                Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjSubTypeDBID`t$ObjSubType`t$ObjSubTypeRefID"

                            }

                            {$_ -eq 3} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6 MaxLevel:`t3 (Object Type)"
                                switch ($ItemLevel6) {
                                    {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_TypeOU} | Select-Object OBJ_TypeOU -Unique).OBJ_TypeOU -join "|")} {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6:`tElement 5 matches Object Type"

                                        $ObjType = $ItemLevel6

                                        $ObjTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_id

                                        $ObjTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_refid
                                    }

                                    Default {
                                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE6:`tElement 5 does not match Object Type"
                                        $ObjTypeDBID = 0
                                        $ObjType = $null
                                        $ObjTypeRefID = $null
                                    }
                                }
                                Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Type Elements"
                                Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tType`tRefID"
                                Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjTypeDBID`t$ObjType`t$ObjTypeRefID"

                            }
                        }
                    }

                    {$_ -eq 7} {
                        $ItemLevel7 = ($PathElements[$PathElements.count - 7])
                        Write-Debug "`t`t`t`t`t`t`t`tSwitch - EQ7 Source Value:`t$ItemLevel7"

                        switch ($ItemLevel7) {
                            {$_ -match $(($ObjInfo | Where-Object{$null -ne $_.OBJ_SubTypeOU} | Select-Object OBJ_SubTypeOU -Unique).OBJ_SubTypeOU -join "|")} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - EQ7:`tElement 6 matches Object Sub-Type"

                                $ObjSubType = $ItemLevel7

                                $ObjSubTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_id

                                $ObjSubTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $ObjSubType}).OBJ_refid
                            }

                            Default {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - EQ7:`tElement 6 does not match Object Sub-Type"
                                $ObjSubTypeDBID = 0
                                $ObjSubType = $null
                                $ObjSubTypeRefID = $null
                            }
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected Object Sub-Type Elements"
                        Write-Verbose "`t`t`t`t`t`t`t`t`tDBID`tSub-Type`tRefID"
                        Write-Verbose "`t`t`t`t`t`t`t`t`t$ObjSubTypeDBID`t$ObjSubType`t$ObjSubTypeRefID"
                    }

                    {$_ -gt 7} {
                        Write-Verbose "`t`t`t`t`t`t`t`tSwitch - GT7:`tSupplied DN path longer than expected"
                    }
                }

                $TargetType = "DistinguishedName"
                Write-Verbose "`t`t`t`t`t`t`t`tTargetType: $TargetType"
                $Descriptor = $null
                #endregion Detect-ProcessOUPath

            }else{

                #region ProcessTDGName
                Write-Verbose "`t`t`t`t`t`t`t`tSourceValue matches TDG name"
                Write-Verbose ""

                $PEParts = $input.Split("-")
                $Descriptor = $PEParts[2]
                $SrcRefID = $(($PEParts[1]).Split("_"))[0]
                $PathElements = ($PEParts[0]).Split("_")

                #region ProcessPathElements
                switch ($($PathElements.Count)) {
                    {$_ -ge 2} {
                        # Tier and Focus
                        $ItemLevel1 = ($PathElements[0])
                        switch ($ItemLevel1) {
                            {$_ -match ($CETierHash.Keys -join '|')} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 0 matches Tier"
                                $TierID = $CETierHash[$ItemLevel1]
                            }

                            Default {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 0 does not match Tier"
                                $TierID = $null
                            }
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected TierID:`t$TierID"

                        $ItemLevel2 = ($PathElements[1])
                        switch ($ItemLevel2) {
                            {$_ -match ($FocusHash.Values -join '|')} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 1 matches Focus"
                                $FocusID = $ItemLevel2
                            }

                            {$_ -match "GBL"} {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 1 matches Global Focus"
                                $FocusID = $ItemLevel2
                            }

                            Default {
                                Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE2:`tElement 1 does not match Focus"
                                $FocusID = $null
                            }
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected FocusID:`t$FocusID"

                    }

                    {$_ -ge 3} {
                        # Top-Lvl Org
                        $ItemLevel3 = ($PathElements[2])
                        if($OUOrgLevel1){
                            switch ($ItemLevel3) {
                                {$_ -match $(($OUOrg | Where-Object{$_.OU_orglvl -eq 3}).OU_name -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 matches Level 1 Org"
                                    $OrgLvl1 = $ItemLevel3
                                }

                                {$_ -match $OUGlobal} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 matches Global Level 1 Org"
                                    $OrgLvl1 = $ItemLevel3
                                }

                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tElement 2 does not match Level 1 Org"
                                    $OrgLvl1 = $null
                                }
                            }
                        }else{
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tNo Level 1 Org Data Available"
                            $OrgLvl1 = $null
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl1:`t$OrgLvl1"
                    }

                    {$_ -ge 4} {
                        # Second-Lvl Org
                        $ItemLevel4 = ($PathElements[3])
                        if($OUOrgLevel2){
                            switch ($ItemLevel4) {
                                {$_ -match $(($OUOrg | Where-Object{$_.OU_orglvl -eq 4}).OU_name -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 matches Level 2 Org"
                                    $OrgLvl2 = $ItemLevel4
                                }

                                {$_ -match $OUGlobal} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 matches Global Level 2 Org"
                                    $OrgLvl2 = $ItemLevel4
                                }

                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tElement 3 does not match Level 2 Org"
                                    $OrgLvl2 = $null
                                }
                            }
                        }else{
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE3:`tNo Level 2 Org Data Available"
                            $OrgLvl2 = $null
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl2:`t$OrgLvl2"
                    }

                    {$_ -eq 5} {
                        # Third-Lvl Org
                        $ItemLevel5 = ($PathElements[4])
                        if($OUOrgLevel3){
                            switch ($ItemLevel5) {
                                {$_ -match $(($OUOrg | Where-Object{$_.OU_orglvl -eq 3}).OU_name -join "|")} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Level 3 Org"
                                    $OrgLvl3 = $ItemLevel5
                                }

                                {$_ -match $OUGlobal} {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 matches Global Level 3 Org"
                                    $OrgLvl3 = $ItemLevel5
                                }

                                Default {
                                    Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE5:`tElement 4 does not match Level 3 Org"
                                    $OrgLvl3 = $null
                                }
                            }
                        }else{
                            Write-Debug "`t`t`t`t`t`t`t`tSwitch - GE4:`tNo Level 3 Org Data Available"
                            $OrgLvl3 = $null
                        }
                        Write-Verbose "`t`t`t`t`t`t`t`tDetected OrgLvl3`t$OrgLvl3"
                    }
                }
                #endregion ProcessPathElements

                #region ProcessPEMid
                if($ObjInfo){
                    $ObjItem = $ObjInfo | Where-Object{$_.OBJ_refid -like $SrcRefID}
                    Write-Verbose "`t`t`t`t`t`t`t`tObjItem:`t$ObjItem"
                    if($ObjItem){
                        $ObjType = $ObjItem.OBJ_TypeOU
                        Write-Debug "`t`t`t`t`t`t`t`tObjType:`t$ObjType"
                        if($ObjItem.OBJ_SubTypeOU){
                            Write-Verbose "`t`t`t`t`t`t`t`tSubType OU value present"

                            $ObjSubType = $ObjItem.OBJ_SubTypeOU
                            Write-Debug "`t`t`t`t`t`t`t`tObjSubType:`t$ObjSubType"

                            $ObjSubTypeRefID = $ObjItem.OBJ_refid
                            Write-Debug "`t`t`t`t`t`t`t`tObjSubTypeRefID:`t$ObjSubTypeRefID"

                            $ObjSubTypeDBID = $ObjItem.OBJ_id
                            Write-Debug "`t`t`t`t`t`t`t`tObjSubTypeDBID:`t$ObjSubTypeDBID"

                            $ObjFocusID = $ObjItem.OBJ_relatedfocus
                            Write-Debug "`t`t`t`t`t`t`t`tObjFocusID:`t$ObjFocusID"

                            $ObjTypeRefID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_refid
                            Write-Debug "`t`t`t`t`t`t`t`tObjTypeRefID:`t$ObjTypeRefID"

                            $ObjTypeDBID = ($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $ObjType -and $null -eq $_.OBJ_SubTypeOU}).OBJ_id
                            Write-Debug "`t`t`t`t`t`t`t`tObjSubTypeDBID:`t$ObjSubTypeDBID"

                        }else{
                            Write-Verbose "`t`t`t`t`t`t`t`tSubType OU value not present"

                            $ObjTypeRefID = $ObjItem.OBJ_refid
                            Write-Verbose "`t`t`t`t`t`t`t`tObjTypeRefID:`t$ObjTypeRefID"

                            $ObjTypeDBID = $ObjItem.OBJ_id
                            Write-Verbose "`t`t`t`t`t`t`t`tObjSubTypeDBID:`t$ObjTypeDBID"

                            $ObjSubType = $null
                            $ObjSubTypeRefID = $null
                            $ObjSubTypeDBID = 0
                        }
                    }else{
                        Write-Verbose "`t`t`t`t`t`t`t`tNo object match found"

                        $ObjType = $null
                        $ObjTypeRefID = $null
                        $ObjTypeDBID = 0
                        $ObjSubType = $null
                        $ObjSubTypeRefID = $null
                        $ObjSubTypeDBID = 0
                    }
                }else{
                    Write-Verbose "`t`t`t`t`t`t`t`tObject data unavailable"
                }
                #endregion PEMid

                $TargetType = "TDG Name"

                #endregion ProcessTDGName

            }

            #region CreateOutput
            $OutputObj = [PSCustomObject]@{
                DomDN               = $DomDN
                DomFull             = $DomFull
                TierID              = $TierID
                FocusID             = $FocusID
                TargetType          = $TargetType
                Descriptor          = $Descriptor
                ObjectType          = $ObjType
                ObjectTypeRefID     = $ObjTypeRefID
                ObjectTypeDBID      = $ObjTypeDBID
                ObjectSubType       = $ObjSubType
                ObjectSubTypeRefID  = $ObjSubTypeRefID
                ObjectSubTypeDBID   = $ObjSubTypeDBID
                MaxLvl              = $MaxLevel
                OrgL1               = $OrgLvl1
                OrgL2               = $OrgLvl2
                OrgL3               = $OrgLvl3
            }
            #endregion CreateOutput

            $OutputCollection += $OutputObj
        }
    }

    end {
        Write-Verbose ""
        Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
        return $OutputCollection
    }
}