function Export-ADDModuleData {
<#
    .SYNOPSIS
        Export Azure AD Module Data

    .DESCRIPTION
        Export Azure AD Module Data

    .PARAMETER DataSet
        

    .PARAMETER QueryValue
        

    .PARAMETER QueryObjects
       
    
    .PARAMETER DataQuery
        

    .EXAMPLE
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Inputs to this cmdlet (if any)

    .OUTPUTS
        Output from this cmdlet (if any)

    .NOTES
        Help Last Updated: 10/26/2020

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="StandardQuery")]
        [Parameter(Mandatory=$true,Position=0,ParameterSetName="UpdateQuery")]
        [string]$DataSet,

        [Parameter(Position=1,ParameterSetName="StandardQuery")]
        [string[]]$QueryValue,

        [Parameter(Mandatory=$true,ParameterSetName="UpdateQuery",ValueFromPipeline=$true)]
        [System.Management.Automation.PSCustomObject]$QueryObjects,

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
        }else{
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
    }

    Process {
        Write-Debug "`t`t`t`t`t`t`t`tSet query text based on specified inputs"
        switch ($PSCmdlet.ParameterSetName) {
            "StandardQuery" {
                $QType = "DataSet"
                switch ($DataSet) {
                    "SetRunData" {
                        $Query = "UPDATE AP_Rundata SET OB_runvalue = '$($QueryValue[0])' WHERE OB_item = '$($QueryValue[1])'"
                    }
        
                    "UpdateOrgEntry" {
    
                    }
                    "SetCustOUData"  {
                        $Query = "UPDATE CUST_OU_Organization SET OU_enabled = '$($QueryValue[1])' WHERE OU_id = '$($QueryValue[0])'"
                    }

                    "AddOrgEntry"  {
                        $Query = "INSERT INTO CUST_OU_Organization (OU_name,OU_orglvl,OU_parent,OU_friendlyname,OU_tierassoc) VALUES ('$($QueryValue[0])',3,null,'$($QueryValue[1])','$($QueryValue[2])')"
                    }

                    "AddOrgEntryADM"  {
                        $Query = "INSERT INTO CUST_OU_Organization (OU_name,OU_orglvl,OU_parent,OU_friendlyname,OU_admin,OU_server,OU_standard,OU_tierassoc) VALUES ('$($QueryValue[0])',3,null,'$($QueryValue[1])',1,0,0,'$($QueryValue[2])')"
                    }

                    "AddOrgEntrySRV"  {
                        $Query = "INSERT INTO CUST_OU_Organization (OU_name,OU_orglvl,OU_parent,OU_friendlyname,OU_admin,OU_server,OU_standard,OU_tierassoc) VALUES ('$($QueryValue[0])',3,null,'$($QueryValue[1])',0,1,0,'$($QueryValue[2])')"
                    }

                    "AddOrgEntrySTD"  {
                        $Query = "INSERT INTO CUST_OU_Organization (OU_name,OU_orglvl,OU_parent,OU_friendlyname,OU_admin,OU_server,OU_standard,OU_tierassoc) VALUES ('$($QueryValue[0])',3,null,'$($QueryValue[1])',0,0,1,'$($QueryValue[2])')"
                    }

                    "AddOrgEntrySPL"  {
                        $Query = "INSERT INTO CUST_OU_Organization (OU_name,OU_orglvl,OU_parent,OU_friendlyname,OU_admin,OU_server,OU_standard,OU_tierassoc) VALUES ('$($QueryValue[0])',3,null,'$($QueryValue[1])','$($QueryValue[2])','$($QueryValue[3])','$($QueryValue[4])','$($QueryValue[5])')"
                    }

                    "RemoveOrgEntry" {
                        $Query = "DELETE FROM CUST_OU_Organization WHERE OU_name LIKE '$($QueryValue[0])' AND $($QueryValue[1]) = 1 and OU_tierassoc = '$($QueryValue[2])'"
                    }

                    "SetAttributeSchema" {
                        $Query = "UPDATE AD_Attributes SET OBJ_Guid = '$($QueryValue[1])' WHERE OBJ_name = '$($QueryValue[0])'"
                    }
                    "InsertAttributeSchema" {
                        $Query = "INSERT INTO AD_Attributes (OBJ_Name,OBJ_guid,OBJ_adtype) VALUES ('$($QueryValue[0])','$($QueryValue[1])','attributeSchema')"
                    }
                    "SetClassGUID" {
                        $Query = "UPDATE AD_Classes SET OBJ_Guid = '$($QueryValue[1])' WHERE OBJ_name = '$($QueryValue[0])'"
                    }
                    "InsertClassGUID" {
                        $Query = "INSERT INTO AD_Classes (OBJ_Name,OBJ_guid) VALUES ('$($QueryValue[0])','$($QueryValue[1])')"
                    }
                }
            }
            "UpdateQuery" {
                switch ($DataSet) {
                    "InsertOrgData" {
                        $QueryObjects | Out-DataTable | Invoke-SQLiteBulkCopy -SQLiteConnection $conn -Table "CUST_OU_Organization"
                    }
                }
            }
            Default {
                $QType = "CustomQuery"
                $Query = $DataQuery
            }
        }
    }

    End {
        Write-Verbose "`t`t`t`t`t`t`t`tData Set:`t$DataSet"
        Write-Verbose "`t`t`t`t`t`t`t`tQuery String:`t$Query"

        try
        {
           
            $Output = Invoke-SqliteQuery -Connection $conn -Query $Query
            if($Output){
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tData Updated"
            }else{
                Write-Verbose "`t`t`t`t`t`t`t`tQuery Result:`tNo Results Returned"
            }
        }
        catch
        {
            Write-Error "`t`t`t`t`t`t`t`tQuery Result:`tFailed" -ErrorAction Continue
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
        }
    }

}