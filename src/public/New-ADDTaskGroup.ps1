function New-ADDTaskGroup {
<#
	.SYNOPSIS
		Command uses the specified OU path to auto-generate all task groups for a given object type.

	.DESCRIPTION
		This cmdlet takes a specified OU, in distinguishedName format, to identify all required task delegation groups for that tier,
		region, country, and site. The cmdlet then creates all of these groups within the correct location in the ADM focus container
		structure. If specified, the cmdlet will also automatically assign the related ACLs for	each delegation group will also be deployed.

		Note: An existing organization structure should already be deployed prior to running this cmdlet

	.PARAMETER CreateLevel
		Specifies which levels of groups should be created using one of the below values:

			- Site: Creates only the site level groups - useful for site specific task groups, particularly those with custom suffix
			- Region: Creates only the region level groups - useful for region specific task groups, particularly those with custom suffix
			- All: Creates both Site and Region groups - default value if this parameter is not specified

	.PARAMETER SetPerms
		Specifying this switch will initiate a push of the ACLs to the associated containers (Experimental).

		Note: Only groups with one of the standard suffixes should include this switch to avoid errors.

	.PARAMETER TargetOU
		Specifies an OU, in DistinguishedName format, from which to determine the required task groups to create. Sample OU should specify
		down to the same level that is being created (site level for Site/All, or Region level for Region only)

	.PARAMETER OUFocus
		Used to specify the OU focus for targeting. For standard suffixes, this should be either ADM, SRV, STD, STG, or you can specify
		ALL to generate all four. Custom values are also accepted, but should be no more than three alpha characters. Specified characters
		should ideally be in all upper case, though this is only to ensure consistent formatting for the names.

	.PARAMETER CustomSuffix
		Optional parameter to specify a specific standard task group, or a custom suffix to create task groups for.

	.PARAMETER Push
		Should not be used directly. This parameter is called when executed using the Push-ADDTaskGroup cmdlet.

	.INPUTS
		None

	.OUTPUTS
		When executed via Push-ADDTaskGroup, and thus using the -Push switch, returns a value of False if successful, or True if there are errors

	.EXAMPLE
		C:\PS> New-ADDTaskGroup -CreateLevel Site -TargetOU "OU=TST,OU=TST,OU=NA,OU=Tier-0,DC=test,DC=local"

		This command creates all site level task groups, but no regional ones, for Tier-0, NA region, TST country, and TST site within the
		test.local domain. This command does not apply any ACLs, so the either the Set or Push-ADDOrgAcl cmdlets will need to be called separately.

	.EXAMPLE
		C:\PS> New-ADDTaskGroup -CreateLevel All -TargetOU "OU=TST,OU=TST,OU=NA,DC=test,DC=local" -SetPerms

		Similar to the first example, but this command also creates the regional task groups and applies the associated ACLs, provided only the
		standard suffixes are being used.

	.EXAMPLE
		C:\PS> New-ADDTaskGroup -CreateLevel Region -TargetOU "OU=NA,DC=test,DC=local" -SetPerms

		This command creates only the region level task groups, but no site groups, and then applies the associated ACLs.

	.EXAMPLE
		C:\PS> New-ADDTaskGroup -TargetOU "OU=TST,OU=TST,OU=NA,DC=test,DC=local" -OUFocus "NET" -CustomSuffix "Test_TaskGroup"

		This command creates both region and site level groups, but using custom values for the OUFocus and suffix values. The specified focus
		does not need to exist within the OU structure, since no ACLs are being set. This approach can be used to generate task delegation groups
		for other items outside of those used to manage AD itself, such as a Network device delegation group in this case.

	.NOTES
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
		[ValidateSet("TDG","ALL")]
		[string]$CreateLevel,

		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]$StartOU,

		[Parameter(ParameterSetName="ChainRun")]
		[Switch]$MTRun,

		[Parameter(ParameterSetName="ChainRun")]
		[int]$PipelineCount,

		[Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[System.DirectoryServices.DirectoryEntry]$TargetDE
	)

    begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""
		Write-Verbose "ParameterSet:`t$($pscmdlet.ParameterSetName)"
        #TODO: Update WhatIf processing support to match New-ADDTopLvlOU cmdlet
		#TODO: Update comment based help

        if($pscmdlet.ParameterSetName -like "ManualRun*"){
            switch ($CreateLevel) {
				# Create TDGs only
				"TDG" {$CreateVal = 1}
				# Create TDGs and call Grant-ADDTDGRights
                Default {$CreateVal = 2}
            }
        }else {
            $ChainRun = $true
        }

		# Detect if input is coming from pipeline or not, and set values for fast detect later
		if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
			Write-Verbose "Pipeline:`tDetected"
			$Pipe = $true

			# Set ID value to be used in Write-Progress later if required
			if($MTRun){
				$ProgParams = @{
					Id = 25
					ParentId = 20
				}
			}else {
				$ProgParams = @{
					Id = 15
					ParentId = 10
				}
			}

			if($PipelineCount -gt 0){
				$TotalItems = $PipelineCount

			}

			Write-Debug "`t`tInitiating Progress Tracking"
			Write-Progress -Activity 'Creating Task Delegation Groups' -CurrentOperation "Initializing..." @ProgParams
		}else{
			Write-Verbose "Pipeline:`tNot Detected"
		}

		# Placeholder for collecting TDGs, either to return to the caller, or to pass to next cmdlet
        $FinalTDGObjs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

		# Establish counters to enable progress tracking
		$AllTDGProcessedCount = 0
		$TDGShouldStageCount = 0
		$TDGStagedCount = 0
        $ProcessedCount = 0
        $FailedCount = 0
        $ExistingCount = 0
        $NewCount = 0
        $GCloopCount = 0
        $loopCount = 1
        $subloopCount = 1

		# Create timer objects to enable tracking of execution time
		#TODO: All: Add switch options to allow this functionality to be turned off - P5
        $loopTimer = [System.Diagnostics.Stopwatch]::new()
		# Placeholder array to collect results of above counter
        $loopTimes = @()

		$subloopTimer = [System.Diagnostics.Stopwatch]::new()

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
            Write-Verbose "`t`t`tOrg OU Target Path:`t$($TargetDEObj.Path)"
        }else {
            Write-Error "The specified OU ($TargetItem) wasn't found in the domain - Skipping" -ErrorAction Continue
            $FailedCount ++
            break
        }
        #endregion DetectInputType

		# Use pipeline value to determine if Progress indicator should be started, as well as determine completion percentage
		if($Pipe){
			if($ProcessedCount -gt 1 -and $TotalItems -gt $ProcessedCount){
				$PercentComplete = ($ProcessedCount / $TotalItems) * 100
			}else{
				$PercentComplete = 0
			}

			Write-Progress -Activity 'Creating Task Delegation Groups' -CurrentOperation "Analyzing $DEPath..." -PercentComplete $PercentComplete @ProgParams
		}

		# Call private convert command to devolve path into components so we can build required group names
		$PIElements = ConvertTo-Elements -SourceValue $($TargetDEObj.DistinguishedName)

		if($PIElements){
			Write-Debug "`t`tPIElements Values - $($PIElements | Out-String)"
		}else{
			Write-Error "ConvertTo-Elements failed to return result - Exiting process" -ErrorAction Continue
			break
		}

		if($PIElements.TierID){
			$TierID = $PIElements.TierID
		}else{
			$DNTierID = ($TargetOUDN | Select-String -Pattern $($CETierDNRegEx -join "|")).Matches.Value
			$FullTierID = ($DNTierID -split "=")[1]
			$TierID = $TierHash[$FullTierID]
		}

		switch ($TierID) {
			"T0" { $TierAssocFilt = @(0,1,4,6) }
			"T1" { $TierAssocFilt = @(0,2,4,5) }
			"T2" { $TierAssocFilt = @(0,3,5,6) }
		}

		Write-Verbose "$($LPP3)`t`tDerived TierID:`t$TierID"
		Write-Debug "`t`tTierAssocFilt:`t$TierAssocFilt"

		$FocusID = $PIElements.FocusID
		Write-Debug "FocusID:`t$FocusID"

		$PStr = Join-String -Strings $TierID,$FocusID -Separator "_"
		Write-Debug "`t`tPStr:`t$PStr"

		# Create an array placeholder to store group name prefixes
		$AllPrefixes = @()

		# Create an array placeholder to store org values for later filtering
		$OrgElements = @()

		switch ($PIElements.MaxLvl) {
			{$_ -ge 1} {
				if($PIElements.OrgL1){
					Write-Debug "`t`tL1 Org:`t$($PIElements.OrgL1)"
					$OrgElements += $PIElements.OrgL1

					$AllPrefixes += [PSCustomObject]@{
						NameElement = Join-String $PStr,($PIElements.OrgL1) -Separator "_"
						Lvl = 1
					}
				}
			}

			{$_ -ge 2} {
				if($PIElements.OrgL2){
					Write-Debug "`t`tL2 Org:`t$($PIElements.OrgL2)"
					$OrgElements += $PIElements.OrgL2
					$AllPrefixes += [PSCustomObject]@{
						NameElement = Join-String $PStr,($PIElements.OrgL1),($PIElements.OrgL2) -Separator "_"
						Lvl = 2
					}
				}else{
					Write-Warning "MaxLevel $MaxLevel or greater - OrgL2 not specified"
				}
			}

			{$_ -eq 3} {
				if($PIElements.OrgL3){
					Write-Debug "`t`tL3 Org:`t$($PIElements.OrgL3)"
					$OrgElements += $PIElements.OrgL3
					$AllPrefixes += [PSCustomObject]@{
						NameElement = Join-String $PStr,($PIElements.OrgL1),($PIElements.OrgL2),($PIElements.OrgL3) -Separator "_"
						Lvl = 3
					}
				}else{
					Write-Warning "MaxLevel $MaxLevel - OrgL3 not specified"
				}
			}
		}

		if($AllPrefixes){
			Write-Verbose "`t`tAllPrefixes Count:`t$($AllPrefixes.Count)"
			Write-Verbose "`t`t`t$($AllPrefixes | Format-Table | Out-String -Stream)"
		}else{
			Write-Error "Failed to identify any prefixes - Skipping OU" -ErrorAction Continue
			break
		}

		if($PIElements.ObjectSubType){
			Write-Debug "`t`tObject SubType Detected - Retrieving Object SubType Data"
			$ParentObjectType = $PIElements.ObjectType
			$ObjectTypes = $ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $($PIElements.ObjectSubType) -and $_.OBJ_ItemType -like "Primary" }
		}else{
			if($PIElements.ObjectType){
				Write-Debug "`t`tObject Type Detected - Retrieving Primary Object Type Data"
				$ObjectTypes = $ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $($PIElements.ObjectType) -and $_.OBJ_ItemType -like "Primary" }
			}else{
				Write-Debug "`t`tNo Object Type or Sub-Type Detected - Retrieving Server Object Type Data"
				$ObjectTypes = $ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_ItemType -like "Primary" }
			}
		}

		# Ensure any misc object types are also captured
		$MiscObjectTypes = $ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_ItemType -like "Primary" -and $_.OBJ_TypeOU -like $null }

		if($MiscObjectTypes){
			$ObjectTypes += $MiscObjectTypes
		}

		if($ObjectTypes){
			Write-Verbose "`t`t Process Applicable ObjectType Types ($($ObjectTypes.Count))"
			Write-Debug "`t`t`t`t$($ObjectTypes | Out-String -Stream)"

			$AllTDGValues = New-Object System.Collections.Generic.List[psobject]

			foreach($ObjType in $ObjectTypes){
				$ObjDBRefID = $ObjType.OBJ_id
				$ObjRefID = $ObjType.OBJ_refid
				$ObjectType = $ObjType.OBJ_TypeOU
				$ObjectDesc = $ObjType.OBJ_category
				Write-Verbose "`t`t`t`tType  DBId   RefId"
				Write-Verbose "`t`t`t`t----- -----  ------"
				Write-Verbose "`t`t`t`t$($ObjectType) $($ObjDBRefID)     $ObjRefID"
				Write-Verbose ""
				Write-Verbose "`t`t`t`t`tAssess Tier Association"
				if($ObjType.OBJ_TierAssoc -in $TierAssocFilt){
					Write-Verbose "`t`t`t`t`t`tOutcome:`tIn Tier - Retrieve Property Groups"
					Write-Verbose ""
					$TDGPropGroups = $AllPropGroups | Where-Object{$_.OBJ_refid -like $ObjDBRefID}

					if($TDGPropGroups){
						Write-Debug "`t`t`t`t`t`t`tPropGroups Returned:`t$($TDGPropGroups.Count)"

						foreach($TDGPropGroup in $TDGPropGroups){
							Write-Verbose "`t`t`t`t`tDerive Primary TDG Values"
							$TDGMid = Join-String $ObjRefID,($TDGPropGroup.OBJ_Scope),($TDGPropGroup.OBJ_rights) -Separator "_"
							Write-Verbose "`t`t`t`t`t`tTDGMid:`t$TDGMid"
							$TDGSuffix = $TDGPropGroup.OBJ_name
							Write-Verbose "`t`t`t`t`t`tTDGSuffix:`t$TDGSuffix"

							$TDGFullSuffix = Join-String -Strings $TDGMid,$TDGSuffix -Separator "-"
							Write-Verbose "`t`t`t`t`t`tFull Suffix:`t$TDGFullSuffix"

							if($($TDGPropGroup.OBJ_assignAcls) -eq 0){
								$GrantAcl = $false
							}else{
								$GrantAcl = $true
							}
							Write-Verbose "`t`t`t`t`t`tHas ACLs:`t$GrantACL"
							Write-Verbose ""

							foreach($Prefix in $AllPrefixes){

								$PrefixName = $Prefix.NameElement
								Write-Verbose "`t`t`t`t`tProcess Prefix:`t$PrefixName"
								$TDGValue = Join-String -Strings $PrefixName,$TDGFullSuffix -Separator "-"
								Write-Verbose "`t`t`t`t`t`tFull Name:`t$TDGValue"

								[string]$Destination = $TargetDEObj.DistinguishedName
								Write-Verbose "`t`t`t`t`t`tOrig TargetDN:`t$Destination"

								if($Prefix.Lvl -eq $MaxLevel){
									$DestinationDN = $Destination -replace $FocusID,$FocusHash["Admin"]
									Write-Verbose "`t`t`t`t`t`tAdmin TargetDN:`t$DestinationDN"
								}else{
									$DestinationDN = ($Destination -replace (Join-String -Strings $OrgElements -Separator "|"),$OUGlobal) -replace $FocusID,$FocusHash["Admin"]
									Write-Verbose "`t`t`t`t`t`tGBL Admin TargetDN:`t$DestinationDN"
								}

								if($DestinationDN -notmatch "^$($DestHash[$TDGPropGroup.OBJ_destination]),*"){
									if($FocusID -match $FocusHash["Server"]){
										$DestinationDN = Join-String $DestHash[$TDGPropGroup.OBJ_destination],$DestinationDN -Separator ","
									}else{
										$DestinationDN = $DestinationDN -replace "OU=$ObjectType","$($DestHash[$TDGPropGroup.OBJ_destination])"
									}
								}

								Write-Verbose "`t`t`t`t`t`tFinal DestinationDN:`t$DestinationDN"
								$TDGElements = [PSCustomObject]@{
									TDGName = $TDGValue
									TDGSetAcl = $GrantAcl
									TDGDestination = $DestinationDN
									TDGRelSuffix = $TDGSuffix
								}

								$AllTDGValues.Add($TDGElements)

							}
						}

					}else{
						Write-Debug "`t`t`t`t`t`t`tPropGroups Returned:`t0"
						Write-Warning "`t`tFailed to retrieve related property groups with specified DB ID - $ObjDBRefID - Skipping $ObjectDesc"
						break
					}
				}else {
					Write-Verbose "`t`t`t`t`t`tOutcome:`tNot in Tier - Skipping"
				}

			}

		}else{
			Write-Warning "`t`tObjectType Data Retrieval: Failed - Skipping $TargetItem"
			break
		}

		Write-Verbose ""
		if($AllTDGValues){
			if($Pipe){
				Write-Progress -Activity 'Creating Task Delegation Groups' -CurrentOperation "Deploying TDGs for $DEPath..." -PercentComplete $PercentComplete @ProgParams

				$TotalTDGItems = $($AllTDGValues.Count)
				Write-Verbose "`t`t`t`tTDGs Staged:`t$TotslTDGItems"
				$AllTDGProcessedCount = 0
				$TDGProcessedCount = 0
			}

			foreach($TDGItem in $AllTDGValues){
				if($Pipe){
					if($TDGProcessedCount -gt 1 -and $TotalTDGItems -gt $TDGProcessedCount){
						$TDGPercentComplete = ($TDGProcessedCount / $TotalTDGItems) * 100
					}else{
						$TDGPercentComplete = 0
					}

					Write-Progress -Id $($ProgParams.Id + 5) -Activity 'Processing' -CurrentOperation "$($TDGItem.TDGRelSuffix)" -PercentComplete $PercentComplete -ParentId $ProgParams.Id
				}

				$TDGName = $TDGItem.TDGName
				$TDGDestination = $TDGItem.TDGDestination
				$DestType = ($TDGDestination.GetType()).Name
				Write-Verbose "`t`t`t`tDest Obj Type:$DestType"

				if ($pscmdlet.ShouldProcess($($TDGName), "Create AD Group")) {
					Write-Verbose "`t`t`t`tCalling New-ADDADObject"
					Write-Verbose "`t`t`t`t`tName:`t$TDGName"
					Write-Verbose "`t`t`t`t`tDestination:`t$TDGDestination"
					$TDGObj = New-ADDADObject -ObjName $TDGName -ObjParentDN $TDGDestination -ObjType "group"

					if($TDGObj){
						switch ($TDGObj.State) {
							{$_ -like "New"} {
								Write-Verbose "`t`t`t`t`tTask Outcome:`tSuccess"
								Write-Verbose ""
								if($TDGItem.TDGSetAcl){
									Write-Verbose "`t`t`t`t`tGrantAcl:`t$true - Add to output"
									$FinalTDGObjs.Add($TDGObj.DEObj)
								}else{
									Write-Verbose "`t`t`t`t`tGrantAcl:`t$false"
								}
							}

							{$_ -like "Existing"} {
								Write-Verbose "`t`t`t`t`tTask Outcome:`tAlready Exists"
								Write-Verbose ""
								if($TDGItem.TDGSetAcl){
									Write-Verbose "`t`t`t`t`tGrantAcl:`t$true - Add to output"
									$FinalTDGObjs.Add($TDGObj.DEObj)
								}else{
									Write-Verbose "`t`t`t`t`tGrantAcl:`t$false"
								}
							}

							Default {
								Write-Verbose "`t`t`t`t`tOutcome:`tFailed"
								Write-Verbose "`t`t`t`t`tFail Reason:`t$($TDGResults.State)"
							}
						}
					}
				}else{
					Write-Verbose "`t`t`t`tWhatIf Detected - Would call New-ADDADObject with following details"
					Write-Verbose "`t`t`t`t`tName:`t$TDGName"
					Write-Verbose "`t`t`t`t`tDestination:`t$TDGDestination"
				}

				$TDGProcessedCount ++

			}

			if($Pipe){
				Write-Progress -Id $($WriteProgParams.Id + 5) -Activity 'Processing' -Completed -ParentId $WriteProgParams.Id
			}

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
		Write-Verbose ""
		Write-Verbose ""
		Write-Verbose "Wrapping Up"
		Write-Verbose "`t`tOU paths procesed:`t$ProcessedCount"
		Write-Verbose "`t`tNew TDGs Created:`t$NewCount"
		Write-Verbose "`t`tPre-Existing TDGs:`t$ExistingCount"
		Write-Verbose "`t`tFailed TDGs:`t$FailedCount"
		Write-Verbose "`t`tStaged TDGs:`t$($FinalTDGObjs.count)"
		Write-Verbose ""
		Write-Verbose ""

		if($Pipe){
			Write-Progress -Activity "Creating OUs" -CurrentOperation "Finished" -Completed @WriteProgParams
		}


		if($FinalTDGObjs){
			if($CreateVal -gt 1) {
				Write-Verbose "`t`tManual Chain Execution Detected - Passing staged TDGs to Grant-ADDTDGRights"
				Write-Verbose "------------------- $($FunctionName): End -------------------"
				Write-Verbose ""
				Write-Verbose ""

				if ($pscmdlet.ShouldProcess("Process $($FinalTDGObjs.Count) TDGs", "Setting ACLs")) {
					$FinalTDGObjs | Grant-ADDTDGRights -PipelineCount $($FinalTDGObjs.Count)
				}else{
					Write-Verbose "`t`tWhatIf Detected - Would pass $($FinalTDGObjs.Count) TDG results to Grant-ADDTDGRights"
				}
			}else {
				Write-Verbose "`t`tChained ADDExecuteAll Detected - Returning staged TDGs to pipeline"
				Write-Verbose "------------------- $($FunctionName): End -------------------"
				Write-Verbose ""
				Write-Verbose ""

				return $FinalTDGObjs
			}
		}
    }
}
