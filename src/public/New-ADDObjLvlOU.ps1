function New-ADDObjLvlOU {
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
            Help Last Updated: 08/07/2019

            Cmdlet Version: 0.1
            Cmdlet Status: (Alpha/Beta/Release-Functional/Release-FeatureComplete)

            Copyright (c) Topher Whitfield All rights reserved.

            Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
            source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
            own risk, and the author assumes no liability.

        .LINK
            https://mer-bach.org
    #>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
    param (
		[Parameter(ParameterSetName="ManualRunA")]
		[Parameter(ParameterSetName="ManualRunB")]
        [ValidateSet("TDG","OBJ","ALL")]
        [string]$CreateLevel,

        [Parameter(ParameterSetName="ManualRunA",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string[]]$StartOU,

        [Parameter(ParameterSetName="ManualRun")]
        [Parameter(ParameterSetName="ChainRun")]
        [int]$PipelineCount,

		[Parameter(ParameterSetName="ChainRun")]
		[int]$ProgParentId,

        [Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.DirectoryServices.DirectoryEntry]$TargetDE,

        [Parameter(DontShow,ParameterSetName="ChainRun")]
        [Switch]$MTRun
    )

    begin {
        #TODO: New-ADDObjLvlOU: Fix input elements to allow manual run more readily
        #TODO: Ensure propper support is added for returning values in 'WhatIf' scenarios
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        if($pscmdlet.ParameterSetName -like "ManualRun*"){
            switch ($CreateLevel) {
                "TDG" {$CreateVal = 2}
                "OBJ" {$CreateVal = 1}
                Default {$CreateVal = 3}
            }
        }else {
            $ChainRun = $true
        }

		# Detect if input is coming from pipeline or not, and set values for fast detect later
		if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
			Write-Verbose "Pipeline:`tDetected"
			if($MTRun){
				$Pipe = $false
			}else {
				$Pipe = $true
                Write-Progress -Id 15 -Activity 'Creating Object Type/SubType OUs' -CurrentOperation "Initializing..." -ParentId 10
			}

			if($PipelineCount -gt 0){
				$TotalItems = $PipelineCount
			}
		}

        $FinalObjOUObjs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

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
        Write-Verbose "`t`t****************** Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

		# Enforced .NET garbage collection to ensure memory utilization does not balloon
		if($GCloopCount -eq 30){
			Run-MemClean
			$GCloopCount = 0
		}

        #region DetectInputType
		# Start process run by detecting the input object type
        Write-Verbose "`t`tDetect input type details"
        Write-Verbose ""
		if($Pipe){
			Write-Verbose "`t`t`tInput Type:`tPipeline"
			$TargetItem = $_
		}elseif($TargetOU) {
			Write-Verbose "`t`t`tInput Type:`tTargetOU (single item)"
			$TargetItem = $TargetOU
		}else {
			Write-Verbose "`t`t`tInput Type:`tStartOU (single item)"
			$TargetItem = $StartOU
		}

		Write-Verbose ""
        try {
            $TargetType = ($TargetItem.GetType()).name
            Write-Verbose "`t`t`tTarget Value:`t$TargetItem"
            Write-Verbose "`t`t`tTarget Type:`t$TargetType"
        }
        catch {
            Write-Error "Unable to determine target type from value provided - Quitting" -ErrorAction Stop
        }

		# Use the input object type to determine how to create a reference DirectoryEntry object for the input OU path
		switch ($TargetType){
			"DirectoryEntry" {
                $DEPath = $TargetItem.Path
			}

			"ADOrganizationalUnit" {
				$DEPath = "LDAP://$($TargetItem.DistinguishedName)"
			}

			Default {
				if($TargetItem -like "LDAP://*"){
                    $DEPath = $TargetItem
				}else{
					if($TargetItem -match $OUdnRegEx){
						$DEPath = "LDAP://$TargetItem"
					}else{
						Write-Error "The specified object ($TargetItem) is not in distinguishedName format - Skipping" -ErrorAction Continue
						$FailedCount ++
						break
					}
				}
			}
		}

        Write-Verbose "`t`t`tDEPath:`t$DEPath"

        if([adsi]::Exists($DEPath)) {
            $TargetDEObj = New-Object System.DirectoryServices.DirectoryEntry($DEPath)
            $TargetOUDN = $TargetDEObj.DistinguishedName
            Write-Verbose "$($LPP3)DE Binding:`tSuccess"
        }else {
            Write-Error "The specified OU ($TargetItem) wasn't found in the domain - Skipping" -ErrorAction Continue
            $FailedCount ++
            break
        }
        #endregion DetectInputType

        $DNFocusID = ($TargetOUDN | Select-String -Pattern $($FocusDNRegEx -join "|")).Matches.Value
        if($DNFocusID){
            $FocusID = ($DNFocusID -split "=")[1]
            Write-Verbose "$($LPP3)`t`tDerived FocusID:`t$FocusID"

            if($FocusID -match $FocusHash["Server"]){
                if($pscmdlet.ParameterSetName -like "ManualRun"){
                    Write-Warning "`t`tObject OUs are not created in the Server focus - Skipping"
                }else{
                    Write-Verbose "`t`tServer Focus - Skipping"
                }

                break
            }
        }


        if($ProcessedCount -gt 1){
            $PercentComplete = ($ProcessedCount / $PipelineCount) * 100
        }else{
            $PercentComplete = 0
        }

        if($Pipe){
            Write-Progress -Id 15 -Activity "Creating OUs" -CurrentOperation "Deploying Object level OUs..." -PercentComplete $PercentComplete -ParentId 10
        }

        $OUObjTypeOUs = $ObjInfo | Where-Object{$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -ne $null} | Select-Object OBJ_TypeOU -Unique

        if($OUObjTypeOUs){
            foreach($ObjTypeOU in $OUObjTypeOUs){
                $ObjTypeName = $ObjTypeOU.OBJ_TypeOU
                Write-Verbose "`t`t`t`tProcessing Obj Type"
                Write-Verbose "`t`t`t`t`tName:`t$($ObjTypeName)"

                if($pscmdlet.ShouldProcess($ObjTypeName, "Creating Object Type OU")){
                    $ObjOUObj = New-ADDADObject -ObjName $ObjTypeName -ObjParentDN $TargetDEObj.distinguishedName
                }else {
                    Write-Verbose ""
                    Write-Verbose "`t`t`t`t+++ WhatIf Detected - Would create OU ($ObjTypeName) in path $($TargetDEObj.distinguishedname) +++"
                    Write-Verbose ""
                    $NewCount ++
                }

                if($ObjOUObj){
                    switch ($ObjOUObj.State) {
                        {$_ -match "New"} {
                            Write-Verbose "`t`t`t`t`tOutcome:`tSuccess"
                            Write-Verbose ""
                            $FinalObjOUObjs.Add($ObjOUObj.DEObj)
                            $NewCount ++
                        }

                        {$_ -like "Existing"} {
                            Write-Verbose "`t`t`t`t`tOutcome:`tSuccess"
                            Write-Verbose ""
                            $FinalObjOUObjs.Add($ObjOUObj.DEObj)
                            $ExistingCount ++
                        }

                        Default {
                            $FailedCount ++
                            Write-Verbose "`t`t`t`tOutcome:`tFailed"
                            Write-Verbose "`t`t`t`tFail Reason:`t$($Org2Obj.State)"
                        }
                    }

                    $ObjSubTypeOUs = $ObjInfo | Where-Object{$_.OBJ_TypeOU -like $ObjTypeName -and $_.OBJ_SubTypeOU -ne $null -and $_.OBJ_relatedfocus -like $FocusID}

                    Write-Verbose "`t`t`t`t`tProcessing Obj Sub-Types"
                    if($ObjSubTypeOUs){
                        foreach($SubOU in $ObjSubTypeOUs){
                            $ObjSubTypeName = $SubOU.OBJ_SubTypeOU
                            Write-Verbose "`t`t`t`tProcessing SubObj Type"
                            Write-Verbose "`t`t`t`t`tName:`t$($ObjSubTypeName)"

                            if($pscmdlet.ShouldProcess($ObjSubTypeName, "Creating Object SubType OU")){
                                $SubObjOUObj = New-ADDADObject -ObjName $ObjSubTypeName -ObjParentDN $ObjOUObj.DEObj.distinguishedname
                            }else {
                                Write-Verbose ""
                                Write-Verbose "`t`t`t`t+++ WhatIf Detected - Would create OU ($ObjSubTypeName) in path $($ObjOUObj.distinguishedname) +++"
                                Write-Verbose ""
                                $NewCount ++
                            }

                            if($SubObjOUObj){
                                switch ($ObjOUObj.State) {
                                    {$_ -match "New"} {
                                        Write-Verbose "`t`t`t`t`tOutcome:`tSuccess"
                                        Write-Verbose ""
                                        $NewCount ++
                                    }

                                    {$_ -like "Existing"} {
                                        Write-Verbose "`t`t`t`t`tOutcome:`tSuccess"
                                        Write-Verbose ""
                                        $ExistingCount ++
                                    }

                                    Default {
                                        $FailedCount ++
                                        Write-Verbose "`t`t`t`tOutcome:`tFailed"
                                        Write-Verbose "`t`t`t`tFail Reason:`t$($Org2Obj.State)"
                                    }
                                }

                            }
                        }
                    }else {
                        Write-Verbose "`t`t`t`tNo Sub-Types Detected"
                    }
                }else {
                    Write-Verbose "`t`t`t`tOutcome:`tFailed - No OU object created"
                }
            }
        }else {
            Write-Verbose "`t`t`t`tNo Types Detected"
        }

        $ProcessedCount ++
        $loopCount ++
        $GCloopCount ++
        $loopTimer.Stop()
        $loopTime = $loopTimer.Elapsed.TotalSeconds
        $loopTimes += $loopTime
        Write-Verbose "`t`tLoop $($ProcessedCount) Time (sec):`t$loopTime"

        if($loopTimes.Count -gt 2){
            $loopAverage = [math]::Round(($loopTimes | Measure-Object -Average).Average, 3)
            $loopTotalTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 3)
            Write-Verbose "`t`tAverage Loop Time (sec):`t$loopAverage"
            Write-Verbose "`t`tTotal Elapsed Time (sec):`t$loopTotalTime"
        }
        $loopTimer.Reset()

        Write-Verbose ""
        Write-Verbose "`t`t****************** End of loop ($loopCount) ******************"
        Write-Verbose ""
    }

    end {
        $TotalOrgProcessed = $Lvl1ProcessedCount + $Lvl2ProcessedCount + $Lvl3ProcessedCount
        Write-Verbose ""
        Write-Verbose "Wrapping Up"
        Write-Verbose "`t`tSource Paths Procesed:`t$ProcessedCount"
        Write-Verbose "`t`tNew OUs Created:`t$NewCount"
        Write-Verbose "`t`tOUs Staged:`t$($FinalObjOUObjs.Count)"
        Write-Verbose "`t`tPre-Existing OUs:`t$ExistingCount"
        Write-Verbose "`t`tFailed OUs:`t$FailedCount"
        Write-Verbose ""
        Write-Verbose ""

        if($Pipe){
            Write-Progress -Id 15 -Activity "Creating OUs" -CurrentOperation "Finished" -Completed -ParentId 10
        }

        if($CreateVal -gt 1) {
            Write-Verbose "$($LPB1)Manual Run and CreateVal greater than 1 - Passing results to New-ADDOrgLvlOU"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            $FinalObjOUObjs | New-ADDTaskGroup -PipelineCount $($FinalFocusLevelOUs.Count)
        }else {
            Write-Verbose "$($LPB1)Chain Run or CreateVal of 1 - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            return $FinalbjgOUObjs
        }
    }
}