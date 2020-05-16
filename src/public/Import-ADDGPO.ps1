function Import-ADDGPO {
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
            Help Last Updated: 10/24/2019

            Cmdlet Version 0.1.0 - Alpha

			Copyright (c) Topher Whitfield All rights reserved.

			Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
			source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
			own risk, and the author assumes no liability.

		.LINK
			https://mer-bach.org
    #>
    [CmdletBinding(DefaultParameterSetName="Other")]
    Param(
        [parameter(Mandatory=$True,ParameterSetName="All")]
        [ValidateScript({Test-Path -Path $_})]
        [String]$BackupFolder,

        [Parameter(ParameterSetName="All")]
        [Switch]$MultiThread,

		[Parameter(ParameterSetName="All")]
		[int]$MTMultiplier=3,

        [parameter(Mandatory=$False,ParameterSetName="All")]
        [ValidateRange(0,2)]
        [Int]$TierID,

        [parameter(Mandatory=$False,ParameterSetName="All")]
        [String]$FocusID,

        [Parameter(ParameterSetName="SupOnly")]
		[switch]$SupOnly
    )

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

		if($MultiThread){
			$MTRun = $true
			if($MTMultiplier -gt 4){
				$MTMultPrompt = Prompt-Options -PromptInfo @("Multi-Thread Multiplier Warning","This option specifies the multiplier used to determine the number of threads based on CPU count, which substantically increases the memory and CPU utilization on the host where it is being run. Please confirm your selection.") -Options "Proceed","Change Value","Quit"

				switch ($MTMultPrompt) {
					0 {
						Write-Verbose "`t`tMultiplier Confirmed:`tYes"
						[int]$MTcount = ((Get-WMIObject Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum) * $MTMultiplier
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
				ApartmentState = "MTA"
				Count = $MTCount
			}
		}else {
			$MTRun = $false
		}

        Write-Verbose "$($LPB1)Run Type:`t$($pscmdlet.ParameterSetName)"
        Write-Verbose "$($LPB1)Setting supplemental run values..."

        if(!($MTRun)){
			Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Initializing..." -ParentId 10
        }

        $SOMReportCSV = Join-Path -Path $BackupFolder -ChildPath "GpoInformation.csv"
		$MigrationTable = Join-Path -Path $BackupFolder -ChildPath "MigrationTable.migtable"
		$CustomGpoXML = Join-Path -Path $BackupFolder -ChildPath "GPODetails.xml"

        if(Test-Path $CustomGpoXML){
            $CustomGpoInfo = Import-Clixml -Path $CustomGpoXML
            $SourceDomainDN = ($CustomGpoInfo | Select-Object -First 1).DomainDN
			$SourceDomain = ($SourceDomainDN -replace "DC=","") -replace ",","."
            $CustInfo = $True
        }else {
            Write-Warning "GPO export details not found - proceeding with raw restore"
            $CustInfo = $False
            #TODO: Add steps to retrieve data from backup content as different source name
        }

        if(Test-Path $SOMReportCSV){
			$SOMData = @()
            $SOMImportData = Import-Csv $SOMReportCSV
			if(!($CustInfo)){
				$SourceDomainDN = (select-string -InputObject (($SOMData | Select-Object -First 1).gposominfo -split ":")[0] -Pattern $DomDnRegEx).Matches.Value
				$SourceDomain = ($SourceDomainDN -replace "DC=","") -replace ",","."
			}

			foreach($SOM in $SOMImportData){
				if([bool]$SOM.GPOName -and [bool]$SOM.GPOSomInfo){
					$SOMData += $SOM
				}
			}

			if($SOMData.Count -gt 0){
				$SOMInfo = $True
			}
        }else {
            $SOMInfo = $False
        }

        try {
            $GPM = New-Object -ComObject GPMgmt.GPM
        }   #end of Try...
        catch {
            Write-Error "Failed to connect to GPMC - Ensure GPMC is installed - Quitting"
            break
        }

        $Constants = $GPM.getConstants()
        $GpmDomain = $GPM.GetDomain($DomName,$Null,$Constants.UseAnyDc)

        $RestoreResults = New-Object System.Collections.Generic.List[Microsoft.GroupPolicy.Gpo]

        if(Test-Path $MigrationTable){
            $MigTable = $True
			$MigTableData = $GPM.GetMigrationTable($MigrationTable)
			foreach($MTEntry in $MigTableData.GetEntries()){
				switch ($MTEntry.Source) {
					{$_ -like "S-1-5-*"} {
						$MigTableData.DeleteEntry($MTEntry.Source)
					}

					{$_ -match "\@"} {
						if($SourceDomain -notlike $DomName){
							$Dest = $MTEntry.Source -Replace $SourceDomain,$DomName
							$MigTableData.UpdateDestination($MTEntry.Source, $MTEntry.Source.Replace("@$($SourceDomain)","@$($DomName)")) | Out-Null
						}
						$Dest = $MTEntry.Source
					}
				}
			}

			$MigTableData.Save($MigrationTable)
        }else {
            $MigTable = $False
        }

		$GPRegExSuf = '(User|Computer)$'

		if($TierID){
			$GPRegExPre = '^T' + $TierID + ''
		}else {
			$GPRegExPre = '^(' + $($TierRegEx) + ')'
		}

		if($FocusID){
			$GPRegExMid = '_' + $FocusID + '.+?'
		}else {
			$GPRegExMid = '_(' + $FocusRegEx + ').+?'
		}

		$GPRegEx = $GPRegExPre + $GPRegExMid + $GPRegExSuf

		$strBackup = $GPM.GetBackupDir($BackupFolder)
		$GPMSearchCriteria = $GPM.CreateSearchCriteria()
		$BackupGPOs = $strBackup.SearchBackups($GPMSearchCriteria)

		$RestoreGPOs = $BackupGPOs | Where-Object {$_.GPODisplayName -match $GPRegEx}

		if(!($RestoreGPOs.Count -gt 0)){
			if($SOMInfo){
				Write-Error "No relevant backups found using specified RegEx - $GPRegEx - Will attempt to process supplemental restore only" -ErrorAction Continue
				$SupOnly = $True
			}else {
				Write-Error "No relevant backups found using specified RegEx - $GPRegEx - No supplemental data to process - Quitting" -ErrorAction Stop
			}
		}

        $ProcessedCount = 0
		$LinksProcessedCount = 0
		$SupProcessedCount = 0
        $LinkedCount = 0
        $FailedCount = 0
        $LinkFailedCount = 0
		$GCloopCount = 1
		$loopCount = 1
		$subloopCount = 1

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
		$subloopTimer = [System.Diagnostics.Stopwatch]::new()
		$loopTimes = @()

		Write-Verbose ""
    }

    Process {
		Write-Verbose ""
		Write-Verbose "$($LPP1)****************** Start of loop ($loopCount) ******************"
		Write-Verbose ""
		$loopTimer.Start()

        if($MultiThread){
			Write-Verbose "$($LPP2)MultiThread:`t$True"
			$MTdata = @{
				Count = $BackupGPOs.Count
				Done = 0
				ProcessedCount = 0
				FailedCount = 0
			}

            $rsSplit = $RestoreGPOs | Split-Pipeline @MTParams -Module GroupPolicy -Variable BackupFolder,DomName,MigrationTable,MTdata -Script { Process {
				$RestoreParams = @{
					Path = $BackupFolder;
					Domain = $DomName;
					CreateIfNeeded = $True;
				};

				if($MigrationTable){
					$RestoreParams.Add("MigrationTable",$MigrationTable)
				};

				Write-Verbose "MT Backup Target:`t$($_.DisplayName)"
				try {
					$Result = Import-GPO -BackupId $_.ID -TargetName $_.GPODisplayName @RestoreParams
					Write-Verbose "Task Outcome:`tSuccess"
				}
				catch {
					Write-Verbose "Task Outcome:`tFailed"
				}


				Write-Verbose "Update Processed Count"
				[System.Threading.Monitor]::Enter($MTdata)
					try{
						$Done = ++$MTdata.Done
						if($Result){
							$Processed = ++$MTdata.ProcessedCount
						}else{
							$Failed = ++$MTdata.FailedCount
						}
						Write-Verbose "Task Outcome:`tSuccess"
					}
					catch {
						Write-Verbose "Task Outcome:`tFailed"
					}

					finally {
						[System.Threading.Monitor]::Exit($MTdata)
					}

					if($Done -gt 1){
						$PercentComplete = ($Done / ($MTdata.Count)) * 100
					}else {
						$PercentComplete = 0
					}

						Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Running multi-threaded restore..." -PercentComplete $PercentComplete -ParentId 10

				} }

			if($rsSplit){
				$ValidateLoopCount = 1

				foreach($rs in $rsSplit){
					if($GCloopCount -eq 20){
						Run-MemClean
						$GCloopCount = 0
					}

					if($ValidateLoopCount -gt 1){
						$ValidatePercent = ($ValidateLoopCount / ($rsSplit.Count)) * 100
					}else{
						$ValidatePercent = 0
					}

					Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Validating results..." -PercentComplete $ValidatePercent -ParentId 10

					$RestoreResults.Add($rs)

					$ValidateLoopCount ++
					$ProcessedCount ++
					$loopCount ++
					$GCloopCount ++
				}

				if($BackupResults.Count -lt $BackupGPOs.Count){
					$FailedCount = $($($BackupGPOs.Count) - $($BackupResults.Count))
				}
			}else{
				if($SOMInfo){
					Write-Error "No values returned from multi-thread restore process - Attempting supplemental data restore anyway" -ErrorAction Continue
				}else {
					Write-Error "No values returned from multi-thread restore process - No supplemental data to restore - Quitting" -ErrorAction Stop
				}
			}
        }else{
            if(!($SupOnly)){
                $PipelineCount = $RestoreGPOs.Count
                $GCloopCount = 0

                foreach($CustomGPO in $RestoreGPOs){
                    Write-Verbose "$($LPP2)Restore GPO:`t$($CustomGPO.GPODisplayName)"
                    if($GCloopCount -eq 20){
                        Run-MemClean
						$GCloopCount = 0
                    }

                    if($ProcessedCount -gt 1){
                        $PercentComplete = ($ProcessedCount / $PipelineCount) * 100
                    }else{
                        $PercentComplete = 0
                    }

					if(!($MTRun)){
						Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Running single-threaded restore..." -PercentComplete $PercentComplete -ParentId 10
					}

                    $RestoreParams = @{
                        BackupId = $CustomGPO.ID
                        Path = $BackupFolder
                        CreateIfNeeded = $True
                        Domain = $DomName
                        TargetName = $CustomGPO.GPODisplayName
                        ErrorAction = "SilentlyContinue"
                    }

                    if($MigTable){
                        $RestoreParams.Add("MigrationTable",$MigrationTable)
                    }

                    try {
                        $RestoredGPO = Import-GPO @RestoreParams

                        if($RestoredGPO){
                            Write-Verbose "$($LPP3)Task Outcome:`tSuccess"
                            $RestoreResults.Add($RestoredGPO)
                            $ProcessedCount ++
                            $loopCount ++
                            $GCloopCount ++
                        }
                    }
                    catch {
                        Write-Verbose "$($LPP3)Task Outcome:`tFailed"
                        $FailedCount ++
                    }
                }
            }
        }

		if($SOMInfo){
			$PipelineCount = $SOMData.Count

			foreach($SOMEntry in $SOMData){
				if($SupProcessedCount -gt 1){
					$PercentComplete = ($SupProcessedCount / $PipelineCount) * 100
				}else{
					$PercentComplete = 0
				}

				Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Restoring supplemental info..." -Status "$($SOMEntry.GPOName)" -PercentComplete $PercentComplete -ParentId 10

				try {
					$rsGPO = Get-GPO -Name $($SOMEntry.GPOName)
				}
				catch {
					Write-Error "Failed to find or retrieve a GPO with the specified name ($($SOMEntry.GPOName)) - Skipping to next item" -ErrorAction Continue
					$SupProcessedCount ++
					break
				}
				Write-Verbose "Task - Restore GPO Links:`t$($rsGPO.DisplayName) "

				if($SOMEntry.GpoSomInfo -and $rsGPO){
					$ExpectedLinks = ($SOMEntry.GpoSomInfo).Count
					$SuccessLinks = 0
					$FailedLinks = 0

					ForEach ($SOM in $SOMEntry.GpoSomInfo) {
						$SomDN = $SOM.Split(":")[0]
						$SomDN = $SomDN -Replace $SourceDomainDN,$DomDN

						$LinkSplat = @{
							Guid = $rsGPO.Id
							Domain = $DomName
							Target = $SomDN
							Order = $SOM.Split(":")[3]
						}

						if($($SOM.Split(":")[2])){
							$LinkSplat.Add("LinkEnabled","Yes")
						}else {
							$LinkSplat.Add("LinkEnabled","No")
						}

						if($($SOM.Split(":")[4])){
							$LinkSplat.Add("Enforced","Yes")
						}else {
							$LinkSplat.Add("Enforced","No")
						}

						Write-Verbose "Task - Link GPO:`t$SOMDN"

						try {
							$SomLink = New-GPLink @LinkSplat
							Write-Verbose "Task Outcome:`tSuccess"
							$LinkStatus = $True
							$SuccessLinks ++
						}
						catch {
							Write-Verbose "Task Outcome:`tFailed"
							$LinkStatus = $False
							$FailedLinks ++
						}

						if($($SOM.Split(":")[1])){
							try {
								$SomInheritance = Set-GPInheritance -Target $SomDN -IsBlocked Yes
							}
							catch {
								Write-Verbose "Couldn't set Inheritance"
							}
						}
					}

					if($SuccessLinks -eq $ExpectedLinks){
						Write-Verbose "Restore Links Outcome:`tSuccess"
						$LinksProcessedCount ++
					}else{
						Write-Verbose "Restore Links Outcome:`tFailed"
						$LinkFailedCount ++
					}
				}

				$SupProcessedCount ++
			}
		}

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
        Write-Verbose ""
        Write-Verbose "Wrapping Up"
        Write-Verbose "`t`tGPOs Imported:`t$ProcessedCount"
        Write-Verbose "`t`tGPO Imports Failed:`t$FailedCount"
        Write-Verbose "`t`tGPOs Supplemental Processed:`t$SupProcessedCount"
        Write-Verbose "`t`tGPO Links Successful:`t$LinksProcessedCount"
        Write-Verbose "`t`tGPO Links Failed:`t$LinkFailedCount"
        Write-Verbose ""

		if(!($MTRun)){
			Write-Progress -Id 15 -Activity "Import GPOs" -CurrentOperation "Finished" -Completed -ParentId 10
		}

        if($ChainRun){
            Write-Verbose "$($LPB1)Chain Run - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            return $RestoreResults
        }else {
            Write-Verbose "$($LPB1)Chain Run Not Detected - Writing status to host"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Host "Import process has completed - Imported $($ProcessedCount) of $($RestoreGPOs.Count) targeted GPOs" -ForegroundColor Yellow
        }
    }
}