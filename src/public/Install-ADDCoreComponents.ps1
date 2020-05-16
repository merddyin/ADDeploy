function Install-ADDCoreComponents {
<#
    .SYNOPSIS
        Deploy core elements of the ESAE structure, to include pre-requisites for 'Red Forest Takeover'

    .DESCRIPTION
        Deploys the shared services, or global objects container into the Admin focus containers for each Tier. Also deploys the global groups used for Tier Control
        and Classification groups used throughout the implementation. Finally, this cmdlet sets the required base ACLs to enable implementation of 'Gold Card Admin'.

        Note: This cmdlet is dependent upon the Tier and Focus level deployment having already been completed. Typically this cmdlet would be called exclusively from
        the Publish-ADDESAEStructure cmdlet.

    .PARAMETER TargetPath
        One or more DirectoryEntry objects representing the Admin Focus containers into which the shared services, or global objects will be deployed.

    .EXAMPLE
        PS C:\> $AdminDEArray | Deploy-ADDCoreComponents

        Takes and array of DirectoryEntry objects and passes it via the pipeline to deploy all core components. The shared servces, or global, OUs, groups, and other
        objects will be created in each path if it is the defined Admin focus path, and all root permissions will be set.

    .INPUTS
        System.DirectoryServices.DirectoryEntry

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Help Last Updated: 10/22/2019

        Cmdlet Version: 0.9.0 - Beta

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
    Param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.DirectoryServices.DirectoryEntry]
        $TargetPath,

        [Parameter()]
        [Switch]$RunRedir,

        [Parameter(DontShow)]
        [Switch]$MTRun
    )

    begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""
        #TODO: Add WhatIf processing support to all action items

        if($InitDep -eq 1){
            $SkipCore = $True
        }

        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Deploy Core Components" -CurrentOperation "Initializing..." -ParentId 10
        }

        $DeployResults = @{}

        $CoreGroups = $CoreOUs | Where-Object{$_.OU_type -like "Group"}
        $DeployCoreResults = @{}

        $PathsProcessed = 0
        $PathsSkipped = 0
        $SharedOUsCreated = 0
        $SharedOUsExisting = 0
        $FailedCount = 0
        $TDGsCreated = 0
        $TDGsExisting = 0
        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $subloopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()
    }

    process {
        Write-Verbose ""
        Write-Verbose "$($LPP1)`t`t****************** Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

		# Enforced .NET garbage collection to ensure memory utilization does not balloon
		if($GCloopCount -eq 30){
			Run-MemClean
			$GCloopCount = 0
		}

        $TargetOUDe = $_
        $TargetOUDN = $TargetOUDe.distinguishedName
        Write-Verbose "$($LPP2)`t`tProcessing Path:`t$TargetOUDN"

        $DNFocusID = ($TargetOUDN | Select-String -Pattern $($FocusDNRegEx -join "|")).Matches.Value
        if($DNFocusID){
            $FocusID = ($DNFocusID -split "=")[1]
            Write-Verbose "$($LPP3)`t`tDerived FocusID:`t$FocusID"
        }

        $DNTierID = ($TargetOUDN | Select-String -Pattern $($CETierDNRegEx -join "|")).Matches.Value
        $FullTierID = ($DNTierID -split "=")[1]
        $TierID = $TierHash[$FullTierID]
        Write-Verbose "$($LPP3)`t`tDerived TierID:`t$TierID"

        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Deploy $TierID Core Components" -CurrentOperation "Creating Shared Services OUs" -ParentId 10
        }

        $FinalGlobalOUDE = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $WFFinalGlobalOUDE = New-Object System.Collections.Generic.List[psobject]

        if($FocusID -match $FocusHash["Admin"]){
            Write-Verbose ""
            Write-Verbose "$($LPP2)`t`tCreate Shared Svcs Elements"

            #region SharedSvcsOrgOUs
            Write-Verbose "$($LPP2)`t`tShared Svcs OU:`tOrg Lvl 1"
            $GOUL1DN = "OU=$OUGlobal,$TargetOUDN"

            if($pscmdlet.ShouldProcess($OUGlobal, "Create Shared Svcs Org Lvl 1")){
                $GOUL1obj = New-ADDADObject -ObjName $OUGlobal -ObjParentDN $TargetOUDe.distinguishedName -ObjType "organizationalUnit"

                if($GOUL1obj){
                    switch ($GOUL1obj.State) {
                        {$_ -like "New"} {
                            Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                            Write-Verbose ""
                            $SharedOUsCreated ++
                        }

                        {$_ -like "Existing"} {
                            Write-Verbose "$($LPP3)`t`tTask Outcome:`tAlready Exists"
                            Write-Verbose ""
                            $SharedOUsExisting ++
                        }

                        Default {
                            Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                            Write-Verbose "$($LPP3)`t`tFail Reason:`t$($GOUL1obj.State)"
                            $FailedCount ++
                            Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 1 Global OU - Quitting" -ErrorAction Stop
                        }
                    }
                }else {
                    Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                    Write-Verbose "$($LPP3)`t`tFail Reason:`tUnknown - No Lvl 1 Object Returned"
                    $FailedCount ++
                    Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 1 Global OU - Quitting" -ErrorAction Stop
                }
            }else {
                Write-Verbose ""
                Write-Verbose "$($LPP3)`t`t+++ WhatIf Detected - Would create OU ($OUGlobal) in path $TargetOUDN +++"
                Write-Verbose ""

                $WFFinalGlobalOUDE.Add($GOUL1DN)
                $SharedOUsCreated ++
            }

            if($MaxLevel -ge 2){
                Write-Verbose "$($LPP2)`t`tShared Svcs OU:`tOrg Lvl 2"
                $GOUL2DN = "OU=$OUGlobal,$GOUL1DN"

                if($pscmdlet.ShouldProcess($OUGlobal, "Create Shared Svcs Org Lvl 2")){
                    $GOUL2obj = New-ADDADObject -ObjName $OUGlobal -ObjParentDN $GOUL1obj.DEObj.distinguishedName -ObjType "organizationalUnit"

                    if($GOUL2obj){
                        switch ($GOUL2obj.State) {
                            {$_ -like "New"} {
                                Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                                Write-Verbose ""
                                $SharedOUsCreated ++
                            }

                            {$_ -like "Existing"} {
                                Write-Verbose "$($LPP3)`t`tTask Outcome:`tAlready Exists"
                                Write-Verbose ""
                                $SharedOUsExisting ++
                            }

                            Default {
                                Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                                Write-Verbose "$($LPP3)`t`tFail Reason:`t$($GOUL2obj.State)"
                                $FailedCount ++
                                Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 2 Global OU - Quitting" -ErrorAction Stop
                            }
                        } #EndSwitch - GOUL2obj.State

                    }else {
                        Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                        Write-Verbose "$($LPP3)`t`tFail Reason:`tUnknown - No Lvl 2 Object Returned"
                        $FailedCount ++
                        Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 2 Global OU - Quitting" -ErrorAction Stop
                    } #EndIf - GOUL2obj Exists

                }else {
                    Write-Verbose ""
                    Write-Verbose "$($LPP3)`t`t+++ WhatIf Detected - Would create OU ($OUGlobal) in path $GOUL1DN +++"
                    Write-Verbose ""
                    $SharedOUsCreated ++
                } #EndIf - WhatIf Check

                if($MaxLevel -eq 3){
                    Write-Verbose "$($LPP2)`t`tShared Svcs OU:`tOrg Lvl 3"
                    $GOUL3DN = "OU=$OUGlobal,$GOUL2DN"

                    if($pscmdlet.ShouldProcess($OUGlobal, "Create Shared Svcs Org Lvl 3")){
                        $GOUL3obj = New-ADDADObject -ObjName $OUGlobal -ObjParentDN $GOUL2obj.DEObj.distinguishedName -ObjType "organizationalUnit"

                        if($GOUL3obj){
                            switch ($GOUL3obj.State) {
                                {$_ -like "New"} {
                                    Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                                    Write-Verbose ""
                                    $FinalGlobalOUDE.Add($GOUL3obj.DEObj)
                                    $SharedOUsCreated ++
                                }

                                {$_ -like "Existing"} {
                                    Write-Verbose "$($LPP3)`t`tTask Outcome:`tAlready Exists"
                                    Write-Verbose ""
                                    $FinalGlobalOUDE.Add($GOUL3obj.DEObj)
                                    $SharedOUsExisting ++
                                }

                                Default {
                                    Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                                    Write-Verbose "$($LPP3)`t`tFail Reason:`t$($GOUL3obj.State)"
                                    $FailedCount ++
                                    Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 3 Global OU - Quitting" -ErrorAction Stop
                                }
                            } #EndSwitch - GOUL3obj.State
                        }else {
                            Write-Verbose "$($LPP3)`t`tOutcome:`tFailed"
                            Write-Verbose "$($LPP3)`t`tFail Reason:`tUnknown - No Lvl 3 Object Returned"
                            $FailedCount ++
                            Write-Error "!!! CATASTROPHIC FAILURE !!! Failed to create Level 3 Global OU - Quitting" -ErrorAction Stop
                        } #EndIf - $GOUL3obj Exists

                    }else {
                        Write-Verbose ""
                        Write-Verbose "$($LPP3)`t`t+++ WhatIf Detected - Would create OU ($OUGlobal) in path $GOUL2DN and add result to placeholder +++"
                        Write-Verbose ""

                        $WFFinalGlobalOUDE.Add($GOUL3DN)
                        $SharedOUsCreated ++
                    } #EndIf - WhatIf Check

                }else {
                    if($pscmdlet.ShouldProcess($OUGlobal, "Add Lvl 2 output to placeholder")){
                        $FinalGlobalOUDE.Add($GOUL2obj.DEObj)
                    }else {
                        $WFFinalGlobalOUDE.Add($GOUL2DN)
                    } #EndIf - WhatIf Check

                } #EndIf - MaxLevel 3 Check

            }else {
                if($pscmdlet.ShouldProcess($OUGlobal, "Add Lvl 1 output to placeholder")){
                    $FinalGlobalOUDE.Add($GOUL1obj.DEObj)
                }else {
                    $WFFinalGlobalOUDE.Add($GOUL1DN)
                } #EndIf - WhatIf Check

            } #EndIf - MaxLevel 2 Check
            #endregion SharedSvcsOrgOUs

            #region SharedSvcsObjOU-TDG-ACLs
            if(!($MTRun)){
                Write-Progress -Id 15 -Activity "Deploy $TierID Core Components" -CurrentOperation "Creating Shared Services Object Type OUs" -ParentId 10
            }
            Write-Verbose "$($LPP2)`t`tAdding Object Type Support"

            if($FinalGlobalOUDE){
                $StageGlobalOU = $FinalGlobalOUDE
                $OrgOUResults = $true
            }elseif($WFFinalGlobalOUDE){
                $StageGlobalOU = $WFFinalGlobalOUDE
                $OrgOUResults = $true
            }else{
                $OrgOUResults = $false
            } #EndIf - SharedSvcs Task Output Check

            Write-Verbose "$($LPP2)`t`tObject Type OUs"
            $GBLObjTypeOUs = $StageGlobalOU | New-ADDObjLvlOU -ChainRun -PipelineCount $($StageGlobalOU.Count)

            if($GBLObjTypeOUs){
                $ObjectOUResults = $true

                Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                Write-Verbose ""

                if(!($MTRun)){
                    Write-Progress -Id 15 -Activity "Deploy $TierID Core Components" -CurrentOperation "Creating Shared Services Task Delegation Groups" -ParentId 10
                }
                Write-Verbose "$($LPP2)`t`tCreate TDGs"
                $TDGPipeCount = $GBLObjTypeOUs.Count
                Write-Verbose "$($LPP3)`t`tOU Count:`t$TDGPipeCount"
                $GBLTDGs = $GBLObjTypeOUs | New-ADDTaskGroup -ChainRun -PipelineCount $TDGPipeCount
                Write-Verbose "$($LPP3)`t`tGBL TDG Count:`t$($GBLTDGs)"
            }else{
                $ObjectOUResults = $false

                Write-Verbose "$($LPP3)`t`tTask Outcome:`tFailed"
                Write-Warning "$($LPP3)`t`tFailed to create Object Type containers - Some additional processes may fail"
            } # GBLObjTypeOUs

            if($GBLTDGs){
                Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                Write-Verbose ""
                $TDGResults = $true

                if(!($MTRun)){
                    Write-Progress -Id 15 -Activity "Deploy $TierID Core Components" -CurrentOperation "Setting Shared Services TDG ACLs" -ParentId 10
                }
                Write-Verbose "$($LPP2)`t`tAccess Control Entries"
                $TDGPipeCount = $GBLTDGs.Count
                $ACLResults = $GBLTDGs | Grant-ADDTDGRights -ChainRun -PipelineCount $TDGPipeCount

                if($ACLResults){
                    Write-Verbose "$($LPP3)`t`tTask Outcome:`tSuccess"
                    Write-Verbose ""
                    $ACLResults = $true
                }else {
                    Write-Verbose "$($LPP3)`t`tTask Outcome:`tFailed"
                    Write-Warning "$($LPP3)`t`tFailed to create Object Type containers - Some additional processes may fail"
                    $ACLResults = $false
                } # GBLAcls
            }else {
                Write-Verbose "$($LPP3)`t`tTask Outcome:`tFailed"
                Write-Warning "$($LPP3)`t`tFailed to Global Task Delegation Groups - Some additional processes may fail"
            } # GBLTDGs
            #endregion SharedSvcsObjOU-TDG-ACLs


            if($GBLObjTypeOUs){
                if(!($MTRun)){
                    Write-Progress -Id 15 -Activity "Deploy $TierID Core Components" -CurrentOperation "Creating Tier Control Groups" -ParentId 10
                }
                Write-Verbose "$($LPP2)`t`tCreating Tier Control Groups"
                $CGPre = Join-String -Strings $TierID,$FocusID -Separator "_"
                Write-Debug "$($LPP3)`t`tCG Name Prefix Initial:`t$CGPre"
                for($i = 1; $i -lt ($MaxLevel + 1); $i++){
                    $CGPre += "_$OUGlobal"
                }

                $CGMid = Join-String -Strings "SOU","AP","TC" -Separator "_"
                Write-Debug "$($LPP3)`t`tCG Name Mid:`t$CGMid"

                $CoreTDGResult = $false

                Write-Verbose "$($LPP3)`t`tCG Name Prefix:`t$CGPre"

                foreach($GlobalOU in $StageGlobalOU){
                    $CGDestPre = "LDAP://OU=Other,OU=Groups"

                    # Adjust value based on WhatIf - DirectoryEntry object won't exist in WhatIf
                    if($WhatIfPreference){
                        $GlobalDN = $GlobalOU.DistinguishedName
                    }else {
                        $GlobalDN = $GlobalOU.DistinguishedName
                    }

                    [string]$CGDestFull = Join-String -Strings $CGDestPre,$GlobalDN -Separator ","
                    Write-Verbose "$($LPP3)`t`tCG Destination DN:`t$CGDestFull"
                    Write-Verbose ""

                    Write-Verbose "$($LPP3)`t`tProcess Core Group Names"
                    foreach($CoreGroup in $CoreGroups){
                        $CGSuffix = $CoreGroup.OU_name
                        Write-Debug "$($LPP4)`t`tCGSuffix:`t$CGSuffix"
                        [string]$CGFullName = Join-String -Strings $CGPre,$CGMid,$CGSuffix -Separator "-"

                        if($pscmdlet.ShouldProcess($CGName,"Create in $CGDestFull")){
                            Write-Verbose "$($LPP4)`t`tName:`t$CGFullName"
                            $CoreTDGObj = New-ADDADObject -ObjName $CGFullName -ObjParentDN $CGDestFull -ObjType "group"

                            if($CoreTDGObj){
                                switch ($CoreTDGObj.State) {
                                    {$_ -like "New"} {
                                        Write-Verbose "$($LPP4)`t`tTask Outcome:`tSuccess"
                                        Write-Verbose ""
                                        $TDGsCreated ++
                                        $CoreTDGResult = $true
                                    }

                                    {$_ -like "Existing"} {
                                        Write-Verbose "$($LPP4)`t`tTask Outcome:`tAlready Exists"
                                        Write-Verbose ""
                                        $CoreTDGResult = $true
                                    }

                                    Default {
                                        Write-Verbose "$($LPP4)`t`tOutcome:`tFailed"
                                        Write-Verbose "$($LPP4)`t`tFail Reason:`t$($CoreTDGObj.State)"
                                        $CoreTDGResult = $false
                                    }
                                }
                            }else {
                                Write-Verbose "$($LPP4)`t`tOutcome:`tFailed"
                                Write-Verbose "$($LPP4)`t`tFail Reason:`tUnknown - No Lvl 3 Object Returned"
                                $CoreTDGResult = $false
                                $FailedCount ++
                            }

                        }else {
                            Write-Verbose "$($LPP3)`t`t+++ WhatIf: Create TDG - $CGFullName +++"
                        } #EndIf - WhatIf Create Core TDG
                        # Logging spacer
                        Write-Verbose ""

                    } #EndForeach - CoreGroups
                    # Logging spacer
                    Write-Verbose ""

                } #EndForeach - StageGlobalOU


            }else {
                Write-Verbose "$($LPP2)`t`tNo Global Object Type Containers - Skipping creation of Tier Control Groups"
            } #EndIf - Tier Control Groups

        }else {
            Write-Verbose "$($LPP2)`t`tAdmin Focus not detected - Skipping creation of Shared Svcs Elements for this path"
        } #EndIf - FocusID matches 'Admin' focus

        # Logging spacer
        Write-Verbose ""

        $ProcessedCount ++
        $loopCount ++
        $GCloopCount ++
        $loopTimer.Stop()
        $loopTime = $loopTimer.Elapsed.TotalSeconds
        $loopTimes += $loopTime
        Write-Verbose "$($LPP2)`t`tLoop $($ProcessedCount) Time (sec):`t$loopTime"

        if($loopTimes.Count -gt 2){
            $loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
            $loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
            Write-Verbose "$($LPP2)`t`tAverage Loop Time (sec):`t$loopAverage"
            Write-Verbose "$($LPP2)`t`tTotal Elapsed Time (sec):`t$loopTotalTime"
        }
        $loopTimer.Reset()

        Write-Verbose ""
        Write-Verbose "$($LPP1)`t`t****************** End of loop ($loopCount) ******************"
        Write-Verbose ""
    }

    end {
        #TODO: Add support for skip
        Write-Verbose "$($LP)`t`tWriting Root ACLs to domain"
        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Deploy Core Components" -CurrentOperation "Setting Root and RecycleBin ACLs" -ParentId 10
        }
        if($WhatIfPreference){
            $RootDomDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomDN")
            $PartitionDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Partitions,CN=Configuration,$DomDN")
            $OptionalFeatures = $PartitionDE."msDS-EnabledFeature"
        }

        $InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]'All'
        $AdminGroupObj = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Administrators,CN=Builtin,$DomDN")
        $DelegateSID = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $AdminGroupObj.objectSid.Value, 0
        $AdminGrpACEDef = $DelegateSID,'GenericAll','Allow',$InheritanceType,$allGuid

        try {
            $aceObj = New-Object -TypeName System.DirectoryServices.ActiveDirectoryAccessRule($AdminGrpACEDef)
        }
        catch {
            Write-Error -Category InvalidData -CategoryActivity "Create aceObj" -CategoryTargetName "$SourceValue" -Message "Unable to create ACE for aceDef - `n$($aceDef | Out-String)" -ErrorAction Continue
        }

        if($aceObj){
            Write-Debug "$($LPB1)`t`tProcess Administrators ACE: aceObj - $($aceObj | Out-String)"
            Write-Verbose "$($LPB1)`t`tApplying ACEs to $($RootDomDE.DistinguishedName)"
            if($pscmdlet.ShouldProcess($DomDN,"Set root ace")){
                try {
                    $RootDomDE.psbase.ObjectSecurity.AddAccessRule($aceObj)
                    $RootDomDE.psbase.CommitChanges()
                    $GCARootACLs = $true
                    Write-Verbose "$($LPB2)`t`tOutcome:`tSuccess"
                }
                catch {
                    $GCARootACLs = $false
                    Write-Verbose "$($LPB2)`t`tOutcome:`tFail"
                }
            }else {
                Write-Verbose "$($LPB2)`t`t+++ WhatIf Detected - Would write FullControl ACE for BUILTIN\Administrators to domain root +++"
            }

            if($pscmdlet.ShouldProcess("Recycle Bin","Set RB ACE")){
                if($OptionalFeatures -like "*Recycle Bin Feature*"){
                    Write-Verbose "$($LPB1)`t`tRecycle Bin Status:`tEnabled"
                    $DelObjDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Recycle Bin Feature,CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,$DomDN")
                    Write-Verbose "$($LPB2)`t`tApplying ACEs to $($DelObjDE.DistinguishedName)"
                    try {
                        $DelObjDE.psbase.ObjectSecurity.AddAccessRule($aceObj)
                        $DelObjDE.psbase.CommitChanges()
                        $GCARecycleACLs = $true
                        Write-Verbose "$($LPB2)`t`tOutcome:`tSuccess"
                    }
                    catch {
                        $GCARecycleACLs = $false
                        Write-Verbose "$($LPB2)`t`tOutcome:`tFail"
                    }
                }else {
                    Write-Verbose "$($LPB1)`t`tRecycle Bin Status:`tDisabled"
                }
            }else {
                Write-Verbose "$($LPB1)`t`t+++ WhatIf Detected - Would write FullControl ACE for BUILTIN\Administrators to domain Recycle Bin (if enabled) +++"
                $GCARecycleACLs = $true
            }
        }else{
            Write-Debug "$($LPB1)`t`tProcess Administrators ACE: Failure - No ACE object"
        }

		$DeployResults.Add("DeployStatus",$true)

        Write-Verbose ""
        Write-Verbose "$($LP)`t`tWrapping Up"
        Write-Verbose "$($LPB1)`t`tSource Paths Procesed:`t$ProcessedCount"
        Write-Verbose "$($LPB1)`t`tOrg OUs Processed:`t$TotalOrgProcessed"
        Write-Verbose "$($LPB1)`t`tNew Org OUs Created:`t$NewCount"
        Write-Verbose "$($LPB1)`t`tPre-Existing Org OUs:`t$ExistingCount"
        Write-Verbose "$($LPB1)`t`tFailed Org OUs:`t$FailedCount"
        Write-Verbose ""

        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Creating OUs" -CurrentOperation "Finished" -Completed -ParentId 10
        }

        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
        Write-Verbose ""

        return $DeployResults

    }
}