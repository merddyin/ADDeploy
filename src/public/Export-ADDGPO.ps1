function Export-ADDGPO {
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
		Module developed by Chris Whitfield, Topher Whitfield for deploying and maintaining an 'Orange Forest' environment. All use and distribution rights remain in force
		and the sole province of the module author.This source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within
		your environment is done at your own risk, and the author assumes no liability.

		Help Last Updated: 10/24/2019

		Cmdlet Version 0.1.0 - Alpha

	.LINK
		https://mer-bach.org
#>
	[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
	param (
		[Parameter(Position=0,Mandatory=$true)]
		[ValidateScript({Test-Path $_})]
		[string]$BackupFolder,

		[Parameter()]
		[Switch]$MultiThread,

		[Parameter()]
		[int]$MTMultiplier=3,

		[Parameter()]
		[ValidateSet(15,30,45,60,90)]
		[int]$ModifiedDays,

		[Parameter()]
		[ValidateSet(0,1,2)]
		[int]$TierID,

		[Parameter()]
		[string]$FocusID
	)

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
        Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
		Write-Verbose ""
		#TODO: Change mechanism for supplemental info collection - Possibly GPInheritance native cmdlets, or maybe SDM depending on redistribution rights?

		if($MultiThread){
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
		}

        Write-Verbose "$($LPB1)Setting supplemental run values..."

        Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Initializing..." -ParentId 10

        $FileDate = (Get-Date).ToString("dd-MM-yyyy-hhmmss")
		Write-Verbose "$($LPB1)BackupFolder:`t$BackupFolder"

        $SubBackupFolder = Join-Path -Path $BackupFolder -ChildPath $FileDate
		Write-Verbose "$($LPB1)SubBackupFolder:`t$SubBackupFolder"
        $CustomGpoXML = Join-Path -Path $SubBackupFolder -ChildPath "GpoDetails.xml"
        $SOMReportCSV = Join-Path -Path $SubBackupFolder -ChildPath "GpoInformation.csv"

		Write-Verbose "$($LPB2)Create SubBackupFolder"

        $BKFolder = New-Item -ItemType Directory -Path $SubBackupFolder -Force
        if(!($BKFolder)){
			Write-Verbose "$($LPB2)Task Outcome:`tFailed"
            Write-Error "Failed to create backup folder - Quitting"
            break
        }else{
			Write-Verbose "$($LPB2)Task Outcome:`tSuccess"
		}

        if($NoMigTable){
            $MigTable = $False
        }else {
            $MigTable = $True
            $MigrationFile = Join-Path -Path $SubBackupFolder -ChildPath "MigrationTable.migtable"
        }

		$AdminsGroup = [adsi]"LDAP://CN=Administrators,CN=Builtin,$DomDN"
		[byte[]]$AdminsSid = $AdminsGroup.objectSid.value
		$AdminsGrpSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $AdminsSid, 0
		$ADRights = "CreateChild, DeleteChild, Self, WriteProperty, DeleteTree, Delete, GenericRead, WriteDacl, WriteOwner"
		$ADAceDef = $AdminsGrpSid,$ADRights,"Allow","Self",$allguid
		$ADMGrpAce = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($ADAceDef)

        try {
            $GPM = New-Object -ComObject GPMgmt.GPM
        }   #end of Try...
        catch {
            Write-Error "Failed to connect to GPMC - Ensure GPMC is installed - Quitting"
            break
        }

        $Constants = $GPM.getConstants()
        $GpmDomain = $GPM.GetDomain($DomName,$Null,$Constants.UseAnyDc)

        $BackupResults = New-Object System.Collections.Generic.List[Microsoft.GroupPolicy.GpoBackup]
        $BackupOutput = New-Object System.Collections.Generic.List[psobject]

        $AllGPOs = Get-GPO -All

		if($AllGPOs){
			Write-Verbose "$($LPB1)All GPO Count:`t$($AllGPOs.Count)"
		}else{
			Write-Error "Failed to retrieve any GPOs to process - Quitting" -ErrorAction Stop
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

		$BackupGPOs = $AllGPOs | Where-Object { $_.DisplayName -match $GPRegEx }

		if($ModifiedDays){
			$BackupGPOs = $BackupGPOs | Where-Object { $_.ModificationTime -gt $(Get-Date).AddDays(-$ModifiedDays) }
		}

		if($BackupGPOs){
			Write-Verbose "$($LPB1)Filt GPO Count:`t$($BackupGPOs.Count)"
		}else{
			if(!($pscmdlet.MyInvocation.ExpectingInput)){
				Write-Error "No GPOs returned after filtering - Quitting" -ErrorAction Stop
			}
		}

        $ProcessedCount = 0
		$AclProcessedCount = 0
        $FailedCount = 0
		$AclFailedCount = 0
        $SupplementCount = 0
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

        if($PipeLine){
			Write-Verbose "$($LPP2)Pipeline:`t$True"
            #TODO: Add pipeline handling for process section
        }else {
			Write-Verbose "$($LPP2)Pipeline:`t$False"

            if($MultiThread){
				Write-Verbose "$($LPP2)MultiThread:`t$True"
				$MTdata = @{
					Count = $BackupGPOs.Count
					Done = 0
					ProcessedCount = 0
					FailedCount = 0
				}

				$ForceAcls = $BackupGPOs | Split-Pipeline @MTParams -Variable ADMGrpAce,MTdata -Script { Process {
					Write-Verbose "MT SetAcl Target:`t$($_.DisplayName)"
					$gpde = [adsi]"LDAP://$($_.Path)"
					$gpde.psbase.ObjectSecurity.AddAccessRule($ADMGrpAce)
					try {
						$gpde.psbase.CommitChanges()
						Write-Verbose "Task Outcome:`tSuccess"
						$Result = $true
					}
					catch {
						Write-Verbose "Task Outcome:`tFailed"
						$Result = $false
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

					Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Validating permissions for targets..." -PercentComplete $PercentComplete -ParentId 10

					} }

				$AclProcessedCount = $MTdata.ProcessedCount
				$AclFailedCount = $MTdata.FailedCount

				Write-Verbose "$($LPP2)Initiate MultiThread Backup"
				$MTdata = @{
					Count = $BackupGPOs.Count
					Done = 0
					ProcessedCount = 0
					FailedCount = 0
				}

                $BKSplit = $BackupGPOs | Split-Pipeline -Module GroupPolicy -Variable MTData,SubBackupFolder,DomName @MTParams -Script { Process {
					Write-Verbose "MT Backup Target:`t$($_.DisplayName)"
					try {
						$_ | Backup-GPO -Path $SubBackupFolder -Domain $DomName -Comment "Backup up using ADDADDeploy - Export-ADDGPO (MT)"
						Write-Verbose "Task Outcome:`tSuccess"
						$Result = $true
					}
					catch {
						Write-Verbose "Task Outcome:`tFailed"
						$Result = $false
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

					Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Running multi-threaded GPO backup..." -PercentComplete $PercentComplete -ParentId 10

				} }

				$ProcessedCount = $MTdata.ProcessedCount
				$FailedCount = $MTdata.FailedCount

				if($BKSplit){
					$ValidateLoopCount = 1

					foreach($bk in $BKSplit){
						if($GCloopCount -eq 20){
							Run-MemClean
							$GCloopCount = 0
						}

						if($ValidateLoopCount -gt 1){
							$ValidatePercent = ($ValidateLoopCount / ($BKSplit.Count)) * 100
						}else{
							$ValidatePercent = 0
						}

						Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Validating results..." -PercentComplete $ValidatePercent -ParentId 10

						$BackupResults.Add($bk)

						$ValidateLoopCount ++
						$loopCount ++
						$GCloopCount ++
					}

					if($BackupResults.Count -lt $BackupGPOs.Count){
						$FailedCount = $($($BackupGPOs.Count) - $($BackupResults.Count))
					}
				}else{
					Write-Error "No values returned from multithreaded backup - Quitting"
					break
				}
            }else{
                $PipelineCount = $BackupGPOs.Count
                $GCloopCount = 0

                Foreach($BackupGPO in $BackupGPOs){
                    Write-Verbose "$($LPP2)Backup GPO:`t$($BackupGPO.DisplayName)"
                    if($GCloopCount -eq 20){
                        Run-MemClean
						$GCloopCount = 0
                    }

                    if($ProcessedCount -gt 1){
                        $PercentComplete = ($ProcessedCount / $PipelineCount) * 100
                    }else{
                        $PercentComplete = 0
                    }

                    Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Running single-threaded backup..." -PercentComplete $PercentComplete -ParentId 10

					$gpde = [adsi]"LDAP://$($BackupGPO.Path)"
					$gpde.psbase.ObjectSecurity.AddAccessRule($ADMGrpAce)

					try {
						$gpde.psbase.CommitChanges()
					}
					catch {

					}

                    try {
                        $bk = $BackupGPO | Backup-GPO -Path $SubBackupFolder -Comment "Backup up using ADDADDeploy - Export-ADDGPO (ST)"
                        if($bk){
                            Write-Verbose "$($LPP3)Task Outcome:`tSuccess"
                            $BackupResults.Add($bk)
                            $ProcessedCount ++
                        }
                    }
                    catch {
                        Write-Verbose "$($LPP3)Task Outcome:`tFailed"
                        $FailedCount ++
                    }

                    $loopCount ++
                    $GCloopCount ++
                }
            }
        }

        $PipelineCount = $BackupResults.Count
        $GCloopCount = 0

		if($BackupResults){
			foreach($Result in $BackupResults){
				if($GCloopCount -eq 20){
					Run-MemClean
					$GCloopCount = 0
				}

				if($SupplementCount -gt 1){
					$PercentComplete = ($SupplementCount / $PipelineCount) * 100
				}else{
					$PercentComplete = 0
				}

				Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Collecting supplemental info..." -PercentComplete $PercentComplete -ParentId 10

				$GpoGuid = $Result.GpoId
				$BackupGuid = $Result.Id
				$GPO = $GpmDomain.GetGPO("{$GpoGuid}")
				$GpoName = $GPO.DisplayName
				$GpoID = $GPO.Id
				$GpmSearchCriteria = $GPM.CreateSearchCriteria()
				$GpmSearchCriteria.Add($Constants.SearchPropertySOMLinks,$Constants.SearchOpContains,$GPO)
				$SOMs = $GpmDomain.SearchSOMs($GpmSearchCriteria)
				$SomInfo = @()

				foreach($SOM in $SOMs){
					$SomDN = $SOM.Path
					$SomInheritance = $SOM.GPOInheritanceBlocked
					$GpoLinks = $SOM.GetGPOLinks()

					foreach ($GpoLink in $GpoLinks) {
						if ($GpoLink.GPOID -eq $GpoID) {
							#Capture the GPO link status
							$LinkEnabled = $GpoLink.Enabled

							#Capture the GPO precedence order
							$LinkOrder = $GpoLink.SOMLinkOrder

							#Capture Enforced state
							$LinkEnforced = $GpoLink.Enforced
						}
					}

					$SomInfo += "$SomDN`:$SomInheritance`:$LinkEnabled`:$LinkOrder`:$LinkEnforced"
				}

				$Wmifilter = ($AllGPOs | Where-Object{$_.DisplayName -like $GpoName}).WMifilter.Path
				if($Wmifilter){
					$WMifilter = ($Wmifilter -split '"')[1]
				}

				$GpoInfo = [PSCustomObject]@{
					Id = $BackupGuid
					GPODisplayName = $GpoName
					GpoGuid = $GpoGuid
					SOMs = $SomInfo
					DomainDN = $DomDN
					Wmifilter = $Wmifilter
				}

				$BackupOutput.Add($GpoInfo)

				$SupplementCount ++
			}
		}else{
			Write-Error "No backup results returned! Processing failed"
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
        Write-Verbose "`t`tGPOs Backed Up:`t$ProcessedCount"
        Write-Verbose "`t`tSOM Info Collected:`t$SupplementCount"
        Write-Verbose "`t`tGPO Backups Failed:`t$FailedCount"
        Write-Verbose ""

		$BackupOutput | Export-Clixml $CustomGpoXML -Force

		$DumpOutputCount = 1

		$FirstCSVLine = '"GPOName","GPOGuid","GPOSomInfo"'
		Add-Content -Path $SOMReportCSV -Value $FirstCSVLine

        foreach($CustomGPO in $BackupOutput){
			if($DumpOutputCount -gt 1){
				$DumpPercentComplete = ($DumpOutputCount / ($BackupOutput.Count)) * 100
			}else{
				$DumpPercentComplete = 0
			}

			Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Dumping supplemental info to file..." -ParentId 10

            $CSVLine = "`"$($CustomGPO.Name)`",`"{$($CustomGPO.GPOGuid)}`","
            foreach($CSOM in $CustomGPO.SOMs){
                $CSVLine += "`"$CSOM`""
            }

            Add-Content -Path $SOMReportCSV -Value $CSVLine

			$DumpOutputCount ++
        }

        Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Creating Migration Table..." -ParentId 10

        if($MigTable){
            $MigrationTable = $GPM.CreateMigrationTable()
            $GpmBackupDir = $GPM.GetBackUpDir($SubBackupFolder)
            $GpmSearchCriteria = $GPM.CreateSearchCriteria()
            $GpmSearchCriteria.Add($Constants.SearchPropertyBackupMostRecent,$Constants.SearchOpEquals,$True)
            $BackedUpGPOs = $GpmBackupDir.SearchBackups($GpmSearchCriteria)

            foreach($BackedUpGPO in $BackedUpGPOs){
                $MigrationTable.Add($Constants.ProcessSecurity,$BackedUpGPO)
            }

            $MigrationTable.Save($MigrationFile)
        }

        Write-Progress -Id 15 -Activity "Export GPOs" -CurrentOperation "Finished" -Completed -ParentId 10

        if($ChainRun){
            Write-Verbose "$($LPB1)Chain Run - Returning results to caller"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            return $BackupResults
        }else {
            Write-Verbose "$($LPB1)Chain Run Not Detected - Writing status to host"
            Write-Verbose "$($LP)------------------- $($FunctionName): End -------------------"
            Write-Host "Export process has completed - Backed up $($ProcessedCount) of $($BackupGPOs.Count) targeted GPOs" -ForegroundColor Yellow
        }
    }
}