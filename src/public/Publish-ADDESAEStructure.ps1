function Publish-ADDESAEStructure {
<#
    .SYNOPSIS
        Deploys one or more levels of the ESAE OU structure, and various dependent componets, to a target Active Directory environment.

    .DESCRIPTION
        This cmdlet uses information from the embedded sqlite database to generate one or more levels of an OU structure within the 'Orange/Gold' or
        'production' AD forest for an Enhanced Security Administration Model (Red Forest) implemenation. The cmdlet provides the ability to deploy
        the structure at one or more levels, but cannot perform more selective deployment.

        To perform selective deployment, run the individual 'New-' cmdlets that support ad-hoc deployment as desired

	.PARAMETER CreateLevel
        Used to indicate if the entire structure should be deployed, or only up to a specific point. Acceptable values for this parameter are as follows:

            FOC - Deploys only the Tier and Focus OU levels
            ORG - Deploys only the Tier, Focus, and Organizatinal (all) OU levels
            OBJ - Deploys all OU levels, but does not deploy Task Delegation Groups or ACLs
            TDG - Deploys all OU levels and Task Delegation Groups, but does not configure related ACLs
            ALL - Deploys all elements of the structure except placeholder Group Policy Objects (Default)

        If this parameter is not specified, or a value is not provided, the ALL option will be used by default.

	.PARAMETER CreateGPOPlaceholders
        Optional parameter that will cause placeholder GPOs to be automatically generated for each Tier, Focus, and Organizational level container. All GPOs
        will leverage an abbreviated naming convention that directly relates to the OU to which the GPO belongs, similar to that used for Task Delegation Groups.
        Two GPOs will be generated for each OU; one for User settings, and one for Computer settings. All generated GPOs will be automatically attached to
        the related OU. If a GPO of the same name already exists, the existing GPO will be linked to the OU instead of generating a placeholder.

	.PARAMETER MultiThread
        Using this switch will cause some cmdlets to be executed with parallel processing using PowerShell Runspaces and the SplitPipeline plugin module. Note
        that, while use of this switch should substantially speed up deployments for complex or large scale deployments, speed gains will be minimal at best
        in smaller deployments. In addition, use of multi-threading will effect the logging functionality of this module, so use of this switch in smaller
        environments is not recommended.

	.PARAMETER Credential
        (Not yet implemented) Allows user to provide alternate credentials to run the process under. When specifying a value for this parameter, you must use
        'domain\username' format.

        Note: This is a required value if specifying an alternate target domain.

	.PARAMETER TargetDomain
        (Not yet implemented) Allows user to specify an alternate domain to connect to in distinguishedName format (ex. DC=MYDOMAIN,DC=NET).

        Note: When specifying a value for this parameter, you must also specify credentials.

	.PARAMETER StartOU
        Specifying this value allows the new OU structure elements to be deployed underneath an existing OU path, instead of at the root of
        the domain. You must provide the value as a string in distinguishedName format (ex. "OU=OUname,DC=MYDOMAIN,DC=NET").

        SPECIAL NOTE: Using this option may currently cause the New-ADDTaskGroup cmdlet to fail to generate all groups with the appropriate names as this option
        is still experimental.

        Note that you cannot use both the TargetDomain and TargetOU parameters together. Instead, the domain value is obtained from the value provided to the
        TargetOU parameter and compared against the domain to which the system running the command is joined. If there is a mismatch, and a value was not provided
        for the Credential parameter, execution will fail.

    .EXAMPLE
        PS C:\> Publish-ADDESAEStructure

        Deploys all elements of the structure, with the exception of the GPO placeholders, in a single-threaded linear manner. The structure will be deployed to the
        root level of the domain to which the system running the cmdlet is joined.

    .EXAMPLE
        PS C:\> Publish-ADDESAEStructure -CreateGPOPlaceholders -MultiThread

        Deploys all elements of the structure, including the GPO placeholders, using parallel processing for some cmdlet calls to decrease total deployment time. The
        structure will be deployed to the root level of the domain to which the system running the cmdlet is joined.

    .EXAMPLE
        PS C:\> Publish-ADDESAEStructure -CreateLevel ORG -StartOU "OU=SOMEOU,DC=MYDOMAIN,DC=NET"

        Deploys the Tier, Focus, and organizational level OUs only, but underneath the OU named 'SOMEOU' instead of at the root of the domain.

    .NOTES
        Help Last Updated: 10/18/2019

        Cmdlet Version 0.9.0 - Beta

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
#>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
    Param(
        [Parameter(ParameterSetName="ChainRun")]
        [Parameter(ParameterSetName="AltDomain")]
        [Parameter(ParameterSetName="AltCredential")]
        [ValidateSet("FOC","ORG","OBJ","TDG","ALL")]
        [string]$CreateLevel,

        [Parameter(ParameterSetName="ChainRun")]
        [Parameter(ParameterSetName="AltDomain")]
        [Parameter(ParameterSetName="AltCredential")]
        [switch]
        $CreateGPOPlaceholders,

        [Parameter(ParameterSetName="ChainRun")]
        [Parameter(ParameterSetName="AltCredential")]
        [string]$StartOU,

        [Parameter(ParameterSetName="ChainRun")]
        [Parameter(ParameterSetName="AltDomain")]
        [Parameter(ParameterSetName="AltCredential")]
        [switch]
        $MultiThread,

        [Parameter(ParameterSetName="ChainRun")]
        [Parameter(ParameterSetName="AltDomain")]
        [Parameter(ParameterSetName="AltCredential")]
        [int]
        $MTMultiplier = 3,

        [Parameter(Mandatory=$true,ParameterSetName="AltDomain")]
        [Parameter(Mandatory=$false,ParameterSetName="AltCredential")]
        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(Mandatory=$true,ParameterSetName="AltDomain")]
        [String[]]
        $TargetDomain
    )

    Begin {
		$FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        if(!($WhatIfPreference)){
            Write-Verbose ""
            Write-Verbose "+++ WhatIf Detected - All activities will be logged, but not executed +++"
            Write-Verbose ""
        }

        if($CreateLevel){
            Write-Verbose "`tCreateLevel Specified - Setting CreateVal"
            switch ($CreateLevel) {
                "TDG" {$CreateVal = 4}
                "OBJ" {$CreateVal = 3}
                "ORG" {$CreateVal = 2}
                "FOC" {$CreateVal = 1}
                Default {$CreateVal = 5}
            }

            Write-Verbose "`tCreateVal:`t$CreateVal"
            if($CreateVal -gt 1){
                $steps = $CreateVal
            }
        }else {
            $steps = 5
        }

        Write-Verbose "`tSteps:`t$Steps"
        Write-Verbose "`tMultiThread:`t$MultiThread"

        if($MultiThread){
            $MultiThreadPrompt = Prompt-Options -PromptInfo @("Multi-Thread Run Warning","While multi-threading speeds up execution, it also causes log data to be written out of sequence, which may make troubleshooting issues more difficult. Please confirm your selection.") -Options "Continue Multi-Threaded","Skip Multi-Threading","Quit"
            switch ($MultiThreadPrompt) {
                0 {
                    Write-Verbose "`t`tMultiThread Confirmed:`tYes"
                }
                1 {
                    Write-Verbose "`t`tMultiThread Confirmed:`tNo - Disabling"
                    $MultiThread = $false
                }
                2 {
                    Write-Verbose "`t`tMultiThread Confirmed:`tQuit - Exiting"
                    break
                }
            }

			if($MTMultiplier -gt 4){
				$MTMultPrompt = Prompt-Options -PromptInfo @("Multi-Thread Multiplier Warning","This option specifies the multiplier used to determine the number of threads based on CPU count, which substantically increases the memory and CPU utilization on the host where it is being run. Please confirm your selection.") -Options "Proceed","Change Value","Quit"

				switch ($MTMultPrompt) {
					0 {
						Write-Verbose "`t`tMultiplier Confirmed:`tYes"
					}

					1 {
						Write-Verbose "`t`tMultiplier Confirmed:`tNo - Change Value"
						[int]$MTMultiplier = Read-Host "Please specify a new numeric value to use."
					}

					2 {
						Write-Verbose "`t`tMultiplier Confirmed:`tQuit - Exiting"
						break
					}
				}
			}else{
				[int]$MTcount = ((Get-WMIObject Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum) * $MTMultiplier
			}

			$MTParams = @{
				Module = "ADDeploy"
				ApartmentState = "MTA"
				Count = $MTCount
			}
        }

        Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 0 of $steps"

        if($StartOU){
            Write-Verbose "`tStartOU Specified:`t$StartOU"
            if($StartOU -match $OUdnRegEx){
                Write-Verbose "`t`tIs DistinguisheName:`t$true"
                if($([adsi]::Exists("LDAP://$StartOU"))){
                    Write-Verbose "`t`tPath Exists:`t$true"
                    $StartOUDN = $StartOU
                }else {
                    Write-Verbose "`t`tPath Exists:`t$false"
                    Write-Error "`t`tThe specified StartOU is in DistinguishedName format, but the indicated path does not exist. Please check the path and try again - Quitting" -ErrorAction Stop
                }
            }else {
                Write-Verbose "`t`tIs DistinguisheName:`t$false"
                $StartOULDAP = "LDAP://OU=$StartOU,$DomDN"
                Write-Verbose "`t`tTest Path:`t$StartOULDAP"
                if($([adsi]::Exists("$StartOULDAP"))){
                    Write-Verbose "`t`tPath Exists:`t$true"
                    $StartOUDN = $StartOULDAP
                }else {
                    Write-Verbose "`t`tPath Exists:`t$false"
                    Write-Error "`t`tThe specified StartOU does not exist in the root of the domain. Please check the path and try again - Quitting" -ErrorAction Stop
                }
            }
        }

		if($TargetDomain){
            if($Initialized){
                if($TargetDomain -notmatch "$DomName|$($ENV:USERDOMAIN)"){
                    Write-Verbose "`tTargetDomain Mismatch - Prompt for Action"
                    $DomChoice = Prompt-Options -PromptInfo @("Runtime - Domain Mismatch","The specified TargetDomain does not match the last run or the initialized values. Please specify how to proceed.") -Options "Reset and Re-initialize Module","Update and Continue","Quit"
                    switch ($DomChoice) {
                        0 {
                            Write-Verbose "`t`tDomChoice:`tReset and Reinitialize Module"
                            Write-Host "Option 0 selected - Reset and Re-initialize module" -ForegroundColor Yellow
                            $ConfirmResetChoice = Prompt-Options -PromptInfo @("Confirm Reset","Please confirm you wish to reset the module. Warning!! This action cannot be undone!") -Options "Yes - Reset Module","No - Cancel Reset" -default 1
                            #TODO: Add code for resetting module preferences
                            if($ConfirmResetChoice -eq 0){
                                Write-Host "Functionality not yet implemented - Please Update DB Directly - Quiting"
                                break
                            }
                        }

                        1 {
                            #TODO: Change option to cross-domain execution - add validation check
                            Write-Verbose "`t`tDomChoice:`tUpdate and Continue"
                            if($TargetDomain -notmatch $DomDNRegEx){
                                #TODO: Update DomDN override code - need to remove global scope variable first before update
                                $DomDN = "DC=$($TargetDomain.replace('.',',DC='))"
                            }else{
                                $DomDN = $TargetDomain
                                $TargetDomain = ($TargetDomain.Replace(',','.')) -replace "DC=",""
                            }

                            Write-Verbose "`t`t`tOld DomName:`t$DomName - Updating:`t$TargetDomain"
                            Export-ADDModuleData -DataSet "SetRunData" -QueryValue "$DomName","$TargetDomain"
                        }

                        2 {
                            Write-Verbose "`t`tDomChoice:`tQuit"
                            break
                        }
                    }
                }
            }

            #TODO: Publish-ADDESAEStructure: Update all cmdlets to handle creds and alternate domain
            $PIParams.Add("Server", $TargetDomain)
            $PIParams.Add("Credential", $Credential)
		}

        $TopProcessed = 0
        $TopFailed = 0
        $FocusProcessed = 0
        $FocusFailed = 0
        $loopCount = 1
        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()

		Write-Verbose ""
    }

    Process {
		Write-Verbose ""
		Write-Verbose "`t****************** Start of loop ($loopCount) ******************"
		Write-Verbose ""
		$loopTimer.Start()

        if($steps -gt 1){
            Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 1a of $steps" -CurrentOperation "Deploying top level OUs..."
        }

        Write-Verbose "`t`tCalling New-ADDTopLvlOU"
        if($StartOUDN){
            $TopLvlOUs = New-ADDTopLvlOU -ChainRun -StartOU $StartOUDN
        }else {
            $TopLvlOUs = New-ADDTopLvlOU -ChainRun
        }

        if($TopLvlOUs){
            Write-Verbose "`t`t`tTask Outcome:`tSuccess"
            Write-Verbose "`t`t`tStaged OU Count:`t$($TopLvlOUs.Count)"
            Write-Debug "`t`t`tTopLvlOU Values"
            Write-Debug "`t`t`t`t$($TopLvlOUs | Out-String -Stream)"
            Write-Verbose ""

            Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 1b of $steps" -CurrentOperation "Deploying Core Components..."
            # Admin focus objects only - Needed to deploy Shared Services elements
            $ADMFocusOUs = $TopLvlOUs | Where-Object {$_.Path -match $FocusHash["Admin"]}

            # Server focus objects only - No object type containers
            $ServerPath = "OU=" + $FocusHash["Server"]
            $SRVFocusOUs = $TopLvlOUs | Where-Object {$_.Path -match $FocusHash["Server"]}

            # Admin and Standard objects - Needed to deploy common elements
            $COMFocusOUs = $TopLvlOUs | Where-Object {$_.Path -match "$($FocusHash["Admin"])|$($FocusHash["Standard"])"}

			$StagePath = "OU=" + $FocusHash["Stage"]
            # Stage focus objects only - No Org containers and unique Object Type
            $STGFocusOUs = $TopLvlOUs | Where-Object {$_.Path -match $StagePath}

            # All non-stage focus objects - Gets all org containers
            $NonStageFocusOUs = $TopLvlOUs | Where-Object {$_.Path -notmatch $StagePath}

			if($MultiThread){
                $data = @{
                    Count = $ADMFocusOUs.Count
                    Done = 0
                }

				$CoreResults = $ADMFocusOUs | Split-Pipeline -Variable data @MTParams -Script { Process {
                    $_ | Install-ADDCoreComponents

                    [System.Threading.Monitor]::Enter($data)
                    try {
                        # Update shared data
                        $done = ++$data.Done
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($data)
                    }

                    if($done -gt 1){
                        $PercentComplete = (($done / $data.Count) * 100)
                    }else {
                        $PercentComplete = 0
                    }

                    Write-Progress -Id 20 -Activity "Core Components" -Status "Deploying..." -PercentComplete $PercentComplete -ParentId 10
                } }
			}else{
				$CoreResults = $ADMFocusOUs | Install-ADDCoreComponents
			}

            if($steps -ge 2){
                Write-Verbose "`t`tCalling New-ADDOrgLvlOU"
                Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 2 of $steps" -CurrentOperation "Deploying Org level OUs..."
                $OrgPipeCount = $NonStageFocusOUs.Count
                Write-Verbose "`t`tSending $OrgPipeCount focus OU objects to New-ADDOrgLvlOU..."
                if($MultiThread){
                    Write-Verbose "`t`t`tMultiThread switch detected - Executing in parallel"
                    $OrgLvlOUs = $NonStageFocusOUs | Split-Pipeline -Script { Process {$_ | New-ADDOrgLvlOU -PipelineCount 0} } @MTParams
                }else {
                    $OrgLvlOUs = $NonStageFocusOUs | New-ADDOrgLvlOU -PipelineCount $OrgPipeCount
                }

                if($OrgLvlOUs){

                    $SrvOrgLvlOUs = $OrgLvlOUs | Where-Object { $_.DistinguishedName -match $ServerPath }

                    $ObjPipe = $OrgLvlOUs
                    $ObjPipeCount = $ObjPipe.Count

                    Write-Verbose "`t`t`t`tStaged OU Count:`t$($ObjPipeCount)"
                    Write-Debug "`t`t`t`tOrgLvlOU Values"
                    Write-Debug "`t`t`t`t`t`t$($ObjPipe | Out-String -Stream)"
                    Write-Verbose ""
                    Write-Verbose ""

                    if($steps -ge 3){
                        Write-Verbose "`t`tCalling New-ADDObjLvlOU"
                        Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 3 of $steps" -CurrentOperation "Deploying Object level OUs..."
                        if($MultiThread){
                            Write-Verbose "`t`t`tMultiThread switch detected - Executing in parallel"
                            $ObjLvlOUs = $ObjPipe |  Split-Pipeline -Script {Process {$_ | New-ADDObjLvlOU -ChainRun -PipelineCount 0 } } @MTParams
                        }else {
                            $ObjLvlOUs = $ObjPipe | New-ADDObjLvlOU -ChainRun -PipelineCount $ObjPipeCount
                        }

                        if($ObjLvlOUs){

                            $TDGPipe = $ObjLvlOUs + $SrvOrgLvlOUs
                            $TDGPipeCount = $TDGPipe.Count
                            Write-Verbose "`t`t`t`tStaged OU Count:`t$($TDGPipeCount)"
                            Write-Debug "`t`t`t`tOrgLvlOU Values"
                            Write-Debug "`t`t`t`t`t`t$($TDGPipe | Out-String -Stream)"
                            Write-Verbose ""
                            Write-Verbose ""

                            if($steps -ge 4){
                                Write-Verbose "`t`tCalling New-ADDTaskGroup"
                                Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 4 of $steps" -CurrentOperation "Deploying Task Delegation Groups..."

                                if($MultiThread){
                                    Write-Verbose "`t`t`tMultiThread switch detected - Executing in parallel"
                                    $TDGResults = $TDGPipe |  Split-Pipeline -Script {Process { $_ | New-ADDTaskGroup -ChainRun -PipelineCount 0 } } @MTParams
                                }else {
                                    $TDGResults = $TDGPipe | New-ADDTaskGroup -ChainRun -PipelineCount $TdgPipeCount
                                }

                                if($TDGResults){

                                    $ACLPipe = $TDGResults
                                    $ACLPipeCount = $ACLPipe.Count
                                    Write-Verbose "`t`t`t`tStaged OU Count:`t$($ACLPipeCount)"
                                    Write-Debug "`t`t`t`tOrgLvlOU Values"
                                    Write-Debug "`t`t`t`t`t`t$($ACLPipe | Out-String -Stream)"
                                    Write-Verbose ""
                                    Write-Verbose ""

                                    if($steps -eq 5){
                                        Write-Verbose "`t`tCalling Grant-ADDTDGRights"
                                        Write-Progress -Id 10 -Activity "$FunctionName" -Status "Deploying ESAE - Step 5 of $steps" -CurrentOperation "Assigning TDG ACLs..."
                                        if($MultiThread){
                                            Write-Verbose "`t`t`tMultiThread switch detected - Executing in parallel"
                                            $ACLResults = $ACLPipe |  Split-Pipeline -Script { Process { $_ | Grant-ADDTDGRights -ChainRun -PipelineCount 0 } } @MTParams
                                        }else {
                                            $ACLResults = $ACLPipe | Grant-ADDTDGRights -ChainRun -PipelineCount $ACLPipeCount
                                        }

                                        if($ACLResults){
                                            Write-Verbose "`t`t`t`tTask Outcome:`tSuccess"
                                        }
                                    }
                                }else{
                                    Write-Verbose "`t`t`t`tTask Outcome:`tFailed"
                                    Write-Error "`t`t`t`tNo results were returned from call to 'New-ADDTaskGroup' - Quitting"
                                    break
                                }
                            }
                        }else{
                            Write-Verbose "`t`t`t`tTask Outcome:`tFailed"
                            Write-Error "`t`t`t`tNo results were returned from call to 'New-ADDObjLvlOU' - Quitting"
                            break
                        }
                    }
                }else{
                    Write-Verbose "`t`t`t`tTask Outcome:`tFailed"
                    Write-Error "`t`t`t`tNo results were returned from call to 'New-ADDOrgLvlOU' - Quitting"
                    break
                }
            }
        }else{
            Write-Verbose "`t`t`t`tTask Outcome:`tFailed"
            Write-Error "`t`t`t`tNo results were returned from call to 'New-ADDTopLvlOU' - Quitting"
            break
        }
        #endregion CreateGlobalContainers



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

    End {
		$FinalLoopTime = [math]::Round(($loopTimes | Measure-Object -Sum).Sum, 0)
		$FinalAvgLoopTime = [math]::Round(($loopTimes | Measure-Object -Average).Average, 0)
		Write-Verbose ""
		Write-Verbose ""
		Write-Verbose "Wrapping Up"
		Write-Verbose "`t`tSource Values Procesed:`t$ProcessedCount"
		Write-Verbose "`t`tNew Items Created:`t$NewCount"
		Write-Verbose "`t`tPre-Existing Items:`t$ExistingCount"
		Write-Verbose "`t`tFailed Items:`t$FailedCount"
		Write-Verbose "`t`tTotal Execution Duration (sec):`t$FinalLoopTime"
		Write-Verbose ""
		Write-Verbose ""

        Write-Progress -Id 10 -Activity "$FunctionName" -Status "Finished" -Completed

        Write-Host "ESAE Deployment process has completed with the following details:" -ForegroundColor Yellow
        Write-Host "`t`tSource Values Procesed:`t$ProcessedCount" -ForegroundColor Yellow
		Write-Host "`t`tFailed Items:`t$FailedCount" -ForegroundColor Yellow
        Write-Host "`t`tTotal Execution Duration (sec):`t$FinalLoopTime" -ForegroundColor Yellow
        Write-Host "`t`tLog File Location:`t$ADDLogPath" -ForegroundColor Yellow
        Write-Host "`t`t`tNotes: Log files will start with 'ADDeploy' followed by the date and time the module was imported." -ForegroundColor Yellow
        Write-Host "`t`t`t       If log file size exceeded 30MB, there will be additional numbered files in ascending order (New/low to Old/high)." -ForegroundColor Yellow
        Write-Host "`t`t`t       You will need to unload the ADDeploy module or close the shell to flush all entries to disk." -ForegroundColor Yellow
        Write-Host ""
        if($MultiThread){
            Write-Host "`t`t`tSecondary Note: The deployment was run with MultiThreading. As a result, the log file content will not be in sequence, and some entries may be missing due to multi-process file locks."
        }

        Write-Verbose "------------------- $($FunctionName): End -------------------"
        Write-Verbose ""
        Write-Verbose ""
    }

}