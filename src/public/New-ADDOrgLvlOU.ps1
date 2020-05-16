
function New-ADDOrgLvlOU {
<#
    .SYNOPSIS
        Short description

    .DESCRIPTION
        Long description

	.PARAMETER CreateLevel
        Used to indicate if the entire structure should be deployed, or only up to a specific point. Acceptable values for this parameter are as follows:

            ORG - Deploys only the Organizatinal (all) OU level
            OBJ - Deploys all OU levels, but does not deploy Task Delegation Groups or ACLs
            TDG - Deploys all OU levels and Task Delegation Groups, but does not configure related ACLs
            ALL - Deploys all elements of the structure except placeholder Group Policy Objects (Default)

        If this parameter is not specified, or a value is not provided, the ALL option will be used by default. This parameter only applies when this cmdlet
        is directly invoked. If this cmdlet is invoked via Publish-ADDESAEStructure instead, each element is individually executed for operational efficiency.

	.PARAMETER StartOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path. You should provide the value as a string in
        distinguishedName format (ex. "OU=OUname,DC=MYDOMAIN,DC=NET"). A simple OU name, not in distinguishedName format, can also be used provided it is a root
        level OU. In this scenario, the function will automatically translate the name into distinguishedName format using the domain DN.

        SPECIAL NOTE: If a recognized Focus container is not part of the distinguishedName, the cmdlet uses the specified value as a base and will attempt to
        create the target OUs for each non-Stage focus automatically. If no Focus containers are present in the specified location, then creation will fail.

	.PARAMETER Level1
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path, instead of underneath a Focus OU. This value
        must be the output from the Get-ADOrganizationalUnit cmdlet that is part of the Microsoft ActiveDirectory module.

        SPECIAL NOTE: Using this option in a non-standard location (A Focus OU) may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups
        with the appropriate names as this option is still experimental.

    .PARAMETER ChainRun
        This switch causes objects required for the next stage of execution to be returned to the pipeline for additional scrutinty or action. This switch is
        only intended to be called by internal cmdlets, such as when this cmdlet is invoked by the Publish-ADDESAEStructure cmdlet, or another upstream cmdlet,
        during chained execution.

     .PARAMETER PipelineCount
        This parameter allows the number of objects being passed to this cmdlet via the pipeline to be specified. This value is used when presenting the progress
        indicator during execution. If this value is not provided, the progress window will display the current activity, but cannot indicate the completion
        percent as PowerShell is unable to determine how many objects are pending.

	.PARAMETER TargetOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path. This value must be a DirectoryEntry type object
        using the ADSI type accelerator. Typically this value is only specified internally by the Publish-ADDESAEStructure cmdlet, or another upstream cmdlet,
        during chained execution.

        SPECIAL NOTE: Using this option in a non-standard location (A Focus OU) may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups
        with the appropriate names as this option is still experimental.

   .EXAMPLE
        #TODO: Add at least two examples
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Microsoft.ActiveDirectory.Management.ADOrganizationalUnit
            If the ActiveDirectory module is available, the Get-ADOrganizationalUnit cmdlet can be used to obtain pipeline values for TargetOU, or
            a single OU object can be specified as the value as a named parameter

        System.String
            A simple string can be passed via the pipeline, or as a named parameter, to provide a starting point similar to TargetOU. This value should
            be in DistinguishedName format, though it can also be a simple name provided the target OU is located in the root of the domain

        System.DirectoryServices.DirectoryEntry
            A single DirectoryEntry object, or an array of such objects, can be either passed via the pipeline, or provided as a single value with a named
            parameter

        System.Integer
            A single integer

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry

    .NOTES
        Help Last Updated: 1/22/2020

        Cmdlet Version: 1.0.0 - RC

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
        [ValidateSet("ORG","OBJ","TDG","ALL")]
        [string]$CreateLevel,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$true,Position=0)]
        [string[]]$StartOU,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$false,Position=1,ValueFromPipelineByPropertyName=$true)]
        [string]$Level1,

        [Parameter(ParameterSetName="ManualRun",Mandatory=$false,Position=2,ValueFromPipelineByPropertyName=$true)]
        [string]$Level1Display,

        [Parameter(ParameterSetName="ChainRun")]
        [int]$PipelineCount,

        [Parameter(ParameterSetName="ChainRun",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.DirectoryServices.DirectoryEntry]$TargetDE,

        [Parameter(DontShow,ParameterSetName="ChainRun")]
        [Switch]$MTRun
    )

    DynamicParam {
        if($Level1 -and ($MaxLevel -gt 1)){
            $RuntimeParamDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

            switch ($MaxLevel) {
                {$_ -ge 2} {
                    $L2AttributeCollection = New-Object System.Collections.ObjectModel.Collection(System.Attribute)
                    $L2Attribute = New-Object System.Management.Automation.ParameterAttribute
                    $L2Attribute.Mandatory = $true
                    $L2Attribute.Position = 3
                    $L2Attribute.ValueFromPipelineByPropertyName = $true
                    $L2Attribute.ParameterSetName = "ManualRun"
                    $L2AttributeCollection.Add($L2Attribute)

                    if($MaxLevel -eq 2){
                        $L2RuntimeParam = New-Object System.Management.Automation.Ru ntimeDefinedParameter("Level2", [string[]], $L2AttributeCollection)
                    }else {
                        $L2RuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("Level2", [string], $L2AttributeCollection)
                    }

                    $RuntimeParamDictionary.Add("Level2", $L2RuntimeParam)

                    $L2DispAttributeCollection = New-Object System.Collections.ObjectModel.Collection(System.Attribute)
                    $L2DispAttribute = New-Object System.Management.Automation.ParameterAttribute
                    $L2DispAttribute.Mandatory = $false
                    $L2DispAttribute.Position = 4
                    $L2DispAttribute.ValueFromPipelineByPropertyName = $true
                    $L2DispAttribute.ParameterSetName = "ManualRun"
                    $L2DispAttributeCollection.Add($L2DispAttribute)

                    if($MaxLevel -eq 2){
                        $L2DispRuntimeParam = New-Object System.Management.Automation.Ru ntimeDefinedParameter("Level2Display", [string[]], $L2DispAttributeCollection)
                    }else {
                        $L2DispRuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("Level2Display", [string], $L2DispAttributeCollection)
                    }

                }
                {$_ -eq 3} {
                    $L3AttributeCollection = New-Object System.Collections.ObjectModel.Collection(System.Attribute)
                    $L3Attribute = New-Object System.Management.Automation.ParameterAttribute
                    $L3Attribute.Mandatory = $true
                    $L3Attribute.Position = 5
                    $L3Attribute.ValueFromPipelineByPropertyName = $true
                    $L3Attribute.ParameterSetName = "ManualRun"
                    $L3AttributeCollection.Add($L3Attribute)

                    $L3RuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("Level3", [string[]], $L3AttributeCollection)

                    $RuntimeParamDictionary.Add("Level3", $L3RuntimeParam)

                    $L3DispAttributeCollection = New-Object System.Collections.ObjectModel.Collection(System.Attribute)
                    $L3DispAttribute = New-Object System.Management.Automation.ParameterAttribute
                    $L3DispAttribute.Mandatory = $false
                    $L3DispAttribute.Position = 6
                    $L3DispAttribute.ValueFromPipelineByPropertyName = $true
                    $L3DispAttribute.ParameterSetName = "ManualRun"
                    $L3DispAttributeCollection.Add($L3DispAttribute)

                    $L3RuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter("Level3Display", [string[]], $L3DispAttributeCollection)

                    $RuntimeParamDictionary.Add("Level3Display", $L3DispRuntimeParam)
                }
            }

            return $RuntimeParamDictionary
        }
    }

    begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        Write-Verbose "$($LPB1)Run Type:`t$($pscmdlet.ParameterSetName)"
        Write-Verbose "$($LPB1)Setting supplemental run values..."

        #TODO: Update WhatIf processing support to match New-ADDTopLvlOU cmdlet
        # Adjust initialization based on detected parameter set name
        if($pscmdlet.ParameterSetName -like "ManualRun"){
            # Shortcut for Parameter Set detection for later processing
            $ChainRun = $false

            # Allow execution to be manually called but still use org definitions from DB
            if($Level1){
                $UpdateDBChoice = Prompt-Options -PromptInfo @("Update DB Option","Do you want to update the Org table of the local DB instance with any new values?") -Options "Yes","No","Quit"
                switch ($UpdateDBChoice) {
                    0 { $WriteDB = $true
                        Write-Host "Updates will be written back to the local DB if not currently present. Local DB should be redistributed to all module users."
                    }
                    1 { $WriteDB = $false
                        Write-Host "Values will not be checked against DB, and new values will not be written back. Redeploying the full structure will not include these new Org OUs."
                    }
                    2 { Write-Verbose "`t`tDomChoice:`tQuit"
                        break
                    }
                }
            }else {
                $AutoOrg = $true
            }

            # Determine if we will auto-call the next logical function with output from this run
            ## ORG causes function to dump output to base pipeline - can be used for manual chaining or further processing
            ## OBJ auto-calls Object type creation process
            ## TDG causes OBJ creation process to be called with auto-call to TDG
            ## Default ensures that OBJ creation is called with auto-call to TDG and Rights in sequence
            switch ($CreateLevel) {
                "TDG" {$CreateVal = 3}
                "OBJ" {$CreateVal = 2}
                "ORG" {$CreateVal = 1}
                Default {$CreateVal = 4}
            }

            Write-Verbose "$($LPB2)CreateVal:`t$CreateVal"
        }else {
            # Shortcut for Parameter Set detection for later processing
            $ChainRun = $true
        }

        if($pscmdlet.MyInvocation.ExpectingInput -or $ChainRun){
            Write-Verbose "Pipeline:`tDetected"
            $Pipe = $true

            # Create variable value hashes for splatting of Write-Progress values
            # based on whether multi-threading is in use or not
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

            Write-Progress @ProgParams -Activity "Creating Org OUs" -CurrentOperation "Initializing..."

		}

        # Create placeholder collections for storing run output to pass to pipeline
        ## First stores real objects from actual run, second stores fakes for WhatIf run
        ## Two are required because list is specific to an object type, and we won't have a DirectoryEntry object from WhatIf
        $FinalOrgOUObjs = New-Object System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]
        $WFFinalOrgOUObjs = New-Object System.Collections.Generic.List[psobject]

        # Used for pipeline processing specific to this function
        $TotalOrgItems = $OUOrg.Count   # Pulled from PostLoad values
        $OrgProcessedCount = 0          # Number of OUs successfully created

        # Set module standard placeholders for loop processing and tracking - Some may not be used
        $ProcessedCount = 0         # Total objects processed by Process block
        $FailedCount = 0            # Number of OUs failed
        $ExistingCount = 0          # Number of OUs already present
        $NewCount = 0               # Count of new versus existing
        $GCloopCount = 1            # Garbage Collection loop counter
        $loopCount = 1              # General Process loop counter - usually same as ProcessedCount
        $subloopCount = 1           # Used to track a sub-loop if required

        $loopTimer = [System.Diagnostics.Stopwatch]::new()      # Stopwatch for tracking execution time of main loop
        $subloopTimer = [System.Diagnostics.Stopwatch]::new()   # Stopwatch for tracking execution time of sub-loop
        $loopTimes = @()                                        # Placeholder array for storing all stopwatch output

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

        # Write-Progress called only if active pipeline detected
        if($Pipe){
            Write-Progress @ProgParams -Activity "Creating Org OUs" -CurrentOperation "Processing..."
        }

        #region DetectInputType
		# Start process run by detecting the input object type so we can handle it properly
        Write-Verbose "$($LPP2)Detect input type details"
        Write-Verbose ""
		if($ChainRun){
			Write-Verbose "$($LPP3)Input Type:`tPipeline"
			$TargetItem = $_
		}else {
            Write-Verbose "$($LPP3)Input Type:`tStartOU (single item)"
            if($StartOU -match $OUdnRegEx){
                $TargetItem = $StartOU
            }else {
                $TargetItem = "OU=$StartOU,$DomDN"
            }
		}

		Write-Verbose ""
        try {
            $TargetType = ($TargetItem.GetType()).name
            Write-Verbose "$($LPP3)Target Value:`t$TargetItem"
            Write-Verbose "$($LPP3)Target Type:`t$TargetType"
        }
        catch {
            Write-Error "Unable to determine target type from value provided - Skipping"
            break
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
						Write-Error "The specified object ($TargetItem) is not in distinguishedName format - Skipping"
						$FailedCount ++
						break
					}
				}
			}
        }

        Write-Verbose ""
        Write-Verbose "$($LPP2)DEPath:`t$DEPath"

        if([adsi]::Exists($DEPath)) {
            Write-Verbose "$($LPP3)Status:`tExists"
            try {
                $TargetDEObj = New-Object System.DirectoryServices.DirectoryEntry($DEPath)
                $TargetOUDN = $TargetDEObj.DistinguishedName
                Write-Verbose "$($LPP3)DE Binding:`tSuccess"
            }
            catch {
                Write-Verbose "$($LPP3)DE Binding:`tFailed"
                Write-Error "$($LPP3)Failed to bind to path ($DEPath) - Skipping"
                $FailedCount ++
                break
            }

        }else {
            Write-Verbose "$($LPP3)Status:`tDoes Not Exist"
            Write-Error "The specified OU ($TargetItem) wasn't found in the domain - Skipping"
            $FailedCount ++
            break
        }
        #endregion DetectInputType

        if($ProcessedCount -gt 1){
            $PercentComplete = ($ProcessedCount / $PipelineCount) * 100
        }else{
            $PercentComplete = 0
        }

        if($Pipe){
            Write-Progress @ProgParams -Activity "Creating Org OUs" -CurrentOperation "Processing $DEPath" -PercentComplete $PercentComplete
        }

        $DNFocusID = ($TargetOUDN | Select-String -Pattern $($FocusDNRegEx -join "|")).Matches.Value

        if($DNFocusID){
            $FocusID = ($DNFocusID -split "=")[1]
            Write-Verbose "$($LPP3)Derived FocusID:`t$FocusID"

            if($FocusID -match $FocusHash["Stage"]){
                if($pscmdlet.ParameterSetName -like "ManualRun"){
                    Write-Warning "$($LPP3)Organizational OUs are not created in the Staging focus - Skipping"
                }else{
                    Write-Verbose "$($LPP3)Staging Focus - Skipping"
                }

                break
            }

            # Indicator of single or multiple focus - false if single focus provided via path
            $mfocus = $false
        }else{
            $mfocus = $true
        }

        # Output object array placeholders
        #TODO: Replace array with list collection
        $OrgL1OBJs = @()
        $OrgL2OBJs = @()
        $OrgL3OBJs = @()

        # Use MaxLevel value (set in PostLoad) to determine which variables should have data and prep for use
        switch ($MaxLevel) {
            {$_ -ge 1} {
                if($ChainRun -or $AutoOrg){
                    $OrgLvl1Items = $OUOrg | Where-Object{$_.OU_orglvl -eq 1}

                    if($OrgLvl1Items){
                        $TotalOrg1Items = $OrgLvl1Items.Count
                        $Org1ItemsProcessed = 0
                    }else {
                        Write-Error "$MaxLevel Org levels expected, but no level 1 org definitions available - Quitting" -ErrorAction Stop
                    }
                }else {
                    if($Level1){
                        if(!($Level1Display)){
                            $Level1Display = $Level1
                        }

                        $NewL1Obj = [PSCustomObject]@{
                            OU_Name = $Level1
                            OU_friendlyname = $Level1Display
                        }

                        $OrgLvl1Items = $NewL1Obj
                    }else {
                        Write-Error "$MaxLevel Org levels expected, but no level 1 org definitions available - Quitting" -ErrorAction Stop
                    }
                }
            }

            {$_ -ge 2} {
                if($ChainRun -or $AutoOrg){
                    $AllOrgLvl2Items = $OUOrg | Where-Object{$_.OU_orglvl -eq 2}

                    if($AllOrgLvl2Items){
                        $TotalOrg2Items = $AllOrgLvl2Items.Count
                        $Org2ItemsProcessed = 0
                    }else {
                        Write-Error "$MaxLevel Org levels expected, but no level 2 org definitions available - Quitting" -ErrorAction Stop
                    }
                }else {
                    $AllOrgLvl2Items = @()

                    if($Level2){
                        for($i = 0; $i -lt ($Level2.Count - 1); $i++){
                            if($Level2Display[$i]){
                                $L2Display = $Level2Display[$i]
                            }else {
                                $L2Display = $Level2
                            }

                            $NewL2Obj = [PSCustomObject]@{
                                OU_Name = $Level2[$i]
                                OU_friendlyname = $L2Display
                            }

                            $AllOrgLvl2Items += $NewL2Obj
                        }else {
                            Write-Error "$MaxLevel Org levels expected, but no level 2 org definitions available - Quitting" -ErrorAction Stop
                        }
                    }
                }
            }

            {$_ -eq 3} {
                if($ChainRun -or $AutoOrg){
                    $AllOrgLvl3Items = $OUOrg | Where-Object{$_.OU_orglvl -eq 3}
                    if($AllOrgLvl3Items){
                        $TotalOrg3Items = $AllOrgLvl3Items.Count
                        $Org3ItemsProcessed = 0
                    }else {
                        Write-Error "$MaxLevel Org levels expected, but no level 3 org definitions available - Quitting" -ErrorAction Stop
                    }
                }else {
                    $AllOrgLvl3Items = @()

                    if($Level3){
                        for($i = 0; $i -lt ($Level3.Count - 1); $i++){
                            if($Level3Display[$i]){
                                $L3Display = $Level3Display[$i]
                            }else {
                                $L3Display = $Level3
                            }

                            $NewL3Obj = [PSCustomObject]@{
                                OU_Name = $Level3[$i]
                                OU_friendlyname = $L3Display
                            }

                            $AllOrgLvl3Items += $NewL3Obj
                        }
                    }else {
                        Write-Error "$MaxLevel Org levels expected, but no level 3 org definitions available - Quitting" -ErrorAction Stop
                    }
                }
            }
        }

        Write-Verbose "`t`t`t`tL1 Orgs Staged for Create:`t$($TotalOrg1Items)"
        Write-Verbose ""

        if($OrgLvl1Items){
            foreach($OrgLvl in $OrgLvl1Items){

                if($Pipe){
                    if($Org1ItemsProcessed -gt 1){
                        $Org1PercentComplete = ($Org1ItemsProcessed / $TotalOrg1Items) * 100
                    }else{
                        $Org1PercentComplete = 0
                    }

                    Write-Progress -Id $($ProgParams.Id + 5) -Activity "Deploying" -CurrentOperation "Level 1 Org OUs..." -PercentComplete $Org1PercentComplete -ParentId $($ProgParams.ParentId + 5)
                }

                $Org1OUName = $OrgLvl.OU_name
                $Org1OUDisplayName = $OrgLvl.OU_friendlyname
                Write-Verbose "`t`t`t`tProcessing Lvl1 Org:`t$Org1OUName"
                Write-Verbose "`t`t`t`t`tFriendly Name:`t$Org1OUDisplayName"
                Write-Verbose ""

                if($ChainRun){
                    $Org1DBid = $OrgLvl.OU_id
                    Write-Verbose "`t`t`t`t`tDB Id:`t$Org1DBID"
                    Write-Verbose ""

                    if($GCL1loopCount -eq 20){
                        Run-MemClean
                        $GCL1loopCount = 0
                    }
                }

                $CrOrg1Objs = @()

                if($mfocus){
                    # Get all non-Stage focus names
                    $FocusNames = $FocusHash.Values | Where-Object {$_ -notmatch $FocusHash["Stage"]}

                    # Create the specified OU for each non-Stage focus container under the specified StartOU
                    foreach($Focus in $FocusNames){
                        $ParentDN = "OU=$Focus,$StartOU"
                        Write-Verbose "`t`tCreating Org OU"
                        $OrgObj = New-ADDADObject -ObjName $Org1OUName -ObjDescription $Org1OUDisplayName -ObjParentDN $ParentDN

                        if($OrgObj){
                            $CrOrg1Objs += $OrgObj
                        }else {
                            $FailedCount ++
                            Write-Verbose "`t`t`t`tOutcome:`tFailed"
                            Write-Verbose "`t`t`t`tFail Reason:`tNo value returned from CreateOrgOU"
                        }
                    }
                }else {
                    Write-Verbose "`t`tCreating Org OU"
                    $OrgObj = New-ADDADObject -ObjName $Org1OUName -ObjDescription $Org1OUDisplayName -ObjParentDN $TargetDEObj.distinguishedName

                    if($OrgObj){
                        $CrOrg1Objs += $OrgObj
                    }else {
                        $FailedCount ++
                        Write-Verbose "`t`t`t`tOutcome:`tFailed"
                        Write-Verbose "`t`t`t`tFail Reason:`tNo value returned from CreateOrgOU"
                    }
                }

                if($CrOrg1Objs){
                    foreach($Org1Obj in $CrOrg1Objs){
                        switch ($Org1Obj.State) {
                            {$_ -like "New"} {
                                $NewCount ++
                            }

                            {$_ -like "Existing"} {
                                $ExistingCount ++
                            }

                            Default {
                                $FailedCount ++
                                Write-Verbose "`t`t`t`tOutcome:`tFailed"
                                Write-Verbose "`t`t`t`tFail Reason:`t$($Org1Obj.State)"
                            }
                        }

                        if($MaxLevel -eq 1){
                            $FinalOrgOUObjs.Add($Org1Obj.DEObj)
                        }else {
                            if($ChainRun){
                                $Org1Out = [PSCustomObject]@{
                                    OrgDN = $Org1Obj.DEObj
                                    OrgID = $Org1DBid
                                }
                            }else {
                                $Org1OUName = [PSCustomObject]@{
                                    OrgDN = $Org1Obj.DEObj
                                }
                            }

                            $OrgL1OBJs += $Org1Out
                        }
                        $Org1ItemsProcessed ++
                        $GCL1loopCount ++
                    }
                }
            }
        }else {
            Write-Verbose "`t`t`t`tOutcome:`tFailed"
            Write-Error "`t`t`t`tMaxLevel is $MaxLevel, but no level $MaxLevel Org data available - Quitting" -ErrorAction Continue
            break
        }

        foreach($L1Obj in $OrgL1OBJs){
            $L1ParentPath = $L1Obj.OrgDN

            if($ChainRun){
                $L1ParentDBid = $L1Obj.OrgID

                $OrgLvl2Items = $OUOrg | Where-Object{$_.OU_orglvl -eq 2 -and $_.OU_parent -eq $L1ParentDBid}
            }else {
                $OrgLvl2Items = $AllOrgLvl2Items
            }

            Write-Verbose "`t`t`t`tL1 Org Path:`t$($L1ParentPath.DistinguishedName)"
            Write-Verbose "`t`t`t`tL2 Children Staged:`t$($OrgLvl2Items.Count)"
            Write-Verbose ""

            if($OrgLvl2Items){
                foreach($OrgLvl in $OrgLvl2Items){
                    if($Org2ItemsProcessed -gt 1){
                        $Org2PercentComplete = ($Org2ItemsProcessed / $TotalOrg2Items) * 100
                    }else{
                        $Org2PercentComplete = 0
                    }

                    if($Pipe){
                        Write-Progress -Id 26 -Activity "Deploying" -CurrentOperation "Level 2 Org OUs..." -PercentComplete $Org2PercentComplete -ParentId 20
                    }

                    $Org2OUName = $OrgLvl.OU_name
                    $Org2OUDisplayName = $OrgLvl.OU_friendlyname
                    Write-Verbose "`t`t`t`tProcessing Lvl1 Org:`t$Org2OUName"
                    Write-Verbose "`t`t`t`t`tFriendly Name:`t$Org2OUDisplayName"
                    Write-Verbose ""

                    if($ChainRun){
                        $Org2DBid = $OrgLvl.OU_id
                        Write-Verbose "`t`t`t`t`tDB Id:`t$Org2DBID"
                        Write-Verbose ""
                    }

                    Write-Verbose "`t`tCreating Org OU"

                    # Enforced .NET garbage collection to ensure memory utilization does not balloon
                    if($GCL2loopCount -eq 30){
                        Run-MemClean
                        $GCL2loopCount = 0
                    }

                    $Org2Obj = New-ADDADObject -ObjName $Org2OUName -ObjDescription $Org2OUDisplayName -ObjParentDN $L1ParentPath.DistinguishedName

                    if($Org2Obj){
                        switch ($Org2Obj.State) {
                            {$_ -like "New"} {
                                $NewCount ++
                            }

                            {$_ -like "Existing"} {
                                $ExistingCount ++
                            }

                            Default {
                                $FailedCount ++
                                Write-Verbose "`t`t`t`tOutcome:`tFailed"
                                Write-Verbose "`t`t`t`tFail Reason:`t$($Org2Obj.State)"
                            }
                        }

                        if($MaxLevel -eq 2){
                            $FinalOrgOUObjs.Add($Org2Obj.DEObj)
                        }else {
                            if($ChainRun){
                                $Org2Out = [PSCustomObject]@{
                                    OrgDN = $Org2Obj.DEObj
                                    OrgID = $Org2DBid
                                }
                            }else {
                                $Org2OUName = [PSCustomObject]@{
                                    OrgDN = $Org2Obj.DEObj
                                }
                            }

                            $OrgL2OBJs += $Org2Out
                        }

                    }else {
                        $FailedCount ++
                        Write-Verbose "`t`t`t`tOutcome:`tFailed"
                        Write-Verbose "`t`t`t`tFail Reason:`tNo value returned from CreateOrgOU"
                    }

                    $Org2ItemsProcessed ++
                    $GCL2loopCount ++
                }

            }else {
                Write-Verbose "`t`t`t`tOutcome:`tFailed"
                Write-Error "`t`t`t`tMaxLevel is $MaxLevel, but no level $MaxLevel Org data available - Quitting" -ErrorAction Continue
                break
            }

        }

        Write-Progress -Id 25 -Activity "Deploying" -CurrentOperation "L1 Finished" -Completed -ParentId 20

        if($OrgL2OBJs){
            foreach($L2Obj in $OrgL2OBJs){
                $L2ParentPath = $L2Obj.OrgDN

                if($ChainRun){
                    $L2ParentDBid = $L2Obj.OrgID

                    $OrgLvl3Items = $OUOrg | Where-Object{$_.OU_orglvl -eq 3 -and $_.OU_parent -eq $L2ParentDBid}
                }

                Write-Verbose "`t`t`t`tL2 Org Path:`t$($L2ParentPath.DistinguishedName)"
                Write-Verbose "`t`t`t`tL3 Children Staged:`t$($OrgLvl3Items.Count)"
                Write-Verbose ""

                if($OrgLvl3Items){
                    foreach($OrgLvl in $OrgLvl3Items){
                        if($Org3ItemsProcessed -gt 1){
                            $Org3PercentComplete = ($Org3ItemsProcessed / $TotalOrg3Items) * 100
                        }else{
                            $Org3PercentComplete = 0
                        }

                        if($Pipe){
                            Write-Progress -Id 27 -Activity "Deploying" -CurrentOperation "Level 3 Org OUs..." -PercentComplete $Org3PercentComplete -ParentId 20
                        }


                        $Org3OUName = $OrgLvl.OU_name
                        $Org3OUDisplayName = $OrgLvl.OU_friendlyname
                        Write-Verbose "`t`t`t`tProcessing Lvl1 Org:`t$Org3OUName"
                        Write-Verbose "`t`t`t`t`tFriendly Name:`t$Org3OUDisplayName"
                        Write-Verbose "`t`t`t`t`tDB Id:`t$Org3DBID"

                        if($ChainRun){
                            $Org3DBid = $OrgLvl.OU_id
                            Write-Verbose "`t`t`t`t`tDB Id:`t$Org3DBID"
                            Write-Verbose ""
                        }

                        Write-Verbose "`t`tCreating Org OU"

                        # Enforced .NET garbage collection to ensure memory utilization does not balloon
                        if($GCL3loopCount -eq 30){
                            Run-MemClean
                            $GCL3loopCount = 0
                        }

                        $Org3Obj = New-ADDADObject -ObjName $Org3OUName -ObjDescription $Org3OUDisplayName -ObjParentDN $L2ParentPath.DistinguishedName

                        if($Org3Obj){
                            $FinalOrgOUObjs.Add($Org3Obj.DEObj)

                            switch ($Org3Obj.State) {
                                {$_ -like "New"} {
                                    $NewCount ++
                                }

                                {$_ -like "Existing"} {
                                    $ExistingCount ++
                                }

                                Default {
                                    $FailedCount ++
                                    Write-Verbose "`t`t`t`tOutcome:`tFailed"
                                    Write-Verbose "`t`t`t`tFail Reason:`t$($Org3Obj.State)"
                                }
                            }

                        }else {
                            $FailedCount ++
                            Write-Verbose "`t`t`t`tOutcome:`tFailed"
                            Write-Verbose "`t`t`t`tFail Reason:`tNo value returned from New-ADDADObject"
                        }

                        $Org3ItemsProcessed ++
                        $GCL3loopCount ++
                    }

                    Write-Progress -Id 27 -Activity "Deploying" -CurrentOperation "L3 Finished" -Completed -ParentId 20
                }else {
                    Write-Verbose "`t`t`t`tOutcome:`tFailed"
                    Write-Error "`t`t`t`tMaxLevel is $MaxLevel, but no level $MaxLevel Org data available - Quitting" -ErrorAction Continue
                    break
                }

            }

            if($Pipe){
                Write-Progress -Id 26 -Activity "Deploying" -CurrentOperation "L2 Finished" -Completed -ParentId 20
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
        $TotalOrgProcessed = $Org1ItemsProcessed + $Org2ItemsProcessed + $Org3ItemsProcessed
        Write-Verbose ""
        Write-Verbose ""
        Write-Verbose "Wrapping Up"
        Write-Verbose "`t`tSource Paths Procesed:`t$ProcessedCount"
        Write-Verbose "`t`tOrg OUs Processed:`t$TotalOrgProcessed"
        Write-Verbose "`t`tNew Org OUs Created:`t$NewCount"
        Write-Verbose "`t`tPre-Existing Org OUs:`t$ExistingCount"
        Write-Verbose "`t`tFailed Org OUs:`t$FailedCount"
        Write-Verbose ""
        Write-Verbose ""

        if($Pipe){
            Write-Progress -Id 25 -Activity "Deploying" -CurrentOperation "Finished" -Completed -ParentId 20
            Write-Progress -Id 20 -Activity "Creating OUs" -CurrentOperation "Finished" -Completed -ParentId 10
        }

        if($CreateVal -gt 1) {
            Write-Verbose "$($LPB1)Manual Run and CreateVal greater than 1 - Passing results to New-ADDOrgLvlOU"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            $FinalOrgOUObjs | New-ADDObjLvlOU -PipelineCount $($FinalFocusLevelOUs.Count)
        }else {
            Write-Verbose "$($LPB1)Chain Run or CreateVal of 1 - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Verbose ""
            Write-Verbose ""
            return $FinalOrgOUObjs
        }
    }
}