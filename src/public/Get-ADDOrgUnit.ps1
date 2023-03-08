function Get-ADDOrgUnit {
<#
    .SYNOPSIS
        Helper function to quickly retrieve model OUs for use in reporting, or for piping to other module cmdlets

    .DESCRIPTION
        Function is capable of retrieving OUs at any level of the structure. When specifying the Level, all available OUs for
        the specified level are returned as DirectoryEntry objects. By default, all OUs are retrieved.

    .PARAMETER Level
        Tells the function which level of the ZTAD OU structure to retrieve. Valid values as follows:

        - All (Default): Gets all ZTAD OUs
        - Tier: Gets all Tier layer OUs
        - Focus: Gets all Focus layer OUs
        - SL: Gets all level one Scope layer OUs
        - CLASS: Gets all Class layer OUs

    .PARAMETER SL
        Retrieves a specific level one Scope layer OU from all Tiers and Focuses in which it exists

    .PARAMETER IncludeChildren
        Specifying this switch when providing a value for SL will retrieve all child OUs of the specified scope

    .EXAMPLE
        PS C:\> Get-ADDOrgUnit -Level CLASS | New-ADDTaskGroup

        The above command retrieves all AD class OUs (Users, Groups, Workstations, etc), and passes it to the New-ADDTaskGroup cmdlet to initiate
        creation of the associated Task Delegation Groups for each OU. The New-ADTaskGroup cmdlet will return DirectoryEntry objects to the pipeline.

    .EXAMPLE
        PS C:\> Get-ADDOrgUnit -SL GBL | Export-CSV C:\Temp\Global.csv -NoTypeInformation

        The above gets all Scope layer OUs named 'GBL' and exports the results to a CSV file without object type details.

   .NOTES
        Help Last Updated: 5/16/2022

        Cmdlet Version: 1.2.0
        Cmdlet Status: Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(DefaultParameterSetName="Default")]
    Param(
        [Parameter(ParameterSetName="Default")]
        [ValidateSet("Tier","Focus","SL","CLASS","ALL")]
        [string]$Level = "ALL",
        [Parameter(ParameterSetName="Selective",Mandatory=$true)]
        [string]$SL,
        [Parameter(ParameterSetName="Selective")]
        [switch]$IncludeChildren
    )

    DynamicParam {
        $TierFilter = @{
            Name = 'TierFilter'
            Type = [string]
            ValidateSet = @("Tier-0","Tier-1","Tier-2")
            ParameterSetName = "Default"
        }

        $FocusFilter = @{
            Name = 'FocusFilter'
            Type = [string]
            ValidateSet = @("ADM","SRV","STD","STG")
            ParameterSetName = "Default"
        }

        $DynamicParameters = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        switch ($Level) {
            "Focus" {
                New-DynamicParameter @TierFilter -Dictionary $DynamicParameters
            }

            "SL" {
                New-DynamicParameter @TierFilter -Dictionary $DynamicParameters
                New-DynamicParameter @FocusFilter -Dictionary $DynamicParameters
            }
        }

        $DynamicParameters
    }

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""
        Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Retrieving List"
        $FinalOUDEs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $FilteredOUDEs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
    
        $TopResults = @()
        
        foreach($tier in $($CETierHash.Values)){
            $TopResults += Find-ADDADObject -ADClass organizationalUnit -ADAttribute name -SearchString $tier
        }

        $Results = @()
    }

    Process {
        Foreach($TResult in $TopResults){
            $Results += Find-ADDADObject -ADClass organizationalUnit -ADAttribute name -SearchString * -SearchRoot $TResult.Path
        }
    
        if($pscmdlet.ParameterSetName -like "Selective"){
            $OULevel = "SPECIAL"
        }else{
            $OULevel = $Level
        }
    
        Write-Verbose "`t`t $($FunctionName): `t OULevel: $OULevel"
    
        if ($Results) {
            $AllCount = $Results.Count
            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters" 
            Write-Verbose "`t`t $($FunctionName): `t Retrieved $AllCount OUs"
    
            switch ($OULevel) {
                "CLASS" {
                    Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - Class and SRV" 
    
                    $ObjTypeOUs = ($ObjInfo | Where-Object{$_.OBJ_ItemType -like 'Primary' -and $null -ne $_.OBJ_TypeOU} | Select-Object OBJ_TypeOU -Unique)
                    $OUName = @($ObjTypeOUs.OBJ_TypeOU)
    
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - Class and SRV" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                            Write-Verbose "PathItems Count:`t$($PathItems.Count)"
                            $Item = $PathItems[0]
                            Write-Verbose "Item:`t$Item"
    
                            if($OUName -contains $Item){
                                Write-Verbose "IsClass:`t$true"
                                $FinalOUDEs.Add($ItemDE)
                                Write-Verbose "FullResults Count:`t$($FullResults.Count)"
                            } 
                            
                            if($Result.DistinguishedName -like "*OU=SRV,*" -and $PathItems.count -eq 3) {
                                $FinalOUDEs.Add($ItemDE)
                            }
    
                            $ProcessedCount ++
                        }
                    } else {
                        Write-Error "No Source Values"
                    }
                }
    
                "SLO" {
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - SLO" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                    
                            if ($($PathItems).count -eq 4) {
                                $FinalOUDEs.Add($ItemDE)
                            }
    
                            $ProcessedCount ++
                        }
                    }else {
                        Write-Error "No Source Values - SLO"
                    }
                }
    
                "SL" {
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - SL" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                    
                            if ($($PathItems).count -eq 3) {
                                $FinalOUDEs.Add($ItemDE)
                            }
    
                            $ProcessedCount ++
                        }
                    }else {
                        Write-Error "No Source Values - SL"
                    }
                }
    
                "Focus" {
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - Focus" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                    
                            if($($PathItems).count -eq 2) {
                                $FinalOUDEs.Add($ItemDE)
                            }
    
                            $ProcessedCount ++
                        }
                    }else {
                        Write-Error "No Source Values - Focus"
                    }
    
                }
    
                "Tier" {
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - Tier" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                    
                            if($($PathItems).count -eq 1) {
                                $FinalOUDEs.Add($ItemDE)
                            }
    
                            $ProcessedCount ++
                        }
                    }else {
                        Write-Error "No Source Values - Focus"
                    }
    
                }
    
                "SPECIAL" {
                    Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters..." 
    
                    $ObjTypeOUs = ($ObjInfo | Where-Object{$_.OBJ_ItemType -like 'Primary' -and $null -ne $_.OBJ_TypeOU} | Select-Object OBJ_TypeOU -Unique)
                    $ClassOUNames = @($ObjTypeOUs.OBJ_TypeOU)
    
                    if($Results){
                        $ProcessedCount = 0
            
                        foreach($Result in $Results){
                            if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                                $PercentComplete = ($ProcessedCount / $AllCount) * 100
                            }else{
                                $PercentComplete = 0
                            }
    
                            If($IncludeChildren){
                                $cOp = "Org, Class, and SRV"
                            }else {
                                $cOp = "Org and SRV"
                            }
    
                            Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Applying Filters - $cOp" -PercentComplete $PercentComplete
                            $OUPath = ($Result.DistinguishedName -Split ",DC")[0]
                            $PathItems = (($OUPath) -replace "OU=","").Split(',')
                            Write-Verbose "PathItems Count:`t$($PathItems.Count)"
    
                            if($PathItems.count -eq 3 -and $($PathItems[0]) -like $SL) {
                                $FinalOUDEs.Add($ItemDE)
                            }else {
                                if($IncludeChildren -and $PathItems.count -eq 4){
                                    $Item = $PathItems[0]
                                    Write-Verbose "Item:`t$Item"
    
                                    if($ClassOUNames -contains $Item -and $($PathItems[1]) -like $SL){
                                        Write-Verbose "IsClass:`t$true"
                                        $FinalOUDEs.Add($ItemDE)
                                        Write-Verbose "FullResults Count:`t$($FullResults.Count)"
                                    } 
                                }
                            }
    
                            $ProcessedCount ++
                        }
                    } else {
                        Write-Error "No Source Values"
                    }
                }
    
                Default {
                    $ProcessedCount = 0
            
                    foreach($Result in $Results){
                        if($ProcessedCount -gt 1 -and $AllCount -gt $ProcessedCount){
                            $PercentComplete = ($ProcessedCount / $AllCount) * 100
                        }else{
                            $PercentComplete = 0
                        }
    
                        Write-Progress -Activity "Getting ZTAD OUs" -CurrentOperation "Getting Directory Entries" -PercentComplete $PercentComplete
                        $FinalOUDEs.Add($Result)
                        $ProcessedCount ++
                    }
                }
            }
    
        }
    }

    End {
        if($FinalOUDEs){
            if($TierFilter){
                Write-Progress -Activity "Applying Filters" -CurrentOperation "Filtering Tiers"

                foreach($OUItem in $FinalOUDEs){
                    if($OUItem.Path -like "*OU=$TierFilter*"){
                        $FilteredOUDEs.Add($OUItem)
                    }
                }

            }elseif($FocusFilter){
                Write-Progress -Activity "Applying Filters" -CurrentOperation "Filtering Focuses"

                foreach($OUItem in $FinalOUDEs){
                    if($OUItem.Path -like "*OU=$FocusFilter*"){
                        $FilteredOUDEs.Add($OUItem)
                    }
                }

            }else{
                foreach($OUItem in $FinalOUDEs){
                    $FilteredOUDEs.Add($OUItem)
                }
            }            
        }

        if($FilteredOUDEs){
            return $FilteredOUDEs
        }
    }
}
