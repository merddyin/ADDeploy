function Import-ADDModuleData {
<#
    .SYNOPSIS
        Short description

    .DESCRIPTION
        Long description

    .PARAMETER exampleparam
        Description of parameter and required elements

    .EXAMPLE
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Inputs to this cmdlet (if any)

    .OUTPUTS
        Output from this cmdlet (if any)

    .NOTES
        Help Last Updated: 10/24/2020

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding(DefaultParameterSetName="StandardQuery")]
    Param(
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="StandardQuery")]
        [string]$DataSet,

        [Parameter(Position=1,ParameterSetName="StandardQuery")]
        [string[]]$QueryFilter,

        [Parameter(Mandatory=$true,Position=0,ParameterSetName="CustomQuery")]
        [string]$DataQuery
    )

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "`n`n"
		Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""

        if(Test-Path $MyModulePath){
            $DBSrcPath = Join-Path -Path $MyModulePath -ChildPath '\src\other'
        } else{
            $scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
            $DBSrcPath = Join-Path -Path $scriptDir -ChildPath '\src\other'
        }

        $DBPath = Join-Path -Path $DBSrcPath -ChildPath 'ADDeploySettings.sqlite'
        Write-Verbose "`t`t`t`t`t`t`t`tOpening connection to embeded sqlite db"
        if(Test-Path $DBPath){
            $conn = New-SQLiteConnection -DataSource $DBPath
        }else{
            Write-Error -Category ResourceUnavailable -CategoryActivity DBConnect -TargetObject $DBPath -Message "File not found" -ErrorAction Stop
        }

        Write-Debug "`t`t`t`t`t`t`t`tDataSet: `t$DataSet"
        if($QueryFilter){
            Write-Debug "`t`t`t`t`t`t`t`tQueryFilter:`t$QueryFilter"
        }else{
            Write-Debug "`t`t`t`t`t`t`t`tQueryFilter:`tNot Present"
        }

        if(!($DataSet)){
            $DataSet = "-Custom Query-"
        }
    }

    Process {
        Write-Debug "`t`t`t`t`t`t`t`tSet query text based on specified inputs"
        if($($PSCmdlet.ParameterSetName) -like "StandardQuery"){
            $QType = "DataSet"
            switch ($DataSet) {
                "OUTop" {
                    $Query = "Select OU_name FROM OU_Core WHERE OU_type = 'Tier' AND OU_enabled = 1" #! Switch any references to use OUCore instead
                }

                "InitialRun" {
                    $Query = "Select * FROM AP_Rundata WHERE OB_item = 'InitDep'"
                }

                "Rundata" {
                    $Query = "Select * FROM AP_Rundata"
                }

                "OUFocus" {
                    $Query = "Select OU_name,OU_focus FROM OU_Core WHERE OU_type = 'Focus' AND OU_enabled = 1" #! Switch any references to use OUCore instead
                }

                "OUTier"{
                    $Query = "Select OU_name,OU_focus FROM OU_Core WHERE OU_type = 'Tier' AND OU_enabled = 1" #! Switch any references to use OUCore instead
                }

                "OUCore"{
                    $Query = "Select OU_name,OU_type,OU_focus FROM OU_core WHERE OU_enabled = 1"
                }

                "OUOrg" {
                    if($QueryFilter){
                        $Query = "Select * FROM OU_Organization WHERE OU_schema = '$QueryFilter'"
                    }else{
                        $Query = "Select * FROM Cust_OU_Organization WHERE ou_enabled = 1"
                    }
                }

                "OUObjType" {
                    switch ($QueryFilter.count){
                        {$_ -eq 1} {
                            # Base OUObjType query
                            $Query = "Select * FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_relatedfocus = '$QueryFilter'"
                        }
                        {$_ -eq 2} {
                            # Query by focus and refid - Used for ACL assignement
                            $Query = "Select * FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_relatedfocus = '$($QueryFilter[0])' AND OBJ_refid = '$($QueryFilter[1])' AND OBJ_AssignACLs = 1"
                        }
                        {$_ -eq 3} {
                            # Query by focus, type OU, and Primary or Secondary - Used for TDG creation
                            $Query = "Select * FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_relatedfocus = '$($QueryFilter[0])' AND OBJ_TypeOU = '$($QueryFilter[1])' AND OBJ_ItemType = '$($QueryFilter[2])'"
                        }
                    }
                }

                "AllObjInfo" {
                    $Query = "Select OBJ_id,OBJ_refid,OBJ_adclass,OBJ_relatedfocus,OBJ_category,OBJ_TypeOU,OBJ_SubTypeOU,OBJ_ItemType,OBJ_AssignACLs,OBJ_TierAssoc FROM AP_Objects WHERE OBJ_enabled = 1"
                }

                "RefIDObjType" {
                    switch ($QueryFilter.count) {
                        {$_ -eq 1} {
                            $Query = "Select OBJ_adclass FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_refid = '$QueryFilter'"
                        }
                        {$_ -eq 2} {
                            $Query = "Select OBJ_adclass FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_refid = '$($QueryFilter[0])' AND OBJ_SubTypeOU = '$($QueryFilter[1])'"
                        }
                    }
                }

                "TDGOBJids" {
                    $Query = "Select OBJ_id FROM AP_Objects WHERE OBJ_enabled = 1 AND OBJ_relatedfocus = '$($QueryFilter[0])' AND OBJ_TypeOU = '$($QueryFilter[1])'"
                }

                "TDGDestinations" {
                    $Query
                }

                "RefIDFromType-SubType" {
                    switch ($QueryFilter.count) {
                        {$_ -eq 1} {
                            # Query by Type only
                            $Query = "Select OBJ_RefID FROM AP_Objects WHERE OBJ_TypeOU = '$QueryFilter'"
                        }
                        {$_ -eq 2} {
                            # Query by Type and Sub-Type
                            $Query = "Select OBJ_RefID FROM AP_Objects WHERE OBJ_TypeOU = '$($QueryFilter[0])' AND OBJ_SubTypeOU = '$($QueryFilter[1])'"
                        }
                    }

                }
                "OULevelCheck" {
                    if($QueryFilter){
                        $Query = "Select DISTINCT OU_orglvl FROM OU_Organization WHERE OU_schema = '$QueryFilter'"
                    }else{
                        $Query = "Select DISTINCT OU_orglvl FROM Cust_OU_Organization"
                    }
                }
                "PropGroups" {
                    $Query = "Select * FROM AP_PropGroups WHERE OBJ_enabled = 1 AND OBJ_refid = '$QueryFilter'"
                }

                "PropGroupDestIDs" {
                    $Query = "Select DISTINCT OBJ_destination from AP_PropGroups WHERE OBJ_enabled"
                }

                "PGPathValues" {
                    $Query = "Select OBJ_id,OBJ_TypeOU,OBJ_SubTypeOU FROM AP_Objects WHERE OBJ_id in ($QueryFilter)"
                }

                "RightsInfo" {
                    $Query = "Select OBJ_indicator,OBJ_value FROM AP_Rights WHERE OBJ_enabled = 1 AND OBJ_assignacls = 1"
                }

                "PGDefinition" {
                    $Query = "Select OBJ_propertyname FROM AP_PropertyGroupMap WHERE OBJ_pgrpname = '$QueryFilter'"
                }

                "PGValidation" {
                    $Query = "Select * FROM AP_PropGroups WHERE OBJ_enabled = 1 AND OBJ_assignAcls = 1 AND OBJ_name = '$QueryFilter'"
                }

                "AllPGData" {
                    $Query = "Select * FROM AP_PropGroups WHERE OBJ_enabled = 1"
                }
                #? New 9-19

                "AclPGData" {
                    $Query = "Select * FROM AP_PropGroups WHERE OBJ_enabled = 1 AND OBJ_assignAcls = 1"
                }
                #? New 9-19

                "AllPGMapData" {
                    $Query = "Select * FROM AP_PropertyGroupMap"
                }
                #? New 9-19

                "ClassMap" {
                    $Query = "Select OBJ_Name,OBJ_guid FROM AD_Classes"
                }

                "AttribMap" {
                    $Query = "Select OBJ_Name,OBJ_guid FROM AD_Attributes WHERE OBJ_adtype = '$QueryFilter'"
                }

                "RoleData" {
                    $Query = "Select * from AP_Roles"
                }

                "RolePermissionData" {
                    $Query = "Select * from AP_RolePermissions"
                }
            }

        }else{
            $QType = "CustomQuery"
            $Query = $DataQuery
        }
    }

    End {
        Write-Verbose "`t`t`t`t`t`t`t`tSelected Query:`t$DataSet"
        try
        {
            $Output = Invoke-SqliteQuery -Connection $conn -Query $Query
            if($Output){
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tData Retrieved"
            }else{
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tNo Data Retrieved"
                Write-Error "Failed: $DataSet"
            }
        }
        catch
        {
            Write-Error "`t`t`t`t`t`t`t`tQuery Result:`tFailed - $DataSet" -ErrorAction Continue
            Write-Debug "`t`t`t`t`t`t`t`tExecuted Query:`t$Query"
            Write-Debug "`t`t`t`t`t`t`t`tQuery Type: $QType"
        }

        Write-Verbose "`t`t`t`t`t`t`t`tClosing connection to embeded sqlite db"
        $conn.Close()
        Write-Verbose "`n"
        Write-Verbose "`t`t`t`t`t`t------------------- $($FunctionName): End -------------------"
        Write-Verbose "`n`n"

        if($Output){
            Return $Output
        }else{
            Write-Error "Failed to return any results for $query from $dataset" -ErrorAction Continue 
        }
    }
}