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
        [Parameter()]
        [Switch]$NoRedir
    )

    begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""
        #TODO: Identify what is causing multiple TC groups to be deployed for each tier
        #TODO: Review and update variable contents to use global options from postload where possible
        #TODO: Update redir functionality to eliminate requirement for AD Module (unless AD Module is needed for Audit SACL)
        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Deploy Core Components" -CurrentOperation "Initializing..." -ParentId 10
        }

        $DeployResults = @{}

        $CoreGroups = $CoreData | Where-Object{$_.OU_type -like "Group"}
        $OUGlobal = ($CoreData | Where-Object {$_.OU_focus -like "Global"}).OU_name
        Write-Verbose "OUGlobal `t $OUGlobal"

        $FailedCount = 0
        $TDGsCreated = 0
        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()
    } #End Begin block

    process {
        Write-Verbose ""
        Write-Verbose "$($LPP1)`t`t****************** Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

        # Enforced .NET garbage collection to ensure memory utilization does not balloon
        if($GCloopCount -eq 30){
            Invoke-MemClean
            $GCloopCount = 0
        }

        foreach($cOU in $($CETierHash.Values)){
            $TierPath = "OU=$cOU,$DomDN"
            Write-Verbose "TierPath: `t $TierPath"
            $TierID = $TierHash["$cOU"]

            foreach($FocusID in $($FocusHash.Values)){          
                $ParentDN = "OU=Tasks,OU=$OUGlobal,OU=$($Focushash['Admin']),$TierPath"
                Write-Verbose "ParentDN: `t $ParentDN"
                $GlobalOU = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$ParentDN")
                Write-Verbose "GloballOU: `t $($GlobalOU.DistinguishedName)"

                Write-Verbose "$($LPP2)`t`tCreating Tier Control Groups"
                $CGPre = Join-String -Strings $TierID,$FocusID -Separator "_"
                Write-Debug "$($LPP3)`t`tCG Name Prefix Initial:`t$CGPre"
                for($i = 1; $i -lt ($MaxLevel + 1); $i++){
                    $CGPre += "_$OUGlobal"
                }
        
                $CGMid = Join-String -Strings "SOU","AP","TC" -Separator "_"
                Write-Debug "$($LPP3)`t`tCG Name Mid:`t$CGMid"
        
                Write-Verbose "$($LPP3)`t`tCG Name Prefix:`t$CGPre"
        
                $GlobalDN = $GlobalOU.DistinguishedName
                Write-Verbose "GloablDN: `t $($GlobalOU.DistinguishedName)"
                Write-Verbose "$($LPP3)`t`tCG Destination DN:`t$GlobalDN"
                Write-Verbose ""          
                
                Write-Verbose "$($LPP3)`t`tProcess Core Group Names"
                foreach($CoreGroup in $CoreGroups){
                    $CGSuffix = $CoreGroup.OU_name
                    Write-Debug "$($LPP4)`t`tCGSuffix:`t$CGSuffix"
                    [string]$CGFullName = Join-String -Strings $CGPre,$CGMid,$CGSuffix -Separator "-"
        
                    if($pscmdlet.ShouldProcess($CGName,"Create in $GlobalDN")){
                        Write-Verbose "$($LPP4)`t`tName:`t$CGFullName"
                        $CoreTDGObj = New-ADDADObject -ObjName $CGFullName -ObjParentDN $GlobalDN -ObjType "group"
        
                        if($CoreTDGObj){
                            switch ($CoreTDGObj.State) {
                                {$_ -like "New"} {
                                    Write-Verbose "$($LPP4)`t`tTask Outcome:`tSuccess"
                                    Write-Verbose ""
                                    $TDGsCreated ++
                                }
        
                                {$_ -like "Existing"} {
                                    Write-Verbose "$($LPP4)`t`tTask Outcome:`tAlready Exists"
                                    Write-Verbose ""
                                }
        
                                Default {
                                    Write-Verbose "$($LPP4)`t`tOutcome:`tFailed"
                                    Write-Verbose "$($LPP4)`t`tFail Reason:`t$($CoreTDGObj.State)"
                                }
                            }
                        }else {
                            Write-Verbose "$($LPP4)`t`tOutcome:`tFailed"
                            Write-Verbose "$($LPP4)`t`tFail Reason:`tUnknown - No Lvl 3 Object Returned"
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
            }
        }

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
    } #End Process block

    end {
        Write-Verbose "$($LP)`t`tWriting Root ACLs to domain"
        if(!($MTRun)){
            Write-Progress -Id 15 -Activity "Deploy Core Components" -CurrentOperation "Setting Root and RecycleBin ACLs" -ParentId 10
        }
        if($pscmdlet.ShouldProcess("Set root ACLs","$DomDN")){
            $RootDomDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomDN")
            $PartitionDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Partitions,CN=Configuration,$DomDN")
            $OptionalFeatures = $PartitionDE."msDS-EnabledFeature"
        }

        $InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]'All'
        $AdminGroupObj = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Administrators,CN=Builtin,$DomDN")
        $DelegateSID = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $AdminGroupObj.objectSid.Value, 0
        $AdminGrpACEDef = $DelegateSID,'GenericAll','Allow',$allGuid,$InheritanceType

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
                    Write-Verbose "$($LPB2)`t`tOutcome:`tSuccess"
                }
                catch {
                    Write-Verbose "$($LPB2)`t`tOutcome:`tFail"
                }
            }else {
                Write-Verbose "$($LPB2)`t`t+++ WhatIf Detected - Would write FullControl ACE for BUILTIN\Administrators to domain root +++"
            }

            if($pscmdlet.ShouldProcess("Recycle Bin","Set RB ACE")){
                #TODO: Check options for enable optional feature
                if($OptionalFeatures -like "*Recycle Bin Feature*"){
                    Write-Verbose "$($LPB1)`t`tRecycle Bin Status:`tEnabled"
                    $DelObjDE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=Recycle Bin Feature,CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,$DomDN")
                    Write-Verbose "$($LPB2)`t`tApplying ACEs to $($DelObjDE.DistinguishedName)"
                    try {
                        $DelObjDE.psbase.ObjectSecurity.AddAccessRule($aceObj)
                        $DelObjDE.psbase.CommitChanges()
                        Write-Verbose "$($LPB2)`t`tOutcome:`tSuccess"
                    }
                    catch {
                        Write-Verbose "$($LPB2)`t`tOutcome:`tFail"
                    }
                }else {
                    Write-Verbose "$($LPB1)`t`tRecycle Bin Status:`tDisabled"
                }
            }else {
                Write-Verbose "$($LPB1)`t`t+++ WhatIf Detected - Would write FullControl ACE for BUILTIN\Administrators to domain Recycle Bin (if enabled) +++"
            } #End If/Esle ShouldProcess - Recycle Bin
            
            #Update AdminSDHolder default SACLs
            $SDHolder = New-Object System.DirectoryServices.DirectoryEntry("LDAP://CN=AdminSDHolder,CN=System,$DomDN")
            foreach($sacl in $EveryoneSACLs){
                $SDHolder.psbase.ObjectSecurity.AddAuditRule($sacl)
            }

            #TODO: Address users/comps redirection
            if($NoRedir){
                Write-Verbose "$($LPB1)`t`tRedirection of Default Users/Computers Skipped"
            } else {
                $RedirPath = "OU=Provisioning,OU=$($FocusHash['Stage']),OU=Tier-2,$DomDN"
                $WellKnownObjects = Get-ADObject -Identity $DomDN -Properties wellKnownObjects | Select-Object -ExpandProperty wellKnownObjects

                $CompWKO = $WellKnownObjects | Where-Object {$_ -like "*CN=Computers,*"}
                Write-Verbose "$($LPB1)`t`tCurrent Computer OU:`t$CompWKO"
                
                $UserWKO = $WellKnownObjects | Where-Object {$_ -like "*CN=Computers,*"}
                Write-Verbose "$($LPB1)`t`tCurrent User OU:`t$UserWKO"

                $NewCompWKO = $CompWKO -replace ($CompWKO.Split(':')[-1]),$RedirPath
                Write-Verbose "$($LPB1)`t`tNew Computer OU:`t$NewCompWKO"

                $NewUserWKO = $UserWKO -replace ($UserWKO.split(':')[-1]),$RedirPath
                Write-Verbose "$($LPB1)`t`tNew User OU:`t$NewUserWKO"

                Write-Verbose "$($LPB2)`t`tAttempting to update default computers location"
                try {
                    Set-ADObject -Identity $DomDN -Add @{wellKnownObjects = $NewCompWKO} -Remove @{wellKnownObjects = $CompWKO}
                    Write-Verbose "$($LPB2)`t`tUpdate Default Computers:`tSuccess"
                }
                catch {
                    Write-Verbose "$($LPB2)`t`tUpdate Default Computers:`tFailed"
                    Write-Warning "Updating the default computers OU failed - Run 'redircmp.exe' manually"
                }

                Write-Verbose "$($LPB2)`t`tAttempting to update default users location"
                try {
                    Set-ADObject -Identity $DomDN -Add @{wellKnownObjects = $NewUserWKO} -Remove @{wellKnownObjects = $UserWKO}
                    Write-Verbose "$($LPB2)`t`tUpdate Default Users:`tSuccess"
                }
                catch {
                    Write-Verbose "$($LPB2)`t`tUpdate Default Users:`tFailed"
                    Write-Warning "Updating the default users OU failed - Run 'redirusr.exe' manually"
                }
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
        } #End If MTRun

        Write-Verbose "$($LP)`t`t------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
        Write-Verbose ""

    } #End End block
}