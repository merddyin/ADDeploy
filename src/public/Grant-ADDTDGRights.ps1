function Grant-ADDTDGRights {
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
        Help Last Updated: 08/06/2019

        Cmdlet Version: 0.1
        Cmdlet Status: (Alpha/Beta/Release-Functional/Release-FeatureComplete)

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

		[Parameter(ParameterSetName="ManualRunB",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]$StartOU,

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

		if($pscmdlet.ParameterSetName -like "ManualRun"){
            $ChainRun = $false
        }else {
            $ChainRun = $true
        }


		if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
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

			Write-Progress @ProgParams -Activity "Setting ACLs" -CurrentOperation "Initializing..."

		}

        $ProcessedCount = 0
        $FailedCount = 0
        $ExistingCount = 0
        $NewCount = 0
		$TotalAcesCount = 0
		$FailedAcesCount = 0
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

		if($Pipe){
			if($ProcessedCount -gt 1 -and $TotalItems -gt $ProcessedCount){
				$PercentComplete = ($ProcessedCount / $TotalItems) * 100
			}else{
				$PercentComplete = 0
			}

			Write-Progress -@ProgParams -Activity "Creating TDGs by OU" -CurrentOperation "Analyzing..." -Status "Processed $ProcessedCount OUs" -PercentComplete $PercentComplete
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
            Write-Verbose "`t`tOrg OU Target Path:`t$($TargetDEObj.Path)"
        }else {
            Write-Error "The specified OU ($TargetItem) wasn't found in the domain - Skipping" -ErrorAction Continue
            $FailedCount ++
            break
        }
        #endregion DetectInputType

		if($pscmdlet.ParameterSetName -like "ManualRun*"){
            if(!($TargetGroup)){
                Write-Error "`t`tNo value provided for TDG to process - Skipping" -ErrorAction Continue
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

		Write-Debug "`t`tConvertTo-Element - Process SourceValue"
		#Break input into separate elements for processing
		$SourceItem = ConvertTo-Elements -SourceValue $SourceValue
		if(!($SourceItem)){
			Write-Error "Failed to obtain results from ConvertTo-Elements - skipping"
		}else{
			Write-Debug "`t`tConvertTo-Element: SourceItem"
			Write-Debug "`t`t`t`t$($SourceItem | Out-String)"
		}

		if($SourceItem.TargetType -like "DistinguishedName"){

		}else{
			Write-Debug "`t`tGet-ADGroup"
			[byte[]]$gSID = $TargetDEObj.objectSid.value
			$DelegateSID = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $gSID, 0
			Write-Verbose "`t`tADGroup Name:`t$gName"
			Write-Verbose "`t`tADGroup SID:`t$DelegateSID"

			#region SetInitialReferencePoints
			$Tier = $SourceItem.TierID
			Write-Debug "`t`tReference Points: Tier - $Tier"
			$FocusID = $SourceItem.FocusID
			Write-Debug "`t`tReference Points: FocusID - $FocusID"
			$TypeOU = $SourceItem.ObjectType
			Write-Verbose "`t`tReference Points: TypeOU - $TypeOU"
			$PermElements = ($SourceValue).Split("-")[1]
			Write-Debug "`t`tReference Points: PermElements - $PermElements"
			$Descriptor = $SourceItem.Descriptor
			Write-Debug "`t`tReference Points: Descriptor - $Descriptor"
			$ObjRefID = ($PermElements).Split("_")[0]
			Write-Debug "`t`tReference Points: ObjrefID - $ObjRefID"
			$ObjScope = ($PermElements).Split("_")[1]
			Write-Debug "`t`tReference Points: ObjScope - $ObjScope"
			$ObjRights = ($PermElements).Split("_")[2]
			Write-Debug "`t`tReference Points: ObjRights - $ObjRights"
			$MaxLvl = $SourceItem.MaxLvl
			$OrgLvl1 = $SourceItem.OrgL1
			Write-Debug "`t`tReference Points: OrgLvl1 - $OrgLvl1"
			if($SourceItem.OrgL2){ $OrgLvl2 = $SourceItem.OrgL2 }
			if($SourceItem.OrgL3){ $OrgLvl3 = $SourceItem.OrgL3 }
			#endregion SetInitialReferencePoints

			#region BuildTargetPathElements
			$ADSISearcher = New-Object System.DirectoryServices.DirectorySearcher

			$TPRoot = Join-String $FocusID,$Tier -Separator ",OU="
			Write-Debug "`t`tReference Points: TPRoot - $TPRoot"

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
			Write-Debug "`t`tObjData - `n`t`t`t`t$($ObjData | Format-Table | Out-String -Stream)"

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
			Write-Debug "`t`taccType - $accType"

			Write-Debug "`t`tProcess ObjScope to identify PGProperties"
			$PGProperties = New-Object System.Collections.Generic.List[psobject]

			switch ($ObjScope){
				"PG" {
					Write-Debug "`t`t`t`tProcess ObjScope: PG"
					Write-Debug "`t`t`t`tProcess ObjScope: PG: Retrieve Property Group Definition"
					Write-Verbose "`t`t`t`tImport PGInfo"
					$PGInfo = $PropGroupMap | Where-Object{$_.OBJ_pgrpname -like $Descriptor} | Select-Object OBJ_propertyname
					$PGInfoCount = $PGInfo.count
					if($PGInfo){
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Returned PGs (Count) - $($PGInfoCount)"
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values"
						$PGProcessedCount = 0
						$PGFailedCount = 0
						$PGInfo | ForEach-Object{
							$pname = $_.OBJ_propertyname
							Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname - $pname"
							if($attribmap["$($pname)"]){
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname in attribmap"
								$PGPObj = [PSCustomObject]@{
									PropName   = $pname
									PropType   = "Attribute"
									ACLTarget  = $attribmap["$($pname)"]
									ADRights   = $RightsHash["$($ObjRights)"]
									ACLScope   = $classmap["$($ADClass)"]
								}
							}elseif($exrightsmap["$($pname)"]){
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname in exrightsmap"
								$PGPObj = [PSCustomObject]@{
									PropName   = $pname
									PropType   = "ExtendedRight"
									ACLTarget  = $exrightsmap["$($pname)"]
									ADRights   = "ExtendedRight"
									ACLScope   = $classmap["$($ADClass)"]
								}
							}else{
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: pname match NOT found!!"
							}

							if($PGPObj){
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
								if($pname -notin $($PGProperties.PropName)){
									$PGProperties.Add($PGPObj)
									$PGProcessedCount ++
								}
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
							}else{
								$PGFailedCount ++
								Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
							}
						}
					}else{
						Write-Verbose "`t`t`t`tNo Property Group info returned"
						Write-Error "`t`t`t`tNo Property Group info returned"
					}
				}
				"PR" {
					Write-Debug "`t`t`t`tProcess ObjScope: PR"
					Write-Debug "`t`t`t`t`t`tDescriptor`tObjRights`tADClass"
					Write-Debug "`t`t`t`t`t`t$Descriptor`t$ObjRights`t$ADClass"
					$pname = $Descriptor

					if($attribmap[$Descriptor]){
						Write-Debug "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor in attribmap"

						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "Attribute"
							ACLTarget  = $attribmap["$($Descriptor)"]
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $classmap["$($ADClass)"]
						}
					}elseif($exrightsmap["$($Descriptor)"]){
						Write-Debug "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor in exrightsmap"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ExtendedRight"
							ACLTarget  = $exrightsmap["$($Descriptor)"]
							ADRights   = "ExtendedRight"
							ACLScope   = $classmap["$($ADClass)"]
						}
					}else{
						Write-Verbose "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor match NOT found!!"
						Write-Debug "`t`t`t`tProcess ObjScope: PR: Process PR Value: Descriptor match NOT found!!"
					}

					if($PGPObj){
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
						if($pname -notin $($PGProperties.PropName)){
							$PGProperties.Add($PGPObj)
							$PGProcessedCount ++
						}
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
					}else{
						$PGFailedCount ++
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
					}
				}
				"OB" {
					Write-Debug "`t`t`t`tProcess ObjScope: OB"
					Write-Debug "`t`t`t`t`t`tObjRights`tADClass"
					Write-Debug "`t`t`t`t`t`t$ObjRights`t$ADClass"
					$pname = $ADClass

					if($ObjRights -like "FC"){
						Write-Debug "`t`t`t`tProcess ObjScope: OB: FC Detected"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ADClass"
							ACLTarget  = $allGuid
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $classmap["$($ADClass)"]
						}
					}else{
						Write-Debug "`t`t`t`tProcess ObjScope: OB: FC not Detected"
						$PGPObj = [PSCustomObject]@{
							PropName   = $pname
							PropType   = "ADClass"
							ACLTarget  = $classmap["$($ADClass)"]
							ADRights   = $RightsHash["$($ObjRights)"]
							ACLScope   = $null
						}
					}

					if($PGPObj){
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: PGPObj - `n`t`t$($PGPObj | Out-String -Stream)"
						if($pname -notin $($PGProperties.PropName)){
							$PGProperties.Add($PGPObj)
							$PGProcessedCount ++
						}
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Success ($pname): $PGProcessedCount of $PGInfoCount"
					}else{
						$PGFailedCount ++
						Write-Debug "`t`t`t`tProcess ObjScope: PG: Process PG Values: Failure ($pname): $PGFailedCount of $PGInfoCount"
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

			$PGPropertiesProcessedCount = 0
			$InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]'Descendents'
			$aces = New-Object System.Collections.Generic.List[System.DirectoryServices.ActiveDirectoryAccessRule]

			if($PGProperties){
				foreach($PGProp in $PGProperties){
					Write-Verbose "`t`t`t`tPGProperty Info"
					Write-Verbose "`t`t`t`t`t`tName`tType"
					Write-Verbose "`t`t`t`t`t`t-----`t-----"
					Write-Verbose "`t`t`t`t`t`t$($PGProp.PropName)`t$($PGProp.PropType)"

					$aceDef = $DelegateSID,($PGProp.ADRights),$accType,($PGProp.ACLTarget),$InheritanceType
					Write-Debug "`t`t`t`t`t`tProcess PGProperties (Pre-ACLScope): aceDef - $($aceDef | Out-String)"
					if($PGProp.ACLScope){
						$aceDef += ($PGProp.ACLScope)
					}
					Write-Debug "`t`t`t`t`t`tProcess PGProperties (Post-ACLScope): aceDef - $($aceDef | Out-String)"
					try {
						$aceObj = New-Object -TypeName System.DirectoryServices.ActiveDirectoryAccessRule($aceDef)
					}
					catch {
						Write-Error -Category InvalidData -CategoryActivity "Create aceObj" -CategoryTargetName "$SourceValue" -Message "Unable to create ACE for aceDef - `n$($aceDef | Out-String)" -ErrorAction Continue
					}

					if($aceObj){
						Write-Debug "`t`t`t`t`t`tProcess PGProperties: aceObj - $($aceObj | Out-String)"
						$aces.Add($aceObj)
						Write-Debug "`t`t`t`t`t`tProcess PGProperties: Process ACE Object: Success"
					}else{
						Write-Debug "`t`t`t`t`t`tProcess PGProperties: Process ACE Object: Failure"
					}
				}
			}
			Write-Verbose "`t`tAces added`t$($aces.count)`n`n"
			#endregion BuildACLElements

			foreach($TarPath in $TargetPaths){
				Write-Verbose "`t`t`t`t`t`tApplying ACEs to $($TarPath.DistinguishedName)"
				$SetAclLoop = 1
				$SetAclCount = $aces.Count
				foreach($ace in $aces){
					Write-Verbose "`t`t`t`t`t`tWriting ACE $SetAclLoop of $SetAclCount"
					$TarPath.psbase.ObjectSecurity.AddAccessRule($ace)
					$TarPath.psbase.CommitChanges()
					$SetAclLoop ++
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