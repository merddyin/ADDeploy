function New-ADDOrgUnit {
<#
    .SYNOPSIS
        Deploys the ZTAD OU structure, or adds a new entry to the structure

    .DESCRIPTION
        This cmdlet will deploy the entirety of the registered ZTAZ OU structure within a new environment. 
        Alternatively, this cmdlet can accept values that will be used to create new branches within a 
        previously deployed structure.

    .PARAMETER TargetGroup
        Specify one or more groups by distinguished name to process TDGs for

    .PARAMETER PipelineCount
        Used to specity the number of objects being passed in the pipeline, if knownn, to use in showing progress

    .PARAMETER TargetDE
        Accepts one or more DirectoryEntry objects to process TDGs for

    .PARAMETER MTRun
        Only used when calling this cmdlet from the Publish-ADDZTADStructure -MultiThread command - modifies the behavior of progress

    .EXAMPLE
        PS C:\> Get-ADDOrgUnit -OULevel CLASS | New-ADDTaskGroup

        The above command retrieves all AD class OUs (Users, Groups, Workstations, etc), and passes it to the New-ADDTaskGroup cmdlet to initiate
        creation of the associated Task Delegation Groups for each OU. The New-ADTaskGroup cmdlet will return DirectoryEntry objects to the pipeline.

    .INPUTS
        System.String
        System.DirectoryServices.DirectoryEntry

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

    .NOTES
        Help Last Updated: 5/16/2022

        Cmdlet Version: 1.1
        Cmdlet Status: Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ManualRunB",ConfirmImpact='Medium')]
    param (
        [Parameter(ParameterSetName="ChainRun")]
        [Switch]$DeployAll,

        [Parameter(ParameterSetName="ManualRunA")]
        [ValidateRange(0,2)]
        [int]$Tier,

        [Parameter(ParameterSetName="ManualRunA")]
        [string]$Focus,

        [Parameter(ParameterSetName="ManualRunA",ValueFromPipeline=$true,Mandatory=$true)]
        [Parameter(ParameterSetName="ManualRunB",ValueFromPipeline=$true,Mandatory=$true)]
        [string[]]$ScopeNode,

        [Parameter(ParameterSetName="ManualRunA",ValueFromPipeline=$true,Mandatory=$false)]
        [Parameter(ParameterSetName="ManualRunB",ValueFromPipeline=$true,Mandatory=$false)]
        [string[]]$ScopeFriendly = ""
    )
    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""
        #TODO: Update help
        #TODO: Update Begin flow to use table changes for OU population in place of static method

        #TODO: Add process to increment DB ver and publish changes to 'central store' in addition to local copy

        Write-Verbose "$FunctionName `tDomDN: `t $DomDN"
        $StgObjTypes = $($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like "STG" -and $_.OBJ_ItemType -like 'Primary'}).OBJ_TypeOU | Select-Object -Unique
        $StdObjTypes = $($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like "STD" -and $_.OBJ_ItemType -like 'Primary'}).OBJ_TypeOU | Select-Object -Unique
        $AdmObjTypes = $($ObjInfo | Where-Object{$_.OBJ_relatedfocus -like "ADM" -and $_.OBJ_ItemType -like 'Primary'}).OBJ_TypeOU | Select-Object -Unique
        
        if($null -eq $StgObjTypes){
            Write-Error "Missing Stage Object Data - Quitting"
            Break
        }

        if($null -eq $StdObjTypes){
            Write-Error "Missing Standard Object Data - Quitting"
            Break
        }

        if($null -eq $Admobjtypes){
            Write-Error "Missing Admin Object Data - Quitting"
            Break
        }
        
        $SrvOrg = $($OUOrg | Where-Object{$_.OU_orglvl -gt 2 -and $_.OU_server -eq 1})
        $AdmOrg = $($OUOrg | Where-Object{$_.OU_orglvl -gt 2 -and $_.OU_admin -eq 1})
        $StdOrg = $($OUOrg | Where-Object{$_.OU_orglvl -gt 2 -and $_.OU_standard -eq 1})
        
        if($pscmdlet.ShouldProcess('Setup','Initialize Variables')){
            # Used for tracking only
            $DeployedOrgOUs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

            # Returned to pipeline
            $ContinueOrgOUs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        }else {
            $DeployedOrgOUs = @()

            $ContinueOrgOUs = @()
        }

        if($DeployAll){
            $PipeBase = 15

            $PipeADMOrg = 3 * $($AdmOrg.Count)
            $PipeSTDOrg = 2 * $($StdOrg.count)
            $PipeSrvOrg = 3 * $($SrvOrg.Count)
            $PipeStgOrg = 3 * $($StgObjTypes.Count)

            $PipeAdmType = $($StdObjTypes.Count + $AdmObjTypes.Count) * $PipeADMOrg
            $PipeStdType = $StdObjTypes.Count * $PipeADMOrg

            $PipelineCount = $PipeBase + $PipeADMOrg + $PipeSTDOrg + $PipeSrvOrg + $PipeStgOrg + $PipeAdmType + $PipeStdType 

            Write-Progress -Id 10 -Activity "Create ZTAD OU Structure" -CurrentOperation "Initializing..." 
        }else{
            if($Focus){
                $FocusList = @($Focus)
            }else{
                $FocusList = @($($FocusHash.GetEnumerator() | Where-Object{$_.name -notlike 'Stage'}).value)
            }

            $ouADM = 0
            $ouSRV = 0
            $ouSTD = 0

            switch ($FocusList){
                {$_ -contains "ADM"} {
                    $ouADM = 1
                }

                {$_ -contains "SRV"} {
                    $ouSRV = 1
                }

                {$_ -contains "STD"} {
                    $ouSTD = 1
                }
            }
        }


        $ProcessedCount = 0
        $FailedCount = 0
        $GCloopCount = 1
        $loopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

        Write-Verbose ""
    }
    
    Process {
        Write-Verbose ""
        Write-Verbose "`t`t****************** $($FunctionName): Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

        # Enforced .NET garbage collection to ensure memory utilization does not balloon 
        if($GCloopCount -eq 30){
            Invoke-MemClean
            $GCloopCount = 0
        }

        if($DeployAll){
            if($ProcessedCount -gt 1 -and $PipelineCount -gt $ProcessedCount){
                $PercentComplete = ($ProcessedCount / $PipelineCount) * 100
            }else{
                $PercentComplete = 0
            }

            Write-Progress -Id 10 -Activity "Create ZTAD OU Structure" -CurrentOperation "Deploying..." -Status "Processed $ProcessedCount" -PercentComplete $PercentComplete

            $TierProcessed = 0
            $FocusProcessed = 0
            $ADMOrgProcessed = 0
            $SrvOrgProcessed = 0
            $StdOrgProcessed = 0

            foreach($cOU in $($CETierHash.Values)){
                Write-Verbose "`t`t $($FunctionName): `tCreate top-level Tier OUs: `t$cOU"
                if($TierProcessed -gt 1 -and 3 -gt $TierProcessed){
                    $TierPercentComplete = ($TierProcessed / 3) * 100
                }else{
                    $TierPercentComplete = 0
                }
                
                Write-Progress -Id 15 -Activity "Tier OU Structure" -CurrentOperation "Deploying $cOU..." -Status "Processed $TierProcessed" -PercentComplete $TierPercentComplete -ParentId 10

                if($pscmdlet.ShouldProcess("$cOU","Create Tier OU")){
                    $TierOU = New-ADDADObject -ObjName $cOU -ObjParentDN $DomDN -ObjDescription $cOU -ObjType organizationalUnit
                }else{
                    $TierOU = @{DistinguishedName = "OU=$cOU,$DomDN"}
                }

                if($TierOU){
                    Write-Verbose "`t`t $($FunctionName): `tTierOU Created: `t $(($TierOU.DEobj).DistinguishedName)"
                    $DeployedOrgOUs.Add($TierOU.DEobj)

                    foreach($fOU in $($FocusHash.Values)){
                        Write-Verbose "`t`t $($FunctionName): `tCreate Focus OUs under Tier: `t$fOU"

                        if($FocusProcessed -gt 1 -and 5 -gt $FocusProcessed){
                            $FocusPercentComplete = ($FocusProcessed / 4) * 100
                        }else{
                            $FocusPercentComplete = 0
                        }

                        Write-Progress -Id 20 -Activity "Focus OU Structure" -CurrentOperation "Deploying $fOU..." -Status "Processed $FocusProcessed" -PercentComplete $FocusPercentComplete -ParentId 15

                        if($pscmdlet.ShouldProcess("$fOU","Create Focus")){
                            $focusOU = New-ADDADObject -ObjName $fOU -ObjParentDN $(($TierOU.DEobj).DistinguishedName) -ObjDescription $fOU -ObjType organizationalUnit
                        }else {
                            $focusOU = @{DistinguishedName = "OU=$fOU,OU=$cOU,$DomDN"}
                        }

                        if($focusOU){
                            Write-Verbose "`t`t $($FunctionName): `tFocusOU Created: `t $(($FocusOU.DEobj).DistinguishedName)"                           
                            $DeployedOrgOUs.Add($focusOU.DEobj)

                            switch ($fOU) {
                                'ADM' {
                                    foreach($admOU in $AdmOrg){
                                        # Filter out any Scope Layer OUs that shouldn't be in this tier
                                        if($cOU -in $(ConvertTo-ADDRiskTier -intValue $($admOU.OU_tierassoc) -ReturnFull)){
                                            if($AdmOrgProcessed -gt 1 -and $($AdmOrg.Count) -gt $AdmOrgProcessed){
                                                $AdmOrgPercentComplete = ($AdmOrgProcessed / $($AdmOrg.Count)) * 100
                                            }else{
                                                $AdmOrgPercentComplete = 0
                                            }
                    
                                            Write-Progress -Id 25 -Activity "ADM Org OU Structure" -CurrentOperation "Deploying $($admOU.OU_name)..." -Status "Processed $AdmOrgProcessed" -PercentComplete $AdmOrgPercentComplete -ParentId 20
                                            
                                            # Create scope OU
                                            if($pscmdlet.ShouldProcess("$($admOU.OU_name)","$($fOU): Create Scope")){
                                                $mOU = New-ADDADObject -ObjName $($admOU.OU_name) -ObjParentDN $(($focusOU.DEobj).DistinguishedName) -ObjDescription $($admOU.OU_friendlyname) -ObjType organizationalUnit
                                            }else {
                                                $mOU = @{DistinguishedName = "OU=$($admOU.OU_name),OU=$fOU,OU=$cOU,$DomDN"}
                                            }

                                            if ($mOU) {
                                                Write-Verbose "`t`t $($FunctionName): `tScopeOU Created: `t $(($mOU.DEobj).DistinguishedName)"                           
                            
                                                $DeployedOrgOUs.Add($mOU.DEobj)

                                                # Create object class layer OUs
                                                foreach($admItem in $AdmObjTypes){
                                                    if ($pscmdlet.ShouldProcess("$ADMitem","$($admOU.OU_name): Create Class")) {
                                                        $admIOU = New-ADDADObject -ObjName $admItem -ObjParentDN $(($mOU.DEobj).DistinguishedName) -ObjDescription $admItem -ObjType organizationalUnit 
                                                    }else {
                                                        $admIOU = @{DistinguishedName = "OU=$admItem,OU=$($admOU.OU_name),OU=$fOU,OU=$cOU,$DomDN"}
                                                    }

                                                    if($admIOU){

                                                        $DeployedOrgOUs.Add($admIOU.DEobj)

                                                        $ContinueOrgOUs.Add($admIOU.DEobj)
                                                        Write-Verbose "`t`t $($FunctionName): `tContinueOrg Count: `t$($ContinueOrgOUs.Count)"
                                                    }else {
                                                        Write-Error "Failed to deploy admin type OU ($admItem)"

                                                        $FailedCount ++
                                                    }

                                                    $ProcessedCount ++
                                                }
                                                
                                            }else {
                                                Write-Error "Failed to deploy adm org OU ($admOU)"

                                                $FailedCount ++
                                            }                  
                                            
                                            $ProcessedCount ++
                                            $ADMOrgProcessed ++
                                        }
                                    } # End ADM Scope create loop

                                    Write-Progress -Id 25 -Activity "ADM Org OU Structure" -CurrentOperation "Finished" -Completed -ParentId 20

                                } # End ADM switch option

                                'SRV' {
                                    foreach($sOrg in $($SrvOrg | Where-Object{$_.OU_orglvl -eq 3})){
                                        # Filter out any Scope Layer OUs that shouldn't be in this tier
                                        if($cOU -in $(ConvertTo-ADDRiskTier -intValue $($sOrg.OU_tierassoc) -ReturnFull)){
                                            if($SrvOrgProcessed -gt 1 -and $($SrvOrg.Count) -gt $SrvOrgProcessed){
                                                $SrvOrgPercentComplete = ($SrvOrgProcessed / $($SrvOrg.Count)) * 100
                                            }else{
                                                $SrvOrgPercentComplete = 0
                                            }
                    
                                            Write-Progress -Id 25 -Activity "Srv Org OU Structure" -CurrentOperation "Deploying $sOrg..." -Status "Processed $SrvOrgProcessed" -PercentComplete $SrvOrgPercentComplete -ParentId 20

                                            # Create scope OU
                                            if ($pscmdlet.ShouldProcess("$sOrg")) {
                                                $vOU = New-ADDADObject -ObjName $($sOrg.OU_name) -ObjParentDN $(($focusOU.DEObj).DistinguishedName) -ObjDescription $($sOrg.OU_friendlyname) -ObjType organizationalUnit
                                            }else {
                                                $vOU = @{DistinguishedName = "OU=$sOrg,OU=$fOU,OU=$cOU,$DomDN"}
                                            }

                                            if($vOU){
                                                # Check for child OUs for this specific scope OU
                                                $SrvChildren = $SrvOrg | Where-Object{$_.OU_orglvl -eq 4 -and $_.OU_parent -eq $sOrg.OU_id}

                                                if($SrvChildren){
                                                    foreach($srvChild in $SrvChildren){
                                                        # Create child OU under specified Scope OU
                                                        if ($pscmdlet.ShouldProcess("$srvChild")) {
                                                            $scOU = New-ADDADObject -ObjName $($srvChild.OU_name) -ObjParentDN $(($vOU.DEObj).DistinguishedName) -ObjDescription $($srvChild.OU_friendlyname) -ObjType organizationalUnit
                                                        }else {
                                                            $scOU = @{DistinguishedName = "OU=$($srvChild.OU_name),OU=$($sOrg.OU_name),OU=$fOU,OU=$cOU,$DomDN"}
                                                        }
            
                                                        if($scOU){
                                                            # If we succeeded, add to both tracking and output
                                                            $DeployedOrgOUs.Add($scOU.DEobj)
            
                                                            $ContinueOrgOUs.Add($scOU.DEobj)
                                                        }else {
                                                            Write-Error "Failed to deploy server org OU ($($srvChild.OU_name))"
            
                                                            $FailedCount ++
                                                        }
                                                    } # End SRV Scope Child create loop

                                                    $ProcessedCount ++
                                                }

                                                # Since we set ACLs at first scope for SRV, add to both tracking and output
                                                $DeployedOrgOUs.Add($vOU.DEobj)

                                                $ContinueOrgOUs.Add($vOU.DEobj)

                                                $ProcessedCount ++

                                            }else {
                                                Write-Error "Failed to deploy server org OU ($sOrg)"

                                                $FailedCount ++
                                            }
                                        }
                                    } # End SRV Scope create loop

                                    Write-Progress -Id 25 -Activity "Srv Org OU Structure" -CurrentOperation "Finished" -Completed -ParentId 20
                                } # End SRV switch option

                                'STD' {
                                    foreach($sTOrg in $StdOrg){
                                        # Filter out any Scope Layer OUs that shouldn't be in this tier
                                        if($cOU -in $(ConvertTo-ADDRiskTier -intValue $($sTOrg.OU_tierassoc) -ReturnFull)){
                                            if($StdOrgProcessed -gt 1 -and $($StdOrg.Count) -gt $StdOrgProcessed){
                                                $StdOrgPercentComplete = ($StdOrgProcessed / $($StdOrg.Count)) * 100
                                            }else{
                                                $StdOrgPercentComplete = 0
                                            }
                    
                                            Write-Progress -Id 25 -Activity "STD Org OU Structure" -CurrentOperation "Deploying $sTOrg..." -Status "Processed $StdOrgProcessed" -PercentComplete $StdOrgPercentComplete -ParentId 20
                                            
                                            # Create scope OU
                                            if ($pscmdlet.ShouldProcess("$($sTOrg.OU_name)")) {
                                                $oOU = New-ADDADObject -ObjName $($sTOrg.OU_name) -ObjParentDN $(($focusOU.DEObj).DistinguishedName) -ObjDescription $($sTOrg.OU_friendlyname) -ObjType organizationalUnit
                                            }else {
                                                $oOU = @{DistinguishedName = "OU=$($sTOrg.OU_name),OU=$fOU,OU=$cOU,$DomDN"}
                                            }

                                            if($oOU){
                                                # If we succeeded, add to tracking only - ACLs not set at this level
                                                $DeployedOrgOUs.Add($(($oOU.DEobj).DistinguishedName))

                                                foreach($stdItem in $StdObjTypes){
                                                    # Create object class OU
                                                    if ($pscmdlet.ShouldProcess("$stdItem")) {
                                                        $dOU = New-ADDADObject -ObjName $stdItem -ObjParentDN $(($oOU.DEObj).DistinguishedName) -ObjDescription $stdItem -ObjType organizationalUnit
                                                    }else {
                                                        $dOU = @{DistinguishedName = "OU=$stdItem,OU=$sTOrg,OU=$focusOU,OU=$cOU,$DomDN"}
                                                    }

                                                    if($dOU){
                                                        # If we succeeded, add to both tracking and output
                                                        $DeployedOrgOUs.Add($dOU.DEobj)

                                                        $ContinueOrgOUs.Add($dOU.DEobj)
                                                    }else {
                                                        Write-Error "Failed to create object type OU ($stdItem)"
                                                        $FailedCount ++
                                                    }

                                                    $ProcessedCount ++
                                                }
                                            }else {
                                                Write-Error "Failed to deploy org OU ($sTOrg)"
                                                $FailedCount ++
                                            }

                                            $ProcessedCount ++
                                            $StdOrgProcessed ++
                                        }
                                    } # End STD Scope create loop

                                    Write-Progress -Id 25 -Activity "STD Org OU Structure" -CurrentOperation "Finished" -Completed -ParentId 20
                                } # End STD switch option

                                'STG' {
                                    Write-Verbose "STG focus detected - Deploying object types..."
                                    # No need to perform Tier check since STG is the same in all Tiers
                                    foreach($stgItem in $StgObjTypes){
                                        if ($pscmdlet.ShouldProcess("$stgItem")) {
                                            $sOU = New-ADDADObject -ObjName $stgItem -ObjParentDN $(($focusOU.DEObj).DistinguishedName) -ObjDescription $stgItem -ObjType organizationalUnit
                                        }else {
                                            $sOU = @{DistinguishedName = "OU=$stgItem,OU=$sTOrg,OU=$fOU,OU=$cOU,$DomDN"}
                                        }

                                        if($sOU){
                                            # If we succeeded, add to both tracking and output
                                            $DeployedOrgOUs.Add($sOU.DEobj)

                                            $ContinueOrgOUs.Add($sOU.DEobj)
                                        }else {
                                            Write-Error "Failed to create object type OU ($stgItem)"
                                            $FailedCount ++
                                        }

                                        $ProcessedCount ++
                                    }
                                } # End STG Scope create loop
                            } # End STG switch option

                        }else {
                            Write-Error "Failed to create focus OU ($fOU)"
                            $FailedCount ++
                        }

                        $ProcessedCount ++
                        $FocusProcessed ++
                    } # End Focus create loop

                    Write-Progress -Id 20 -Activity "Focus OU Structure" -CurrentOperation "Finished" -Completed -ParentId 15
                }else {
                    Write-Error "Failed to create tier OU ($cOU)"

                    $FailedCount ++
                }

                $ProcessedCount ++
                $TierProcessed ++
            } # End Tier create loop

            Write-Progress -Id 15 -Activity "Tier OU Structure" -CurrentOperation "Finished" -Completed -ParentId 10
        }else {
            $ExecDBUpdate = $false

            if($Tier){
                Write-Verbose "`t`t $($FunctionName):`t Tier Provided:`t $($Tier)"
                $ParentDN = "OU=Tier-$($Tier),$DomDN"
                
                switch ($Tier) {
                    0 { $TierAssoc = 1 }
                    1 { $TierAssoc = 2 }
                    2 { $TierAssoc = 3 }
                }
                
                Write-Verbose "`t`t $($FunctionName):`t WhatIf not specified"
                
                foreach($Foc in $FocusList){
                    Write-Verbose "`t`t $($FunctionName):`t  Focus Provided:`t $($Foc) - Updating ParentDN"
                    $ParentDN = "OU=$($Foc),$($ParentDN)"
                    
                    switch ($Foc) {
                        "ADM" { 
                            $ClassOU = $AdmObjTypes
                        }
                        "SRV" { 
                            $ClassOU = $SrvOrg | Where-Object{$_.OU_orglvl -eq 4 -and $_.OU_parent -eq $sOrg.OU_id}
                        }
                        "STD" { 
                            $ClassOU = $StdObjTypes
                        }
                    }

                    if($PSCmdlet.ShouldProcess("$ScopeNode","Create new scope")){
                        Write-Verbose "`t`t $($FunctionName):`t Preparing to call New-ADDADObject with following values:"
                        Write-Verbose "`t`t $($FunctionName):`t`t`t`tObjName:`t ScopeNode:`t $ScopeNode"
                        Write-Verbose "`t`t $($FunctionName):`t`t`t`tObjParentDN:`t ParentDN:`t $ParentDN"
                        Write-Verbose "`t`t $($FunctionName):`t`t`t`tObjDescription:`t ScopeFriendly:`t $ScopeNode"
                        $sOU = New-ADDADObject -ObjName "$ScopeNode" -ObjParentDN $ParentDN -ObjDescription "$ScopeFriendly" -ObjType organizationalUnit

                        if($sOU){
                            $DeployedOrgOUs.Add($(($sOU.DEobj).DistinguishedName))
                            $ExecDBUpdate = $true
                            
                            # Create object class OU
                            if ($null -ne $ClassOU) {
                                foreach($cItem in $ClassOU){
                                        
                                    $cOU = New-ADDADObject -ObjName $cItem -ObjParentDN $(($sOU.DEObj).DistinguishedName) -ObjDescription $cItem -ObjType organizationalUnit
                                    
                                    if($cOU){
                                        # If we succeeded, add to both tracking and output
                                        $DeployedOrgOUs.Add($cOU.DEobj)

                                        $ContinueOrgOUs.Add($cOU.DEobj)

                                    }else {
                                        Write-Error "Failed to create object type OU ($cItem)"

                                        $FailedCount ++
                                    }
                                } # End child create loop
                                            
                                $ProcessedCount ++
                            } # End ShouldProcess Child Create
                            #TODO: Fix loops in mass deploy section so using '-WhatIf' doesn't break tracking
                            
                        }else{
                            Write-Error "Failed to deploy scope OU ($ScopeNode)"

                            $FailedCount ++
                        } # End child create loop
                    }else{
                        $sOU = @{DistinguishedName = "OU=$ScopeNode,OU=$Foc,OU=Tier-$($Tier),$DomDN"}
                        $DeployedOrgOUs += $sOU

                        if($Foc -like $($FocusHash["Server"])){
                            $ContinueOrgOUs += $sOU
                        }

                        if ($null -ne $ClassOU) {
                            foreach($cItem in $ClassOU){
                                $cOU = @{DistinguishedName = "OU=$cItem,OU=$ScopeNode,OU=$Foc,OU=Tier-$($Tier),$DomDN"}
                                
                                $DeployedOrgOUs += $cOU
                                
                                $ContinueOrgOUs += $cOU
                            }
                        }
                    } # End if/else ShouldProcess
                }

            }else {
                foreach($Tier in $($CETierHash.Values)){
                    $ParentDN = "OU=$($Tier),$DomDN"
                    $TierAssoc = 0

                    foreach($Foc in $FocusList){
                        Write-Verbose "`t`t $($FunctionName):`t  Focus Provided:`t $($Foc) - Updating ParentDN"
                        $ParentDN = "OU=$($Foc),$($ParentDN)"
                        
                        switch ($Foc) {
                            "ADM" { 
                                $ClassOU = $AdmObjTypes
                            }
                            "SRV" { 
                                $ClassOU = $SrvOrg | Where-Object{$_.OU_orglvl -eq 4 -and $_.OU_parent -eq $sOrg.OU_id}
                            }
                            "STD" { 
                                $ClassOU = $StdObjTypes
                            }
                        }
    
                        if($PSCmdlet.ShouldProcess("$ScopeNode","Create new scope")){
                            $sOU = New-ADDADObject -ObjName "$ScopeNode" -ObjParentDN "$ParentDN" -ObjDescription "$ScopeFriendly" -ObjType organizationalUnit
    
                            if($sOU){
                                $ExecDBUpdate = $true
                                
                                $DeployedOrgOUs.Add($(($sOU.DEobj).DistinguishedName))
                                
                                # Create object class OU
                                if ($null -ne $ClassOU) {
                                    foreach($cItem in $ClassOU){
                                            
                                        $cOU = New-ADDADObject -ObjName $cItem -ObjParentDN $(($sOU.DEObj).DistinguishedName) -ObjDescription $cItem -ObjType organizationalUnit
                                        
                                        if($cOU){
                                            # If we succeeded, add to both tracking and output
                                            $DeployedOrgOUs.Add($cOU.DEobj)
    
                                            $ContinueOrgOUs.Add($cOU.DEobj)
                                        }else {
                                            Write-Error "Failed to create object type OU ($cItem)"
    
                                            $FailedCount ++
                                        }
                                    } # End child create loop
                                                
                                    $ProcessedCount ++
                                } # End ShouldProcess Child Create
                                #TODO: Fix loops in mass deploy section so using '-WhatIf' doesn't break tracking
                                
                            }else{
                                Write-Error "Failed to deploy scope OU ($ScopeNode)"
    
                                $FailedCount ++
                            } # End child create loop
                        }else{
                            $sOU = @{DistinguishedName = "OU=$ScopeNode,OU=$Foc,OU=Tier-$($Tier),$DomDN"}
                            $DeployedOrgOUs += $sOU
    
                            if($Foc -like $($FocusHash["Server"])){
                                $ContinueOrgOUs += $sOU
                            }
    
                            if ($null -ne $ClassOU) {
                                foreach($cItem in $ClassOU){
                                    $cOU = @{DistinguishedName = "OU=$cItem,OU=$ScopeNode,OU=$Foc,OU=Tier-$($Tier),$DomDN"}
                                    
                                    $DeployedOrgOUs += $cOU
                                    
                                    $ContinueOrgOUs += $cOU
                                }
                            }
                        } # End if/else ShouldProcess
                    } # End foreach Focus
                } # End foreach Tier
            } # End if/else Tier

            if($ExecDBUpdate){
                Write-Verbose "`t`t $($FunctionName):`t Updating Database"
                Export-ADDModuleData -DataSet AddOrgEntrySPL -QueryValue $ScopeNode,$ScopeFriendly,$ouADM,$ouSRV,$ouSTD,$TierAssoc
                
                Write-Verbose "`t`t $($FunctionName):`t Updating Variable"
                $OrgData = Import-ADDModuleData -DataSet OUOrg
                Set-Variable -Name OUOrg -Value $OrgData -Scope Script -Visibility Private
            }
        }

        $GCloopCount ++
        $loopCount ++
        $loopTimer.Stop()
        $loopTime = $loopTimer.Elapsed.TotalSeconds
        $loopTimes += $loopTime
        Write-Verbose "`t`t $($FunctionName): `tLoop $($ProcessedCount) Time (sec):`t$loopTime"

        if($loopTimes.Count -gt 2){
            $loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
            $loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
            Write-Verbose "`t`t $($FunctionName): `tAverage Loop Time (sec):`t$loopAverage"
            Write-Verbose "`t`t $($FunctionName): `tTotal Elapsed Time (sec):`t$loopTotalTime"
        }
        $loopTimer.Reset()
        Write-Verbose ""
        Write-Verbose "`t`t****************** $($FunctionName): End of loop ($loopCount) ******************"
        Write-Verbose ""
    }

    End {
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "`t`t $($FunctionName): Wrapping Up"
        Write-Verbose "`t`tTDGs procesed:`t$ProcessedCount"
        Write-Verbose "`t`tTDGs failed:`t$FailedCount"
        $FinalLoopTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 0)
        $FinalAvgLoopTime = [math]::Round(($loopTimes | Measure-Object -Average).Average, 0)
        Write-Verbose "`t`tTotal time (sec):`t$FinalLoopTime"
        Write-Verbose "`t`tAvg Loop Time (sec):`t$FinalAvgLoopTime"
        Write-Verbose ""


        if($DeployAll){
            Write-Progress -Id 10 -Activity "$FunctionName" -Status "Finished Processing OUs..." -Completed
        }

        if ($pscmdlet.ShouldProcess('ContinueOrgOUs','Export results')) {
            Write-Output $ContinueOrgOUs
        }else {
            Write-Host "WhatIf was used so no object were created. "
            Write-Host "Had WhatIf not been used, the following would have been created and returned to the pipeline:"
            $ContinueOrgOUs
        }
        Write-Verbose "------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
    }
}