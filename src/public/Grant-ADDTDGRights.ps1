function Grant-ADDTDGRights {
<#
	.SYNOPSIS
		Configures ACLs as defined based on the Task Delegation Group naming convention

	.DESCRIPTION
		This cmdlet accepts a directory entry representing an AD group, or can also string values with one or more group names. The values will
		be checked against the OU structure and the appropriate ACLs applied, based on the naming convention employed by the model.

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
		Help Last Updated: 010/06/2020

		Cmdlet Version: 1.0
		Cmdlet Status: Release

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
	[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Medium')]
	Param (
		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]
		$TargetGroup,

		[Parameter(ParameterSetName="ManualRun")]
		[Parameter(ParameterSetName="ChainRun")]
		[int]$PipelineCount,

		[Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[System.DirectoryServices.DirectoryEntry]$TargetDE,

		[Parameter(DontShow,ParameterSetName="ChainRun")]
		[Switch]$MTRun
	)

	begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""
		#TODO: Update help

		if($pscmdlet.ParameterSetName -like "ManualRun"){
			$ChainRun = $false
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
					Id = 30
				}
				
				if($PipelineCount){
					$ProgParams.Add("ParentId",25)
				}
			}else {
				$ProgParams = @{
					Id = 20
				}
				
				if($PipelineCount){
					$ProgParams.Add("ParentId",15)
				}
			}

			if($PipelineCount -gt 0){
				$TotalItems = $PipelineCount

			}

			Write-Verbose "`t`tInitiating Progress Tracking"
			Write-Progress -Activity "Setting ACLs" -CurrentOperation "Initializing..." @ProgParams
		}else{
			Write-Verbose "Pipeline:`tNot Detected"
		}
		
		$ProcessedCount = 0
		$FailedCount = 0
		$GCloopCount = 1
		$loopCount = 1

		$loopTimer = [System.Diagnostics.Stopwatch]::new()
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

		if($Pipe){
			if($ProcessedCount -gt 1 -and $TotalItems -gt $ProcessedCount){
				$PercentComplete = ($ProcessedCount / $TotalItems) * 100
			}else{
				$PercentComplete = 0
			}

			Write-Progress @ProgParams -Activity "Setting ACLs per TDG" -CurrentOperation "Deploying..." -Status "Processed $ProcessedCount" -PercentComplete $PercentComplete
		}

		#region DetectInputType
		# Start process run by detecting the input object type
		Write-Verbose "`t`tDetect input type details"
		Write-Verbose ""
		if($Pipe){
			Write-Verbose "`t`t`tInput Type:`tPipeline"
			$TargetItem = $_
		}elseif($TargetGroup) {
			Write-Verbose "`t`t`tInput Type:`tTargetGroup (single item)"
			$TargetItem = $TargetGroup
		}

		Write-Verbose ""
		Write-Verbose "`t`t`tTarget Value:`t$TargetItem"

		try {
			$TargetType = ($TargetItem.GetType()).name
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

			Default {
				if($TargetItem -like "LDAP://*"){
					$DEPath = $TargetItem
				}else{
					if($TargetItem -match $OUdnRegEx){
						$DEPath = "LDAP://$TargetItem"
					}else{
						Write-Warning "The specified object ($TargetItem) is not in distinguishedName format - Skipping"
						$FailedCount ++
						break
					}
				}
			}
		}

		Write-Verbose "`t`t`tDEPath:`t$DEPath"

		if([adsi]::Exists($DEPath)) {
			$TargetDEObj = New-Object System.DirectoryServices.DirectoryEntry($DEPath)
			Write-Verbose "`t`tOrg OU Target Path:`t$($TargetDEObj.Path)"
		}else {
			Write-Warning "The specified OU ($TargetItem) wasn't found in the domain - Skipping"
			$FailedCount ++
			break
		}
		#endregion DetectInputType

		if($pscmdlet.ParameterSetName -like "ManualRun*"){
			if(!($TargetGroup)){
				Write-Warning "`t`tNo value provided for TDG to process - Skipping"
				$FailedCount ++
				break
			}elseif ($TargetGroup -like "LDAP://*") {
				$TargetDEObj = New-Object System.DirectoryServices.DirectoryEntry($TargetGroup)
			}else {
				$GrpADSISearcher = New-Object System.DirectoryServices.DirectorySearcher
				$GrpADSISearcher.SearchRoot
				$GrpADSISearcher.Filter = "(&(objectCategory=group)(name=$TargetGroup))"
				$GrpSearchResults = $($GrpADSISearcher.FindAll())
				foreach($SearchResult in $GrpSearchResults){
					$TargetDEObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($($SearchResult.path))
				}
			}
		}

		$gName = $TargetDEObj.psbase.Properties["name"]

		$TargetPaths = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]

		if($gName){
			$SourceValue = $gName
			Write-Verbose "`t`tProcessing TDG: $SourceValue"
		}else{
			Write-Error "Couldn't retrieve group name for DEPath - Skipping" -ErrorAction Continue
			break
		}

		Write-Verbose "`t`tConvertTo-Element - Process SourceValue"
		#Break input into separate elements for processing
		$SourceItem = ConvertTo-Elements -SourceValue $SourceValue
		if(!($SourceItem)){
			Write-Error "Failed to obtain results from ConvertTo-Elements - skipping"
		}else{
			Write-Verbose "`t`tConvertTo-Element: SourceItem"
			Write-Verbose "`t`t`t`t$($SourceItem | Out-String)"
		}

		if($SourceItem.TargetType -like "DistinguishedName"){

		}else{
			Write-Verbose "`t`tGet-ADGroup"
			[byte[]]$gSID = $TargetDEObj.objectSid.value
			$DelegateSID = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $gSID, 0
			Write-Verbose "`t`tADGroup Name:`t$gName"
			Write-Verbose "`t`tADGroup SID:`t$DelegateSID"

			#region SetInitialReferencePoints
			$Tier = $SourceItem.TierID
			Write-Verbose "`t`tReference Points: Tier - $Tier"
			$FocusID = $SourceItem.FocusID
			Write-Verbose "`t`tReference Points: FocusID - $FocusID"
			$TypeOU = $SourceItem.ObjectType
			Write-Verbose "`t`tReference Points: TypeOU - $TypeOU"
			$PermElements = ($SourceValue).Split("-")[1]
			Write-Verbose "`t`tReference Points: PermElements - $PermElements"
			$Descriptor = $SourceItem.Descriptor
			Write-Verbose "`t`tReference Points: Descriptor - $Descriptor"
			$ObjRefID = ($PermElements).Split("_")[0]
			Write-Verbose "`t`tReference Points: ObjrefID - $ObjRefID"
			$ObjScope = ($PermElements).Split("_")[1]
			Write-Verbose "`t`tReference Points: ObjScope - $ObjScope"
			$ObjRights = ($PermElements).Split("_")[2]
			Write-Verbose "`t`tReference Points: ObjRights - $ObjRights"
			$MaxLvl = $SourceItem.MaxLvl
			$OrgLvl1 = $SourceItem.OrgL1
			Write-Verbose "`t`tReference Points: OrgLvl1 - $OrgLvl1"
			if($SourceItem.OrgL2){ $OrgLvl2 = $SourceItem.OrgL2 }
			if($SourceItem.OrgL3){ $OrgLvl3 = $SourceItem.OrgL3 }
			#endregion SetInitialReferencePoints

			#region BuildTargetPathElements
			$ADSISearcher = New-Object System.DirectoryServices.DirectorySearcher

			$TPRoot = Join-String $FocusID,$Tier -Separator ",OU="
			Write-Verbose "`t`tReference Points: TPRoot - $TPRoot"

			if($FocusID -like $FocusHash["Stage"]){
				$SPath = $TPRoot
			}else{
				$SPath = Join-String $OrgLvl1,$TPRoot -Separator ",OU="
				$OrgPathLvl = 1
				if($OrgLvl2){
					$SPath = Join-String $OrgLvl2,$SPath -Separator ",OU="
					$OrgPathLvl = 2
				}
				if($OrgLvl3){
					$SPath = Join-String $OrgLvl3,$SPath -Separator ",OU="
					$OrgPathLvl = 3
				}
			}

			$SPath = Join-String "OU=$($SPath)",$DomDN -Separator ","
			$SPath = "LDAP://$SPath"
			Write-Verbose "`t`tBase Search Path:`t$SPath"

			$ADSISearcher.SearchRoot = $SPath

			Write-Verbose "`t`tInitiating ADSI Search"
			$SearchResultLoop = 0

			switch ($FocusID) {
				{$_ -like $FocusHash["Server"]} {

					$OrgLvlCheck = $MaxLvl - $OrgPathLvl
					switch ($OrgLvlCheck) {
						2 {
							$ADSISearcher.Filter = "(objectCategory=organizationalUnit)"
							$ADSISearcher.SearchScope = "OneLevel"
							try {
								$SubSearchResults = $($ADSISearcher.FindAll())
								foreach($SubSearchResult in $SubSearchResults){
									$ADSISearcher.SearchRoot = $SubSearchResult.Path
									try {
										$SearchResults = $($ADSISearcher.FindAll())
										foreach($SearchResult in $SearchResults){
											$resultObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($($SearchResult.path))
											if($resultObj){
												Write-Verbose "`t`tResult Found:`t$($resultObj.distinguishedname)"
												if($($resultObj.distinguishedname) -notin $($TargetPaths).distinguishedname){
													$TargetPaths.Add($resultObj)
													$SearchResultLoop ++
													Write-Verbose "`t`t`t`tDirectoryEntry Added to Placeholder"
												}else{
													Write-Verbose "`t`t`t`tDirectoryEntry Not Added:`tAlready Present"
												}
											}
										}
									}
									catch {
										Write-Verbose "`t`tNo child OU results for Lvl 2 - $SPath"
									}
								}
							}
							catch {
								Write-Verbose "`t`tNo child OU results for Lvl 1 - $SPath"
							}

						}

						1 {
							$ADSISearcher.Filter = "(objectCategory=organizationalUnit)"
							$ADSISearcher.SearchScope = "OneLevel"
							try {
								$SearchResults = $($ADSISearcher.FindAll())
								foreach($SearchResult in $SearchResults){
									$resultObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($($SearchResult.path))
									if($resultObj){
										Write-Verbose "`t`tResult Found:`t$($resultObj.distinguishedname)"
										if($($resultObj.distinguishedname) -notin $($TargetPaths).distinguishedname){
											$TargetPaths.Add($resultObj)
											$SearchResultLoop ++
											Write-Verbose "`t`t`t`tDirectoryEntry Added to Placeholder"
										}else{
											Write-Verbose "`t`t`t`tDirectoryEntry Not Added:`tAlready Present"
										}
									}
								}
							}
							catch {
								Write-Verbose "`t`tNo child OU results for path - $SPath"
							}
						}

						0 {
							$resultObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($SPath)
							if($resultObj){
								Write-Verbose "`t`tResult Found:`t$($resultObj.distinguishedname)"
								if($($resultObj.distinguishedname) -notin $($TargetPaths).distinguishedname){
									$TargetPaths.Add($resultObj)
									$SearchResultLoop ++
									Write-Verbose "`t`t`t`tDirectoryEntry Added to Placeholder"
								}else{
									Write-Verbose "`t`t`t`tDirectoryEntry Not Added:`tAlready Present"
								}
							}
						}
					}
				}

				{$_ -like $FocusHash["Stage"]} {
					$ADSISearcher.Filter = "(objectCategory=organizationalUnit)"
					$ADSISearcher.SearchScope = "OneLevel"
					try {
						$SearchResults = $($ADSISearcher.FindAll())
						foreach($SearchResult in $SearchResults){
							$resultObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($($SearchResult.path))
							if($resultObj){
								Write-Verbose "`t`tResult Found:`t$($resultObj.distinguishedname)"
								if($($resultObj.distinguishedname) -notin $($TargetPaths).distinguishedname){
									$TargetPaths.Add($resultObj)
									$SearchResultLoop ++
									Write-Verbose "`t`t`t`tDirectoryEntry Added to Placeholder"
								}else{
									Write-Verbose "`t`t`t`tDirectoryEntry Not Added:`tAlready Present"
								}
							}
						}
					}
					catch {
						Write-Verbose "`t`tNo child OU results for path - $SPath"
					}
				}

				Default {
					$ADSISearcher.Filter = "(&(objectCategory=organizationalUnit)(name=$TypeOU))"
					try {
						$SearchResults = $($ADSISearcher.FindAll())
						foreach($SearchResult in $SearchResults){
							$resultObj = New-Object System.DirectoryServices.DirectoryEntry -ArgumentList @($($SearchResult.path))
							if($resultObj){
								Write-Verbose "`t`tResult Found:`t$($resultObj.distinguishedname)"
								if($($resultObj.distinguishedname) -notin $($TargetPaths).distinguishedname){
									$TargetPaths.Add($resultObj)
									$SearchResultLoop ++
									Write-Verbose "`t`t`t`tDirectoryEntry Added to Placeholder"
								}else{
									Write-Verbose "`t`t`t`tDirectoryEntry Not Added:`tAlready Present"
								}
							}
						}
					}
					catch {
						Write-Verbose "`t`tNo results for $TypeOU in $SPath"
					}
				}
			}

			Write-Verbose "`t`tAdded $($SearchResultLoop) paths for processing`n"
			#endregion BuildTargetPathElements

			#region BuildACLElements
			Write-Verbose "`t`t`t`tImport TDGInfo"
			$TDGInfo = $PropGroups | Where-Object{$_.OBJ_name -like $Descriptor}
			if(!($TDGInfo)){
				Write-Verbose "`t`tTDG Descriptor: $($Descriptor)`tIssue: Matching entry not found in DB`tAction: Skip"
				Write-Error "TDG Descriptor: $($Descriptor)`tIssue: Matching entry not found in DB`tAction: Skip"
				Read-Host "Press Enter to exit"
				break
			}

			$ObjData = $ObjInfo | Where-Object {$_.OBJ_relatedfocus -like $FocusID -and $_.OBJ_refid -like $ObjRefID}
			Write-Verbose "`t`tObjData - `n`t`t`t`t$($ObjData | Format-Table | Out-String -Stream)"

			if(!($ObjData)){
				Write-Verbose "`t`tObjType: ($ObjRefID)`tIssue: Object type not found`t Action: Skip"
				Write-Error "$FunctionName - ObjType: ($ObjRefID)`tIssue: Object type not found`t Action: Skip" -ErrorAction Continue
				$FailedCount ++
				break
			}elseif($ObjData.count -gt 1){
				Write-Error "$FunctionName - ObjType: ($ObjRefID)`tObjFocus: ($FocusID)`tIssue: Query returned multiple results`tAction: Skip" -ErrorAction Continue
				$FailedCount ++
				break
			}

			$ADClass = $ObjData.OBJ_adclass
			Write-Verbose "`t`tADClass - $ADClass"

			if($ObjRights -like "DL"){
				$accType = "Deny"
			}else{
				$accType = "Allow"
			}
			Write-Verbose "`t`taccType - $accType"

			Write-Verbose "`t`tProcess ObjScope to identify PGProperties"
			$PGProperties = New-Object System.Collections.Generic.List[psobject]

			switch ($ObjScope){
				"PG" {
					Write-Verbose "`t`t`t`tProcess ObjScope: PG"
					Write-Verbose "`t`t`t`tProcess ObjScope: PG: Retrieve Property Group Definition"
					Write-Verbose "`t`t`t`tImport PGInfo"
					$PGInfo = $PropGroupMap | Where-Object{$_.OBJ_pgrpname -like $Descriptor} | Select-Object OBJ_propertyname
					$PGInfoCount = $PGInfo.count
					if($PGInfo){
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Returned PGs (Count) - $($PGInfoCount)"
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values"
						$PGProcessedCount = 0
						$PGFailedCount = 0
						$PGInfo | ForEach-Object{
							$pname = $_.OBJ_propertyname
							Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname - $pname"
							if($attribmap["$($pname)"]){
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname in attribmap"
								$PGPObj = [PSCustomObject]@{
									PropName   = $pname
									PropType   = "Attribute"
									ACLTarget  = $attribmap["$($pname)"]
									ADRights   = $RightsHash["$($ObjRights)"]
									ACLScope   = $classmap["$($ADClass)"]
								}
							}elseif($exrightsmap["$($pname)"]){
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname in exrightsmap"
								$PGPObj = [PSCustomObject]@{
									PropName   = $pname
									PropType   = "ExtendedRight"
									ACLTarget  = $exrightsmap["$($pname)"]
									ADRights   = "ExtendedRight"
									ACLScope   = $classmap["$($ADClass)"]
								}
							}else{
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname match NOT found!!"
							}

							if($PGPObj){
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
								if($pname -notin $($PGProperties.PropName)){
									$PGProperties.Add($PGPObj)
									$PGProcessedCount ++

									if($pname -like "ms-Mcs-AdmPwd"){
										Write-Verbose "`t`t`t`t`t`tMcs-AdmPwd detected: Adding ExtendedRight"
										$PGPObj = [PSCustomObject]@{
											PropName   = $pname
											PropType   = "ExtendedRight"
											ACLTarget  = $attribmap["$($pname)"]
											ADRights   = "ExtendedRight"
											ACLScope   = $classmap["$($ADClass)"]
										}

										$PGProperties.Add($PGPObj)
										$PGProcessedCount ++
									}
								}
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
							}else{
								$PGFailedCount ++
								Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
							}
						}
					}else{
						Write-Verbose "`t`t`t`tNo Property Group info returned"
						Write-Error "`t`t`t`tNo Property Group info returned"
					}
				}
				"PR" {
					Write-Verbose "`t`t`t`tProcess ObjScope: PR"
					Write-Verbose "`t`t`t`t`t`tDescriptor`tObjRights`tADClass"
					Write-Verbose "`t`t`t`t`t`t$Descriptor`t$ObjRights`t$ADClass"
					$pname = $Descriptor

					if($attribmap[$Descriptor]){
						Write-Verbose "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor in attribmap"

						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "Attribute"
							ACLTarget  = $attribmap["$($Descriptor)"]
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $classmap["$($ADClass)"]
						}
					}elseif($exrightsmap["$($Descriptor)"]){
						Write-Verbose "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor in exrightsmap"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ExtendedRight"
							ACLTarget  = $exrightsmap["$($Descriptor)"]
							ADRights   = "ExtendedRight"
							ACLScope   = $classmap["$($ADClass)"]
						}
					}else{
						Write-Verbose "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor match NOT found!!"
						Write-Verbose "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor match NOT found!!"
					}

					if($PGPObj){
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
						if($pname -notin $($PGProperties.PropName)){
							$PGProperties.Add($PGPObj)
							$PGProcessedCount ++
						}
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
					}else{
						$PGFailedCount ++
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
					}
				}
				"OB" {
					Write-Verbose "`t`t`t`tProcess ObjScope: OB"
					Write-Verbose "`t`t`t`t`t`tObjRights`tADClass"
					Write-Verbose "`t`t`t`t`t`t$ObjRights`t$ADClass"
					$pname = $ADClass

					if($ObjRights -like "FC"){
						Write-Verbose "`t`t`t`tProcess ObjScope: OB: FC Detected"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ADClass"
							ACLTarget  = $allGuid
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $classmap["$($ADClass)"]
						}
					}else{
						Write-Verbose "`t`t`t`tProcess ObjScope: OB: FC not Detected"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ADClass"
							ACLTarget  = $classmap["$($ADClass)"]
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $null
						}
					}


					if($PGPObj){
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
						if($pname -notin $($PGProperties.PropName)){
							$PGProperties.Add($PGPObj)
							$PGProcessedCount ++

							if($pname -like 'computer' -and $ObjRights -like 'DE'){
								Write-Verbose "`t`t`t`tProcess ObjScope: OB: Class Computer detected - Adding serviceConnectionPoint ACL"
								$PGPObjEx = [PSCustomObject]@{
									PropName   = $pname
									PropType   = "ADClass"
									ACLTarget  = $classmap["serviceConnectionPoint"]
									ADRights   = $RightsHash["$($ObjRights)"]
									ACLScope   = $null
								}
								$PGProperties.Add($PGPObjEx)
								$PGProcessedCount ++
							}
						}
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
					}else{
						$PGFailedCount ++
						Write-Verbose "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
					}
				}
				default {
					Write-Error "Unable to find any logical matches for specified target type - Skipping"
					Read-Host "Press enter to skip"
					break
				}
			}

			$PGPropertiesCount = $PGProperties.count
			Write-Verbose "`n`n`t`tIdentified $PGPropertiesCount PGProperties for processing"

			$InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]'Descendents'
			$aces = New-Object System.Collections.Generic.List[System.DirectoryServices.ActiveDirectoryAccessRule]

			Write-Debug "`t`t`t`tAce Info"
			Write-Debug "`t`t`t`t`t$aces"
			if($PGProperties){
				foreach($PGProp in $PGProperties){
					Write-Verbose "`t`t`t`tPGProperty Info"
					Write-Verbose "`t`t`t`t`t`tName`tType"
					Write-Verbose "`t`t`t`t`t`t-----`t-----"
					Write-Verbose "`t`t`t`t`t`t$($PGProp.PropName)`t$($PGProp.PropType)"
					
					foreach($TarPath in $TargetPaths){
						Write-Verbose "`t`t`t`t`t`t$($FunctionName):`t Checking for legacy ACEs:`t $($TarPath.DistinguishedName)"
						$AclList = $TarPath.psbase.ObjectSecurity.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])
						$RemoveAces = $AclList | Where-Object {$_.identityreference -like $DelegateSID}
						
						if($RemoveAces){
							Write-Verbose "`t`t`t`t`t`t$($FunctionName):`t Found $($RemoveAces.Count) legacy ACEs:`t $($TarPath.DistinguishedName)"
							Write-Verbose "`t`t`t`t`t`t$($FunctionName):`t Initiating ACE cleanup before rewrite:`t $($TarPath.DistinguishedName)"
							
							foreach($RA in $RemoveAces){
								$TarPath.psbase.ObjectSecurity.RemoveAccessRule($RA) | Out-Null
							}
							
							$TarPath.psbase.CommitChanges()
							Write-Verbose "`t`t`t`t`t`t$($FunctionName):`t Legacy ACEs removed:`t $($TarPath.DistinguishedName)"
						}
					}
					

					$aceDef = $DelegateSID,($PGProp.ADRights),$accType,($PGProp.ACLTarget),$InheritanceType
					Write-Verbose "`t`t`t`t`t`tProcess PGProperties (Pre-ACLScope): aceDef - $($aceDef | Out-String)"
					if($PGProp.ACLScope){
						$aceDef += ($PGProp.ACLScope)
					}
					Write-Verbose "`t`t`t`t`t`tProcess PGProperties (Post-ACLScope): aceDef - $($aceDef | Out-String)"
					try {
						$aceObj = New-Object -TypeName System.DirectoryServices.ActiveDirectoryAccessRule($aceDef)
					}
					catch {
						Write-Error -Category InvalidData -CategoryActivity "Create aceObj" -CategoryTargetName "$SourceValue" -Message "Unable to create ACE for aceDef - `n$($aceDef | Out-String)" -ErrorAction Continue
					}

					if($aceObj){
						Write-Verbose "`t`t`t`t`t`tProcess PGProperties: aceObj - $($aceObj | Out-String)"
						$aces.Add($aceObj)
						Write-Verbose "`t`t`t`t`t`tProcess PGProperties: Process ACE Object: Success"
					}else{
						Write-Verbose "`t`t`t`t`t`tProcess PGProperties: Process ACE Object: Failure"
					}
				}
			}
			Write-Debug "`t`tAces added`t$($aces.count)`n`n"
			#endregion BuildACLElements

			foreach($TarPath in $TargetPaths){
				Write-Verbose "`t`t`t`t`t`tApplying DACLs to $($TarPath.DistinguishedName)"
				$SetAclLoop = 1
				$SetAclCount = $aces.Count
				foreach($ace in $aces){
					Write-Verbose "`t`t`t`t`t`tWriting ACE $SetAclLoop of $SetAclCount"
					$TarPath.psbase.ObjectSecurity.AddAccessRule($ace)
					$SetAclLoop ++
				}

				try {
					$TarPath.psbase.CommitChanges()
				}
				catch {
					Write-Verbose "`t`t`t`t`t`tFailed to write one or more ACEs for path [$($TarPath.Path)]"
				}
			}

		}

		$ProcessedCount ++
		$GCloopCount ++
		$loopCount ++
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
		Write-Verbose "`t`tTDGs procesed:`t$ProcessedCount"
		Write-Verbose "`t`tTDGs failed:`t$FailedCount"
		$FinalLoopTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 0)
		$FinalAvgLoopTime = [math]::Round(($loopTimes | Measure-Object -Average).Average, 0)
		Write-Verbose "`t`tTotal time (sec):`t$FinalLoopTime"
		Write-Verbose ""
		Write-Verbose ""

		$TDGRightsResults = [PSCustomObject]@{
			Processed = $ProcessedCount
			Failed = $FailedCount
			Runtime = $FinalLoopTime
			AvgLoopTime = $FinalAvgLoopTime
		}

		if($Pipe){
			Write-Progress -Id 15 -Activity "$FunctionName" -Status "Finished Processing ACLs..." -Completed -ParentId 10
		}

		Write-Verbose "------------------- $($FunctionName): End -------------------"
		Write-Verbose ""

		if($ChainRun){
			return $TDGRightsResults
		}
	}
}