function New-ADDGPObject {
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
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="ChainRun",ConfirmImpact='Low')]
    Param (
		[Parameter(ParameterSetName="ManualRunA",Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[string[]]$StartOU,

        [Parameter(ParameterSetName="RestoreRun",Mandatory=$true)]
        [Parameter(ParameterSetName="ChainRun")]
        [ValidateScript({Test-Path $_ -PathType Container})]
		[string]$GPRestoreSource,

        [Parameter(ParameterSetName="RestoreRun")]
        [Parameter(ParameterSetName="ChainRun")]
		[switch]$MultiThread,

        [Parameter(ParameterSetName="ManualRunA")]
        [Parameter(ParameterSetName="ManualRunB")]
        [Parameter(ParameterSetName="ChainRun")]
        [int]$PipelineCount,

        [Parameter(ParameterSetName="ChainRun",ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.DirectoryServices.DirectoryEntry]$TargetDE
    )

    Begin {
        $FunctionName = $pscmdlet.MyInvocation.MyCommand.Name
		Write-Verbose "$($LP)------------------- $($FunctionName): Start -------------------"
        Write-Verbose ""

        Write-Verbose "$($LPB1)Run Type:`t$($pscmdlet.ParameterSetName)"
        $Pipe = $false  # Force initial value to false

        switch ($pscmdlet.ParameterSetName) {
            {$_ -like "ManualRun*"} {
                $Action = "Create"

                if($pscmdlet.MyInvocation.ExpectingInput){
                    Write-Verbose "$($LPB2)Pipeline:`tDetected"
                    $Pipe = $true
                }else{
                    Write-Verbose "Pipeline:`tNot Detected"
                }
            }

            {$_ -like "RestoreRun"} {
                $Action = "Restore"
                Write-Verbose "$($LPB2)TargetType:`tBackupDirectory - Restore/Import"

                if(Test-Path -Path $(Join-Path -Path $GPRestoreSource -ChildPath "manifest.xml")){
                    $RestoreObjects = Get-ChildItem -Path $GPRestoreSource -Directory
                    if($($RestoreObjects.Count) -gt 1){
                        Write-Verbose "$($LPB2)Pipeline:`tDetected"
                        $PipelineCount = $RestoreObjects.Count
                        $Pipe = $true
                    }else {
                        Write-Verbose "Pipeline:`tNot Detected"
                    }

                    $GPMTPath = Join-Path -Path $ENV:TEMP -ChildPath "MigrationTable.migtable"

                    Write-Verbose "$($LPB2)TestSourceResult:`tSuccess"
                }else {
                    Write-Verbose "$($LPB2)TestSourceResult:`tFail"
                    Write-Error "$($LPB2)No backup manifest was detect in specified location - Quitting"
                    break
                }
            }

            {$_ -like "ChainRun"} {
                if($TargetDE){
                    $Action = "Create"
                    Write-Verbose "$($LPB2)Pipeline:`tDetected"
                    $Pipe = $true

                    Write-Verbose "$($LPB2)TargetType:`tOrgUnitObject(s) - Create New"
                }

                if($GPRestoreSource){
                    $Action = "Restore"
                    Write-Verbose "$($LPB2)TargetType:`tBackupDirectory - Restore/Import"

                    if(Test-Path -Path $(Join-Path -Path $GPRestoreSource -ChildPath "manifest.xml")){
                        $RestoreObjects = Get-ChildItem -Path $GPRestoreSource -Directory
                        if($($RestoreObjects.Count) -gt 1){
                            Write-Verbose "$($LPB2)Pipeline:`tDetected"
                            $PipelineCount = $RestoreObjects.Count
                            $Pipe = $true
                        }else {
                            Write-Verbose "Pipeline:`tNot Detected"
                        }

                        if(Test-Path -Path $(Join-Path -Path $GPRestoreSource -ChildPath "MigrationTable.migtable")){
                            $GPMTPath = Join-Path -Path $GPRestoreSource -ChildPath "MigrationTable.migtable"
                            $GPMTCreate = $false
                        }else {
                            $GPMTPath = Join-Path -Path $ENV:TEMP -ChildPath "MigrationTable.migtable"
                            $GPMTCreate = $true
                        }

                        Write-Verbose "$($LPB2)TestSourceResult:`tSuccess"
                    }else {
                        Write-Verbose "$($LPB2)TestSourceResult:`tFail"
                        Write-Error "$($LPB2)No backup manifest was detect in specified location - Quitting"
                        break
                    }
                }
            }
        }

        if($Pipe){
            Write-Debug "$($LPB2)Initiating Progress Tracking"
            Write-Progress -Id 15 -Activity "Deploy Group Policy Components" -CurrentOperation "Initializing..." -ParentId 10
		}

        Write-Verbose "$($LPB1)Setting supplemental run values..."

        $GPOFocuses = @("User","Computer")
        $GuidRe = '(?<={)(.*?)(?=})'

        $loopTimer = [System.Diagnostics.Stopwatch]::new()
        $subloopTimer = [System.Diagnostics.Stopwatch]::new()
        $loopTimes = @()
    }

    Process {
        Write-Verbose ""
        Write-Verbose "$($LPP1)`t`t****************** Start of loop ($loopCount) ******************"
        Write-Verbose ""
        $loopTimer.Start()

        if($GCloopCount -eq 20){
            Write-Verbose ""
            Write-Debug "$($LPP2)`t`tInitiating forced garbage collection (memory cleanup)"
            $MemoryUsed = [System.gc]::GetTotalMemory("forcefullcollection") /1MB
            Write-Debug "$($LPP3)`t`tCurrent Memory in Use (Loop 20) - $($MemoryUsed) - Initiating cleanup"
            [System.GC]::Collect()
            [System.gc]::GetTotalMemory("forcefullcollection") | Out-Null
            [System.GC]::Collect()
            $PostCleanupMemoryUsed = [System.gc]::GetTotalMemory("forcefullcollection") /1MB
            Write-Debug "$($LPP3)`t`tPost-Cleanup Memory in Use - $($MemoryUsed) MB - Resetting Loop Count"
            $GCloopCount = 0
            Write-Verbose ""
        }

        switch ($Action) {
            {$_ -like "Restore"} {
                Write-Progress -Id 15 -Activity "GPO: Import-Restore" -CurrentOperation "Analyzing backups..." -ParentId 10

                $GPCom = New-Object -ComObject GPmgmt.GPM
                $GPConst = $GPCom.GetConstants()
                $GPDomain = $GPCom.GetDomain($ENV:USERDNSDOMAIN,$Null,$GPConst.UseAnyDc)

                $GPBackupDir = $GPCom.GetBackupDir($GPRestoreSource)
                $GPSearch = $GPCom.CreateSearchCriteria()
                $GPSearch.Add($GPConst.SearchPropertyBackupMostRecent,$GPConst.SearchOpEquals,$true)
                $BackupList = $GPBackupDir.SearchBackups($GPSearch)

                $MigrationTable = $GPCom.CreateMigrationTable()

                foreach($GPBackup in $BackupList){
                    $BackupGPDom = $GPBackup.GPODomain
                    $MigrationTable.Add(0,$GPBackup)
                    $MigrationTable.Add($GPConst.ProcessSecurity,$GPBackup)
                }

                $mtEntries = $MigrationTable.GetEntries()

                foreach($Entry in $mtEntries){

                }
                $MigrationTable.Save($GPMTPath)
            }

            {$_ -like "Create"} {
                Write-Progress -Id 15 -Activity "GPO: Create New" -CurrentOperation "Initiating deployment..." -ParentId 10

            }
        }
    }

    End {

    }

}