function New-ADDTopLvlOU {
<#
    .SYNOPSIS
        Deploys the Tier and Focus levels of the ESAE OU structure, with the ability to deploy sub-components using chained execution.

    .DESCRIPTION
        This cmdlet uses information from the embedded sqlite database to generate the top level Tier containers, as well as the Focus level containers for a
        new ESAE OU structure to a target domain. This cmdlet is capable of chaining execution to subsequent deployment steps automatically to complete one or
        more steps in a linear manner. Particularly for deployment of large environments, meaning those with many level 1 containers and/or a highly granular
        delegation model, are encouraged to use the Publish-ADDESAEStructure instead, as this will automatically enable multi-threaded execution where appropriate.

	.PARAMETER CreateLevel
        Used to indicate if the entire structure should be deployed, or only up to a specific point. Acceptable values for this parameter are as follows:

            TOP - Deploys only the Tier and Focus OU levels
            ORG - Deploys only the Tier, Focus, and Organizatinal (all) OU levels
            OBJ - Deploys all OU levels, but does not deploy Task Delegation Groups or ACLs
            TDG - Deploys all OU levels and Task Delegation Groups, but does not configure related ACLs
            ALL - Deploys all elements of the structure except placeholder Group Policy Objects (Default)

        If this parameter is not specified, or a value is not provided, the ALL option will be used by default. This parameter only applies when this cmdlet
        is directly invoked. If this cmdlet is invoked via Publish-ADDESAEStructure instead, each element is individually executed for operational efficiency.

	.PARAMETER StartOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path, instead of at the root of
        the domain. You must provide the value as a string in distinguishedName format (ex. "OU=OUname,DC=MYDOMAIN,DC=NET").

        SPECIAL NOTE: Using this option may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups with the appropriate names as this option
        is still experimental.

    .PARAMETER ChainRun
        This switch causes objects required for the next stage of execution to be returned to the pipeline for additional scrutinty or action. This switch is
        only intended to be called by internal actions, such as when this cmdlet is invoked by the Publish-ADDESAEStructure cmdlet, or another upstreams cmdlet
        during chained execution.

    .EXAMPLE
        PS C:\> $TopOUs = New-ADDTopLvlOU

        Deploys only the Tier and Focus level containers to the root of the domain to which the machine running the cmdlet is joined, then returns and array of
        DirectoryEntry objects representing the Focus level containers to the pipeline, with the results stored in the $TopOUs variable.

    .EXAMPLE
        PS C:\> New-ADDTopLvlOU -CreateLevel All

        Deploys all aspects of the model in a linear fashion, with nothing returned to the pipeline. The process will provide a progress indicator during active
        deployment, but nothing else.

    .INPUTS
        System.String

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

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
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
    param (
        [Parameter(ParameterSetName="ManualRun")]
        [ValidateSet("TOP","TDG","OBJ","ORG","ALL")]
        [string]$CreateLevel,

        [Parameter(ParameterSetName="ManualRun")]
        [Parameter(ParameterSetName="ChainRun")]
        [string]$StartOU,

        [Parameter(ParameterSetName="ChainRun")]
        [Switch]$ChainRun
    )

    begin {
        #TODO: Augment to enable alternate domain - may already be addressed via DomDN, but make sure it works with alt target
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        Write-Verbose "$($LPB1)Run Type:`t$($pscmdlet.ParameterSetName)"
        Write-Verbose "$($LPB1)Setting supplemental run values..."

        if($pscmdlet.ParameterSetName -like "ManualRun"){
            switch ($CreateLevel) {
                "ALL" {$CreateVal = 5}
                "TDG" {$CreateVal = 4}
                "OBJ" {$CreateVal = 3}
                "ORG" {$CreateVal = 2}
                Default {$CreateVal = 1}
            }

            Write-Verbose "$($LPB2)CreateVal:`t$CreateVal"
        }

        $OUTop = $CoreOUs | Where-Object{$_.OU_type -like "Tier"}
        Write-Verbose "$($LPB2)Top Level OUs:`t$($OUTop.Count)"
        $OUFocus = $CoreOUs | Where-Object{$_.OU_type -like "Focus"}
        Write-Verbose "$($LPB2)Focus Level OUs:`t$($OUFocus.Count)"

        if($StartOU){
            Write-Verbose "$($LPB2)Target Type:`tStartOU"
            Write-Verbose "$($LPB2)`tValue:`t$StartOU"
            if($StartOU -match $OUdnRegEx){
                Write-Verbose "$($LPB2)`tIs DistinguisheName:`t$true"
                if($([adsi]::Exists("LDAP://$StartOU"))){
                    Write-Verbose "$($LPB2)`tPath Exists:`t$true"
                    $TopNameDestDN = $StartOU
                }else {
                    Write-Verbose "$($LPB2)`tPath Exists:`t$false"
                    Write-Error "$($LPB2)`tThe specified StartOU is in DistinguishedName format, but the indicated path does not exist. Please check the path and try again - Quitting" -ErrorAction Stop
                }
            }else {
                Write-Verbose "$($LPB2)`tIs DistinguisheName:`t$false"
                $StartOULDAP = "LDAP://OU=$StartOU,$DomDN"
                Write-Verbose "$($LPB2)`tTest Path:`t$StartOULDAP"
                if($([adsi]::Exists("$StartOULDAP"))){
                    Write-Verbose "$($LPB2)`tPath Exists:`t$true"
                    $TopNameDestDN = $StartOULDAP
                }else {
                    Write-Verbose "$($LPB2)`tPath Exists:`t$false"
                    Write-Error "$($LPB2)`tThe specified StartOU does not exist in the root of the domain. Please check the path and try again - Quitting" -ErrorAction Stop
                }
            }
        }else {
            Write-Verbose "$($LPB2)Target Type:`tDefault"
            Write-Verbose "$($LPB2)`tValue:`t$DomDN"
            $TopNameDestDN = $DomDN
        }

        $TopLevelOUs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $FocusLevelOUs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $WFTopLevelOUs = New-Object System.Collections.Generic.List[psobject]
        $WFFocusLevelOUs = New-Object System.Collections.Generic.List[psobject]

        $ProcessedCount = 0
		$FailedCount = 0
		$ExistingCount = 0
		$NewCount = 0
		$GCloopCount = 1
		$loopCount = 1
		$subloopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
		$subloopTimer = [System.Diagnostics.Stopwatch]::new()
		$loopTimes = @()

		Write-Verbose ""
    }

    process {
		Write-Verbose ""
		Write-Verbose "$($LPP1)****************** Start of loop ($loopCount) ******************"
		Write-Verbose ""
		$loopTimer.Start()

		# Enforced .NET garbage collection to ensure memory utilization does not balloon
		if($GCloopCount -eq 30){
			Run-MemClean
			$GCloopCount = 0
		}

        #region CreateTopLevelOUs
        Write-Verbose "$($LPP2)Creating Tier level OU"
        foreach($OU in $OUTop){
            $TopName = $($OU.OU_name)
            Write-Verbose "$($LPP3)Name:`t$TopName"

            Write-Verbose "$($LPP3)DestinationDN:`t$TopNameDestDN"
            $TopNameFullDN = "OU=$TopName,$TopNameDestDN"

            if($pscmdlet.ShouldProcess($TopName, "Creating Tier Lvl OU")){
                $TopOUobj = New-ADDADObject -ObjName $TopName -ObjParentDN $TopNameDestDN

                if($TopOUObj){
                    switch ($TopOUObj.State) {
                        {$_ -match "New"} {
                            Write-Verbose "$($LPP3)Outcome:`tSuccess"
                            Write-Verbose ""
                            $TopLevelOUs.Add($TopOUobj.DEObj)
                            $NewCount ++
                        }

                        {$_ -like "Existing"} {
                            Write-Verbose "$($LPP3)Outcome:`tSuccess"
                            Write-Verbose ""
                            $TopLevelOUs.Add($TopOUobj.DEObj)
                            $ExistingCount ++
                        }

                        Default {
                            $FailedCount ++
                            Write-Verbose "$($LPP3)Outcome:`tFailed"
                            Write-Verbose "$($LPP3)Fail Reason:`t$($TopOUObj.State)"
                        }
                    }
                }
            }else{
                Write-Verbose ""
                Write-Verbose "$($LPP3)+++ WhatIf Detected - Would create OU ($TopName) in path $TopNameDestDN +++"
                Write-Verbose ""
                $WFTopLevelOUs.Add($TopNameFullDN)
                $NewCount ++
            }

            $ProcessedCount ++
            Write-Verbose ""
        }
        #endregion CreateTopLevelOUs

        #region CreateFocusLevelOUs
        foreach($OU in $OUFocus){
            Write-Verbose "$($LPP2)Creating Focus level OU"
            $FocusName = $($OU.OU_name)
            Write-Verbose "$($LPP3)Name:`t$FocusName"

            if($pscmdlet.ShouldProcess($FocusName, "Creating Focus Lvl OU")){
                foreach($TopOU in $TopLevelOUs){
                    Write-Verbose "$($LPP3)DestinationDN:`t$($TopOU.distinguishedname)"

                    $FocusOUobj = New-ADDADObject -ObjName $FocusName -ObjParentDN $($TopOU.distinguishedname)

                    if($FocusOUobj){
                        switch ($FocusOUobj.State) {
                            {$_ -match "New"} {
                                Write-Verbose "$($LPP3)Outcome:`tSuccess"
                                Write-Verbose ""
                                $NewCount ++
                            }

                            {$_ -like "Existing"} {
                                Write-Verbose "$($LPP3)Outcome:`tSuccess"
                                Write-Verbose ""
                                $ExistingCount ++
                            }

                            Default {
                                $FailedCount ++
                                Write-Verbose "$($LPP3)Outcome:`tFailed"
                                Write-Verbose "$($LPP3)Fail Reason:`t$($FocusOUobj.State)"
                                break
                            }
                        }

                        if($FocusName -match $FocusHash["Stage"]){
                            Write-Verbose "$($LPP3)Stage Focus Detected:`tCalling New-ADDObjLvlOU"
                            $stageObjTypes = $FocusOUobj.DEObj | New-ADDObjLvlOU -ChainRun
                        }else {
                            Write-Verbose "$($LPP3)Stage Focus Not Detected:`tAdding to Output"
                            Write-Verbose "$($LPP3)`tCurrent Count:`t$($FocusLevelOUs.Count)"
                            $FocusLevelOUs.Add($FocusOUobj.DEObj)
                            Write-Verbose "$($LPP3)`tNew Count:`t$($FocusLevelOUs.Count)"
                        }

                    }else {
                        Write-Verbose "$($LPP3)Outcome:`tFailed"
                        Write-Warning "$($LPP3)Failed to create focus OU - Later deployment steps may fail"
                    }

                }
            }else {
                foreach($TopOU in $WFTopLevelOUs){
                    Write-Verbose "$($LPP3)DestinationDN:`t$TopOU"
                    $FocusNameFullDN = "OU=$FocusName,$TopOU"

                    if($FocusName -match $FocusHash["Stage"]){
                        Write-Verbose "$($LPP3)Stage Focus Detected:`tCalling New-ADDObjLvlOU"
                        $stageObjTypes = $FocusNameFullDN | New-ADDObjLvlOU -ChainRun
                    }else {
                        Write-Verbose "$($LPP3)Stage Focus Not Detected:`tAdding to Output"
                        Write-Verbose "$($LPP4)Current Count:`t$($WFFocusLevelOUs.Count)"
                        $WFFocusLevelOUs.Add($FocusNameFullDN)
                        Write-Verbose "$($LPP4)New Count:`t$($WFFocusLevelOUs.Count)"
                    }

                }
            }

            $ProcessedCount ++
            Write-Verbose ""
        }
        #endregion CreateFocusLevelOUs

        $loopCount ++
        $GCloopCount ++
        $loopTimer.Stop()
        $loopTime = $loopTimer.Elapsed.TotalSeconds
        $loopTimes += $loopTime
        Write-Verbose "$($LPP2)Loop $($ProcessedCount) Time (sec):`t$loopTime"

        if($loopTimes.Count -gt 2){
            $loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
            $loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
            Write-Verbose "$($LPP2)Average Loop Time (sec):`t$loopAverage"
            Write-Verbose "$($LPP3)Total Elapsed Time (sec):`t$loopTotalTime"
        }
        $loopTimer.Reset()

        Write-Verbose ""
        Write-Verbose "$($LPP1)****************** End of loop ($loopCount) ******************"
        Write-Verbose ""
    }

    end {
		Write-Verbose ""
		Write-Verbose "$($LPB1)Wrapping Up"
		Write-Verbose "$($LPB2)Source Values Procesed:`t$ProcessedCount"
		Write-Verbose "$($LPB2)New Items Created:`t$NewCount"
		Write-Verbose "$($LPB2)Pre-Existing Items:`t$ExistingCount"
		Write-Verbose "$($LPB2)Failed Items:`t$FailedCount"
        Write-Verbose ""

        if($WhatIfPreference){
            $FinalFocusLevelOUs = $WFFocusLevelOUs
        }else {
            $FinalFocusLevelOUs = $FocusLevelOUs
        }

        if($CreateVal -gt 1) {
            Write-Verbose "$($LPB1)Manual Run and CreateVal greater than 1 - Passing results to New-ADDOrgLvlOU"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            $FinalFocusLevelOUs | New-ADDOrgLvlOU -PipelineCount $($FinalFocusLevelOUs.Count)
        }else {
            Write-Verbose "$($LPB1)Chain Run or CreateVal of 1 - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            return $FinalFocusLevelOUs
        }
    }
}