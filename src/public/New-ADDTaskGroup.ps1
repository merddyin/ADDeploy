function New-ADDTaskGroup {
<#
	.SYNOPSIS
		Command uses the specified Class or SRV OU path to auto-generate all task groups for a given object type.

	.DESCRIPTION
		This cmdlet takes a specified Class or bottom level SRV OU, in distinguishedName or DirectoryEntry format, and uses it to dynamically
		identify all required task delegation groups for that container and object class. The cmdlet then creates all of the groups within the 
		appropriate ADM focus containers. SL level groups are stored in the designated global container structure, while all other groups are 
		stored in their respective SL Groups containers (OU=Groups,OU=<SL>). If specified, the cmdlet will also automatically pass the resulting
		DirectoryEntry objects to the Grant-ADDTDGRights cmdlet. If not specified, the cmdlet returns the resulting objects to the pipeline.

		Note: An existing ZTAD OU structure must already be deployed prior to running this cmdlet

	.PARAMETER StartOU
		Accepts string inputs with the DistinguishedName of an an object class container, a bottom level SRV container, or the Provision/Deprovion
		staging containers. 

	.PARAMETER MTRun
		Only used when calling this cmdlet from the Publish-ADDZTADStructure -MultiThread command - modifies the behavior of progress

	.PARAMETER PipelineCount
		Used to specity the number of objects being passed in the pipeline, if knownn, to use in showing progress

	.PARAMETER TargetDE
		Accepts one or more DirectoryEntry objects to process

	.PARAMETER Owner
		The sAMAccountName that will be designated as the 'owner' for the TDGs

	.EXAMPLE
		C:\PS> $TDGs = New-ADDTaskGroup -CreateLevel TDG -StartOU "OU=Users,OU=TST,OU=STD,OU=Tier-2,DC=MyDomain,DC=com" -Owner flastname
		C:\PS> $TDGs | Grant-ADDTDGRights
		C:\PS> $TDGs | Select-Object -Property Path | Out-File -FilePath C:\Temp\TDGList.txt

		The first command creates all of the AD Task Delegation Groups (TDGs) related to standard User objects for the TST SL in Tier-2.
		After completion, the resulting DirectoryEntry objects are returned to the pipeline, and are stored in the $TDGs variable.

		The second command passes the $TDGs variable contents to the Grant-ADDTDGRights cmdlet, which will provision the required ACLs associated to each 
		Task Delegation Group for the specified Users OU.

		The final command selects the OU path and outputs the details to a text file.

	.INPUTS
		System.String
		Integer
		System.DirectoryServices.DirectoryEntry

	.OUTPUTS
		System.DirectoryServices.DirectoryEntry

	.NOTES
		Help Last Updated: 11/8/2022

		Cmdlet Version 1.2 - Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
	[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
	param (
		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]$StartOU,

		[Parameter(ParameterSetName="ChainRun")]
		[Switch]$MTRun,

		[Parameter(ParameterSetName="ChainRun")]
		[int]$PipelineCount,

		[Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[System.DirectoryServices.DirectoryEntry]$TargetDE,

		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true)]
		[Parameter(ParameterSetName="ChainRun",Mandatory=$true)]
		[string]$Owner
	)

	begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""
		Write-Verbose "ParameterSet:`t$($pscmdlet.ParameterSetName)"
		#TODO: Update help
		#TODO: Add error handling to ensure groups are not created with 'NoMatch', and to provide feedback to console

		# Detect if input is coming from pipeline or not, and set values for fast detect later
		if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
			Write-Verbose "Pipeline:`tDetected"
			$Pipe = $true

			# Set ID value to be used in Write-Progress later if required
			if($MTRun){
				$ProgParams = @{
					Id = 25
				}
				
				if($PipelineCount){
					$ProgParams.Add("ParentId",20)
				}
			}else {
				$ProgParams = @{
					Id = 15
				}
				
				if($PipelineCount){
					$ProgParams.Add("ParentId",10)
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

		Write-Debug "`t`tAttempting to find owner"
		$OwnerObj = Find-ADDADObject -ADClass user -ADAttribute sAMAccountName -SearchString $Owner
		if($OwnerObj){
			$OwnerDN = $OwnerObj.distinguishedName
		}else{
			Write-Error "The value specified for Owner ($Owner) was not found - Fatal Error" -ErrorAction Stop
		}

		# Hash for splatting info to New-ADDADObject cmdlet
		$TDGHash = @{
			ObjOwner = $OwnerDN
			ObjFocus = "ADM"
			ObjRefType = "TDG"
			ObjDescription = "Task Delegation Group created as part of ZTAD framework"
		}

		# Placeholder for collecting TDGs, either to return to the caller, or to pass to next cmdlet
		$FinalTDGObjs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

		# Establish counters to enable progress tracking
		$ProcessedCount = 0
		$FailedCount = 0
		$ExistingCount = 0
		$NewCount = 0
		$GCloopCount = 0
		$loopCount = 1

		# Create timer objects to enable tracking of execution time
		$loopTimer = [System.Diagnostics.Stopwatch]::new()
		# Placeholder array to collect results of above counter
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
			Invoke-MemClean
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
		$DEPath = $null
		switch ($TargetType){
			"DirectoryEntry" {
				Write-Verbose "`t`t`tDETarget:`t$TargetItem.Path" 

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

		Write-Verbose "$($LPP3)`t`tDerived TierID:`t$TierID"

		switch ($TierID) {
			"T0" { $TierAssocFilt = @(0,1,4,6) }
			"T1" { $TierAssocFilt = @(0,2,4,5) }
			"T2" { $TierAssocFilt = @(0,3,5,6) }
		}

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
				if($PIElements.OrgL1 -or ($FocusID -like $FocusHash["Stage"])){
					Write-Verbose "`t`tL1 Org:`t$($PIElements.OrgL1)"
					$OrgElements += $PIElements.OrgL1

					$AllPrefixes += [PSCustomObject]@{
						NameElement = Join-String $PStr,($PIElements.OrgL1) -Separator "_"
						Lvl = 1
					}
				}
			}

			{$_ -ge 2} {
				if($PIElements.OrgL2 -or ($FocusID -like $FocusHash["Stage"])){
					if($FocusID -like $FocusHash["Stage"]){
						Write-Verbose "`t`tL2 Org:`tSkipped for Staging"
					} else {
						Write-Verbose "`t`tL2 Org:`t$($PIElements.OrgL2)"
						$OrgElements += $PIElements.OrgL2
						$AllPrefixes += [PSCustomObject]@{
							NameElement = Join-String $PStr,($PIElements.OrgL1),($PIElements.OrgL2) -Separator "_"
							Lvl = 2
						}
					}
				}else{
					Write-Warning "MaxLevel $MaxLevel or greater - OrgL2 not specified"
				}
			}

			{$_ -eq 3} {
				if($PIElements.OrgL3 -or ($FocusID -like $FocusHash["Stage"])){
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
			$ObjectTypes = @($ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_SubTypeOU -like $($PIElements.ObjectSubType) -and $_.OBJ_ItemType -like "Primary" })
		}else{
			if($PIElements.ObjectType){
				Write-Debug "`t`tObject Type Detected - Retrieving Primary Object Type Data"
				$ObjectTypes = @($ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_TypeOU -like $($PIElements.ObjectType) -and $_.OBJ_ItemType -like "Primary" })
			}else{
				Write-Debug "`t`tNo Object Type or Sub-Type Detected - Retrieving Server Object Type Data"
				$ObjectTypes = @($ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_ItemType -like "Primary" })
			}
		}

		# Ensure any misc object types are also captured
		$MiscObjectTypes = @($ObjInfo | Where-Object{ $_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_ItemType -like "Primary" -and $_.OBJ_TypeOU -like $null })
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
				$ObjectTierAssoc = [int]$ObjType.OBJ_TierAssoc
				Write-Verbose "`t`t`t`tType        `t`tDBId `t`tRefId `t`tTiers"
				Write-Verbose "`t`t`t`t----        `t`t---- `t`t----- `t`t-----"
				Write-Verbose "`t`t`t`t$($ObjectType) `t`t$($ObjDBRefID)   `t`t$($ObjRefID)      `t`t$($ObjectTierAssoc)"
				Write-Verbose ""
				Write-Verbose "`t`t`t`t`tAssess Tier Association"
				if($ObjectTierAssoc -in $TierAssocFilt){
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
								$OUPathReg = "^(OU=Tasks,OU=)($($OrgElements -Join '|'))(,OU=$($FocusHash['Admin']),OU=)($CETierRegEx),$DomDN"
								$PrefixName = $Prefix.NameElement
								Write-Verbose "`t`t`t`t`tProcess Prefix:`t$PrefixName"
								$TDGValue = Join-String -Strings $PrefixName,$TDGFullSuffix -Separator "-"
								Write-Verbose "`t`t`t`t`t`tFull Name:`t$TDGValue"

								Write-Verbose "`t`t`t`t`tTesting destination path..."
								[string]$Destination = "$($TargetDEObj.DistinguishedName)"
								Write-Verbose ""
								Write-Verbose "`t`t`t`t`t`tInitial Value:`t$Destination"

								#Check ObjectType or Org
								if($Destination -match "^(OU=)($($OrgElements -Join '|'))"){
									$Destination = "OU=Tasks,$Destination"
									Write-Debug "`t`t`t`t`t`t`tCP1 (Obj or Org) Value:`t$Destination"
								}

								#Check Specific ObjectType
								if($Destination -match "^OU=$ObjectType," -and $ObjectType -notlike 'Tasks'){
									$Destination = $Destination -replace "^(OU=)($ObjectType)(,)","OU=Tasks,"
									Write-Debug "`t`t`t`t`t`t`tCP2 (ObjectType) Value:`t$Destination"
								}
								
								#Check focus
								if($Destination -notmatch ",OU=$($FocusHash['Admin']),"){
									$Destination = $Destination -replace "(OU=)($FocusID)(,)","OU=$($FocusHash['Admin']),"
									Write-Debug "`t`t`t`t`t`t`tCP3 (Focus) Value:`t$Destination"
								}

								#Check RegEx match
								if($Destination -notmatch $OUPathReg){
									$Destination = "OU=Tasks,OU=$(($PrefixName -split '_')[2]),OU=$($FocusHash['Admin']),OU=$($CETierHash[$TierID]),$DomDN"
									Write-Debug "`t`t`t`t`t`t`tCP4 (Rewrite) Value:`t$Destination"
								}

								#Check exists
								if(-not($([adsi]::Exists("LDAP://$Destination")))){
									$Destination = $Destination -replace "(OU=)($($OrgElements -Join '|'))(,)","OU=$OUGlobal,"
									Write-Debug "`t`t`t`t`t`t`tCP4 (Existence, Redir Global) Value:`t$Destination"

								}

								Write-Verbose "`t`t`t`t`t`tFinal Destination:`t$Destination"
								$TDGElements = [PSCustomObject]@{
									TDGName = $TDGValue
									TDGSetAcl = $GrantAcl
									TDGDestination = $Destination
									TDGRelSuffix = $TDGSuffix
								}

								Write-Debug "`t`t`t`t`t`tTDGElements for Creation: `n`t`t`t`t`t`t$TDGElements"

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
				$TDGProcessedCount = 0
			}

			foreach($TDGItem in $AllTDGValues){
				if($Pipe){
					if($TDGProcessedCount -gt 1 -and $TotalTDGItems -gt $TDGProcessedCount){
						$TDGPercentComplete = ($TDGProcessedCount / $TotalTDGItems) * 100
					}else{
						$TDGPercentComplete = 0
					}

					Write-Progress -Id $($ProgParams.Id + 5) -Activity 'Processing' -CurrentOperation "$($TDGItem.TDGRelSuffix)" -PercentComplete $TDGPercentComplete -ParentId $ProgParams.Id
				}

				$TDGName = $TDGItem.TDGName
				$TDGDestination = $TDGItem.TDGDestination
				$DestType = ($TDGDestination.GetType()).Name
				Write-Verbose "`t`t`t`tDest Obj Type:$DestType"

				# Identify additional attribute values
				$PreTmp = $(($TDGName).Split('-'))[0]
				Write-Verbose "$($FunctionName): `tPreTmp Value: `t$($PreTmp)"
				#!: Note - Double cast is intentional and required to prevent returning ASCI char code instead of int value
				$tierTmp = [int][string]$PreTmp[1]
				Write-Verbose "$($FunctionName): `ttierTmp Value: `t$($tierTmp)"
				$scopeTmp = $(($PreTmp).Split('_'))[2]
				Write-Verbose "$($FunctionName): `tscopeTmp Value: `t$($scopeTmp)"

				if ($pscmdlet.ShouldProcess($($TDGName), "Create AD Group")) {
					Write-Verbose "`t`t`t`tCalling New-ADDADObject"
					Write-Verbose "`t`t`t`t`tName:`t$TDGName"
					Write-Verbose "`t`t`t`t`tDestination:`t$TDGDestination"
					$TDGObj = New-ADDADObject -ObjName $TDGName -ObjParentDN $TDGDestination -ObjTier $tierTmp -ObjScope $scopeTmp @TDGHash

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
				Write-Progress -Id $($ProgParams.Id + 5) -Activity 'Processing' -Completed -ParentId $ProgParams.Id
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
			Write-Progress -Activity "Creating OUs" -CurrentOperation "Finished" -Completed @ProgParams
		}


		if($FinalTDGObjs){
			if($CreateVal -gt 1) {
				Write-Verbose "`t`tManual Chain Execution Detected - Passing staged TDGs to Grant-ADDTDGRights"
				Write-Verbose "------------------- $($FunctionName): End -------------------"
				Write-Verbose ""
				Write-Verbose ""

				if ($pscmdlet.ShouldProcess("Process $($FinalTDGObjs.Count) TDGs", "Setting ACLs")) {
					$FinalTDGObjs | Grant-ADDTDGRight -PipelineCount $($FinalTDGObjs.Count)
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
